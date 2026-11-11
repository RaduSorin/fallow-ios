import SwiftUI

/// First run, one card at a time: welcome, reminders, backup, Face ID.
struct SetupFlow: View {
    @Environment(Vault.self) private var vault
    @Environment(\.openURL) private var openURL

    @State private var step = 0
    @State private var settings = VaultSettings()
    @State private var errorText: LocalizedStringResource?

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
    }

    @ViewBuilder
    private var card: some View {
        switch step {
        case 0: welcome
        case 1: reminders
        case 2: backup
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

    private var backup: some View {
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
        }
    }

    private var protection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpecimenLabel(text: "Privacy")
            Text("Lock it with Face ID.")
                .font(.notebookTitle())
            Text("Fallow makes a key that never leaves this iPhone. Only your face, or your phone passcode, can open it.")
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
}
