import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// .fallow files. Not declared by the app, so it falls back to plain data.
    static var fallowFile: UTType { UTType(filenameExtension: TransferFile.fileExtension) ?? .data }
}

/// A sealed .fallow file, ready for the system's "Save to Files" sheet.
struct FallowDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.fallowFile, .data]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw TransferFile.Failure.notAFallowFile }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Me → Backup and transfer: the iCloud copy, and a .fallow file to move everything by hand.
struct BackupView: View {
    @Environment(Vault.self) private var vault
    @Environment(Backup.self) private var backup

    @State private var asking: PassphraseSheet.Mode?
    @State private var exportDocument: FallowDocument?
    @State private var importing = false
    @State private var importedData: Data?
    @State private var replacement: VaultContents?
    /// Made inside the passphrase sheet, shown once it has closed (one sheet at a time).
    @State private var afterSheet: (document: FallowDocument?, contents: VaultContents?) = (nil, nil)
    @State private var message: LocalizedStringResource?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { vault.contents?.settings.iCloudBackup ?? false },
                    set: { on in try? vault.update { $0.settings.iCloudBackup = on } }
                )) {
                    Text("Encrypted iCloud backup")
                }
                if vault.contents?.settings.iCloudBackup == true {
                    LabeledContent {
                        statusText
                    } label: {
                        Text("Last backup")
                    }
                    Button {
                        guard let contents = vault.contents else { return }
                        Task { await backup.backUp(contents) }
                    } label: {
                        Text("Back up now")
                    }
                    .disabled(backup.status == .saving)
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("The copy is sealed with a key kept in your iCloud Keychain, so a new iPhone signed in to your Apple Account can open it. Apple cannot read it, and neither can we.")
            }

            Section {
                Button {
                    asking = .export
                } label: {
                    Label { Text("Save to a file") } icon: { Image(systemName: "square.and.arrow.up") }
                }
                Button {
                    importing = true
                } label: {
                    Label { Text("Open a file") } icon: { Image(systemName: "square.and.arrow.down") }
                }
            } header: {
                Text("File")
            } footer: {
                Text("A .fallow file holds everything, locked with a passphrase you choose. Use it to move to another iPhone, or to bring Răgaz over from Kitchen Tales.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(Text("Backup and transfer"))
        .sheet(item: $asking, onDismiss: {
            exportDocument = afterSheet.document
            replacement = afterSheet.contents
            afterSheet = (nil, nil)
        }) { mode in
            PassphraseSheet(mode: mode) { passphrase in
                try await run(mode, passphrase: passphrase)
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .fallowFile,
            defaultFilename: TransferFile.suggestedName()
        ) { result in
            if case .success = result { message = "Saved. Keep the passphrase somewhere safe: without it the file cannot be opened." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.fallowFile, .data]) { result in
            guard case .success(let url) = result else { return }
            do {
                importedData = try TransferFile.readPicked(url)
                Task {
                    // Let the Files sheet finish closing first.
                    try? await Task.sleep(for: .milliseconds(400))
                    asking = .open
                }
            } catch {
                message = "That file could not be read."
            }
        }
        .confirmationDialog(
            Text("Replace what is on this iPhone?"),
            isPresented: Binding(get: { replacement != nil }, set: { if !$0 { replacement = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let replacement { try? vault.update { $0 = TransferFile.replacing($0, with: replacement) } }
                replacement = nil
                message = "Everything from the file is here now."
            } label: {
                Text("Replace")
            }
        } message: {
            Text("Your journal, months, exercises and herbarium here are replaced by the ones in the file.")
        }
        .alert(
            Text(message ?? ""),
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button { message = nil } label: { Text("OK") }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch backup.status {
        case .saving: Text("Saving…")
        case .unavailable: Text("iCloud is off on this iPhone")
        case .failed: Text("Not saved, will try again")
        case .saved(let date): Text(date, format: .relative(presentation: .named))
        case .off, .waiting: Text("Not yet")
        }
    }

    private func run(_ mode: PassphraseSheet.Mode, passphrase: String) async throws {
        switch mode {
        case .export:
            guard let contents = vault.contents else { return }
            let data = try await Task.detached { try TransferFile.seal(contents, passphrase: passphrase) }.value
            afterSheet.document = FallowDocument(data: data)
        case .open:
            guard let data = importedData else { return }
            let contents = try await Task.detached { try TransferFile.open(data, passphrase: passphrase) }.value
            importedData = nil
            afterSheet.contents = contents
        }
    }
}

extension TransferFile {
    /// Reads a file picked in the Files sheet (it may live outside the app's sandbox).
    static func readPicked(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}

/// Asks for the passphrase: twice when saving a file, once when opening one.
struct PassphraseSheet: View {
    enum Mode: String, Identifiable {
        case export, open
        var id: String { rawValue }
    }

    let mode: Mode
    let onDone: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var again = ""
    @State private var working = false
    @State private var error: LocalizedStringResource?

    private var ready: Bool {
        switch mode {
        case .export: TransferFile.normalized(passphrase).count >= TransferFile.minimumPassphrase && passphrase == again
        case .open: !passphrase.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(text: $passphrase) { Text("Passphrase") }
                        .textContentType(mode == .export ? .newPassword : .password)
                    if mode == .export {
                        SecureField(text: $again) { Text("Once more") }
                            .textContentType(.newPassword)
                    }
                } footer: {
                    if mode == .export {
                        Text("At least 8 characters. A short sentence is easy to remember and hard to guess. There is no way to recover it.")
                    } else {
                        Text("The passphrase chosen when the file was saved.")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(mode == .export ? Text("Save to a file") : Text("Open a file"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button { submit() } label: {
                            if mode == .export { Text("Save") } else { Text("Open") }
                        }
                        .disabled(!ready)
                    }
                }
            }
        }
        .interactiveDismissDisabled(working)
    }

    private func submit() {
        working = true
        error = nil
        Task {
            do {
                try await onDone(passphrase)
                dismiss()
            } catch TransferFile.Failure.wrongPassphrase {
                self.error = "That passphrase does not open this file."
            } catch TransferFile.Failure.notAFallowFile {
                self.error = "This is not a Fallow file."
            } catch {
                self.error = "Something went wrong. Try again."
            }
            working = false
        }
    }
}
