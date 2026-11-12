import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(Vault.self) private var vault
    @Environment(Backup.self) private var backup
    @State private var confirmErase = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(AppLanguage.current(locale).displayName)
                } label: {
                    Text("Language")
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Change language")
                }
            } footer: {
                Text("Fallow is in English by default. You can switch to Romanian in the app's iOS settings.")
            }

            Section {
                NavigationLink {
                    ExercisesView()
                } label: {
                    Label { Text("My exercises") } icon: { Image(systemName: "books.vertical") }
                }
                NavigationLink {
                    JournalView()
                } label: {
                    Label { Text("Journal") } icon: { Image(systemName: "book.closed") }
                }
                NavigationLink {
                    CoachView()
                } label: {
                    Label { Text(verbatim: "Claude") } icon: { Image(systemName: "bubble.left.and.text.bubble.right") }
                }
                NavigationLink {
                    BackupView()
                } label: {
                    Label { Text("Backup and transfer") } icon: { Image(systemName: "icloud") }
                }
            }

            Section {
                reminderToggle("Morning", value: settingBinding(\.morningReminder), fallback: 8 * 60 + 30)
                reminderToggle("Evening", value: settingBinding(\.eveningReminder), fallback: 21 * 60)
                Toggle(isOn: settingBinding(\.fridayReminder)) { Text("Friday evening, 20:00") }
                Toggle(isOn: settingBinding(\.worryReminder)) { Text("Monday worry list, 8:30") }
                Toggle(isOn: settingBinding(\.reflectionReminder)) { Text("Monthly reflection, first Monday") }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Reminders are set on this iPhone only and never show what you wrote.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { vault.contents?.herbarium?.quiet != true },
                    set: { show in try? vault.update { $0.herbarium?.quiet = show ? nil : true } }
                )) {
                    Text("Show when a plant comes")
                }
            } header: {
                Text("Herbarium")
            } footer: {
                Text("When off, new plants wait quietly in the herbarium.")
            }

            if MindfulHealth.isAvailable {
                Section {
                    Toggle(isOn: Binding(
                        get: { vault.contents?.settings.healthMindful ?? false },
                        set: { on in
                            if on {
                                Task {
                                    let allowed = await MindfulHealth.requestAccess()
                                    try? vault.update { $0.settings.healthMindful = allowed }
                                }
                            } else {
                                try? vault.update { $0.settings.healthMindful = false }
                            }
                        }
                    )) {
                        Text("Save mindful minutes")
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("After a guided exercise with a timer, its length goes to Health as mindful minutes. Nothing you wrote goes there.")
                }
            }

            Section {
                Toggle(isOn: settingBinding(\.widgetIntention)) { Text("Show the month's intention") }
                Toggle(isOn: settingBinding(\.widgetRhythms)) { Text("Show and tick rhythms") }
            } header: {
                Text("Widgets")
            } footer: {
                Text("By default widgets show only dates and counts. What you turn on here is kept unencrypted outside the vault, so it can show on the Home Screen and the Lock Screen.")
            }

            Section {
                Button {
                    vault.lock()
                } label: {
                    Label { Text("Lock now") } icon: { Image(systemName: "lock") }
                }
                Button(role: .destructive) {
                    confirmErase = true
                } label: {
                    Label { Text("Erase everything") } icon: { Image(systemName: "trash") }
                }
            } header: {
                Text("Privacy")
            }

            Section {
                LabeledContent {
                    Text(Bundle.main.appVersion)
                } label: {
                    Text("Version")
                }
            }
        }
        .confirmationDialog(
            Text("Erase everything?"),
            isPresented: $confirmErase,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                try? vault.eraseEverything()
            } label: {
                Text("Erase from this iPhone")
            }
            Button(role: .destructive) {
                try? vault.eraseEverything()
                Task { try? await backup.deleteBackup() }
            } label: {
                Text("Erase here and in iCloud")
            }
        } message: {
            Text("This deletes your journal and its key from this iPhone. With iCloud, the backup and its key go too. It cannot be undone.")
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }
}

extension SettingsView {
    fileprivate func settingBinding<Value>(_ path: WritableKeyPath<VaultSettings, Value>) -> Binding<Value> {
        Binding(
            get: { (vault.contents?.settings ?? VaultSettings())[keyPath: path] },
            set: { value in try? vault.update { $0.settings[keyPath: path] = value } }
        )
    }

    @ViewBuilder
    fileprivate func reminderToggle(_ title: LocalizedStringResource, value: Binding<Int?>, fallback: Int) -> some View {
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

/// Languages the app ships with. English is the default.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case romanian = "ro"

    static func current(_ locale: Locale) -> AppLanguage {
        let code = Bundle.main.preferredLocalizations.first ?? locale.language.languageCode?.identifier ?? "en"
        return AppLanguage(rawValue: code) ?? .english
    }

    var displayName: String {
        switch self {
        case .english: "English"
        case .romanian: "Română"
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
