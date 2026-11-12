import SwiftUI
import UniformTypeIdentifiers

/// First run, one card at a time: welcome, reminders, backup, Face ID.
struct SetupFlow: View {
    @Environment(Vault.self) private var vault
    @Environment(Backup.self) private var backup
    @Environment(\.openURL) private var openURL

    @State private var step = 0
    @State private var settings = VaultSettings()
    @State private var errorText: LocalizedStringResource?
    /// A backup found in iCloud, so the first card can offer it.
    @State private var foundBackup = false
    @State private var restoring = false
    @State private var restoreError: LocalizedStringResource?
    @State private var picking = false
    @State private var pickedData: Data?
    @State private var askingPassphrase = false
    @State private var fromFile: VaultContents?

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.moss : Theme.cardBorder)
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityElement()
            .accessibilityLabel(Text("Step \(step + 1) of \(stepCount)"))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    card
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
                .padding(20)
        }
        .background(Theme.paper)
        .animation(.easeInOut(duration: 0.25), value: step)
        .task { foundBackup = await backup.hasBackup() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.fallowFile, .data]) { result in
            guard case .success(let url) = result else { return }
            do {
                pickedData = try TransferFile.readPicked(url)
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    askingPassphrase = true
                }
            } catch {
                restoreError = "That file could not be read."
            }
        }
        .sheet(isPresented: $askingPassphrase, onDismiss: {
            guard let fromFile else { return }
            self.fromFile = nil
            do {
                try vault.restore(fromFile)
            } catch {
                restoreError = "The key could not be saved. Check that your iPhone has a passcode, then try again."
            }
        }) {
            PassphraseSheet(mode: .open) { passphrase in
                guard let data = pickedData else { return }
                fromFile = try await Task.detached { try TransferFile.open(data, passphrase: passphrase) }.value
                pickedData = nil
            }
        }
    }

    /// Already used Fallow: bring it back from iCloud or from a .fallow file.
    private var bringBack: some View {
        NotebookCard {
            SpecimenLabel(text: "Already used Fallow?")
            if foundBackup {
                Text("There is a Fallow backup in your iCloud.")
                    .foregroundStyle(Theme.inkMuted)
            }
            HStack {
                Button {
                    restoreFromICloud()
                } label: {
                    if restoring { ProgressView() } else { Text("Restore from iCloud") }
                }
                .disabled(restoring)
                Spacer()
                Button {
                    picking = true
                } label: {
                    Text("Open a .fallow file")
                }
            }
            if let restoreError {
                Text(restoreError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func restoreFromICloud() {
        restoring = true
        restoreError = nil
        Task {
            defer { restoring = false }
            do {
                let contents = try await backup.restore()
                try vault.restore(contents)
            } catch BackupError.notFound {
                restoreError = "No backup found in this iCloud account."
            } catch BackupError.unavailable {
                restoreError = "iCloud is off on this iPhone. Sign in to iCloud in Settings, then try again."
            } catch BackupError.noKey {
                restoreError = "The backup key has not reached this iPhone. Turn on iCloud Keychain (Passwords), wait a minute and try again."
            } catch BackupError.wrongKey {
                restoreError = "The backup key on this iPhone does not open this backup."
            } catch {
                restoreError = "The backup could not be restored."
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        switch step {
        case 0: welcome
        case 1: reminders
        case 2: backupCard
        default: protection
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpecimenLabel(text: "Welcome")
            Text("A quiet pause, one month at a time.")
                .font(.notebookTitle())
            Text("Choose an intention for the month, keep a few small rhythms and look back at the end. What you write stays encrypted on this iPhone.")
                .foregroundStyle(Theme.inkMuted)
            NotebookCard {
                SpecimenLabel(text: "Language")
                Text("Fallow follows your iPhone language. You can switch between English and Romanian in the app's settings.")
                    .foregroundStyle(Theme.inkMuted)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Change language")
                }
            }
            bringBack
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpecimenLabel(text: "Reminders")
            Text("When should Fallow remind you?")
                .font(.notebookTitle())
            Text("Reminders stay on your phone. No server knows when they ring.")
                .foregroundStyle(Theme.inkMuted)
            NotebookCard {
                reminderRow(title: "Morning", value: $settings.morningReminder, fallback: 8 * 60 + 30)
                Divider().overlay(Theme.cardBorder)
                reminderRow(title: "Evening", value: $settings.eveningReminder, fallback: 21 * 60)
            }
        }
    }

    private func reminderRow(title: LocalizedStringResource, value: Binding<Int?>, fallback: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? fallback : nil }
            )) {
                Text(title)
            }
            if let minutes = value.wrappedValue {
                DatePicker(
                    selection: Binding(
                        get: { VaultSettings.date(fromMinutes: minutes) },
                        set: { value.wrappedValue = VaultSettings.minutes(from: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                ) {
                    Text("Time")
                }
            }
        }
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpecimenLabel(text: "Backup")
            Text("Keep a copy in your iCloud?")
                .font(.notebookTitle())
            Text("Fallow can save an encrypted copy in your own iCloud, so a new iPhone gets everything back. Apple cannot read it, and neither can we.")
                .foregroundStyle(Theme.inkMuted)
            NotebookCard {
                Toggle(isOn: $settings.iCloudBackup) {
                    Text("Encrypted iCloud backup")
                }
            }
            if foundBackup && settings.iCloudBackup {
                Text("Starting fresh replaces the backup already in your iCloud. To keep it, go back and choose Restore from iCloud.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var protection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpecimenLabel(text: "Privacy")
            Text("Lock it with Face ID.")
                .font(.notebookTitle())
            Text("Fallow makes a key that never leaves this iPhone. Only your face, or your phone passcode, can open it.")
                .foregroundStyle(Theme.inkMuted)
            Text("If you turn off the iPhone passcode, iOS removes this key and the journal on this iPhone can no longer be opened. The iCloud backup can bring it back.")
                .font(.footnote)
                .foregroundStyle(Theme.inkMuted)
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button {
                    step -= 1
                } label: {
                    Text("Back")
                }
            }
            Spacer()
            Button {
                if step < stepCount - 1 {
                    step += 1
                } else {
                    finish()
                }
            } label: {
                Group {
                    if step < stepCount - 1 {
                        Text("Continue")
                    } else {
                        Text("Protect with Face ID")
                    }
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func finish() {
        do {
            try vault.setUp(settings: settings)
        } catch {
            errorText = "The key could not be saved. Check that your iPhone has a passcode, then try again."
        }
    }
}

#Preview {
    SetupFlow()
        .environment(Vault(keyStore: InMemoryKeyStore(), fileURL: URL.temporaryDirectory.appending(path: "preview.fallow")))
        .environment(Backup(store: FolderBackupStore(url: URL.temporaryDirectory.appending(path: "preview.backup")), keys: InMemoryBackupKey()))
}
