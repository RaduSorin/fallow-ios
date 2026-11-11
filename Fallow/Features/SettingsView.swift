import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(Vault.self) private var vault
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
                Text("Erase everything")
            }
        } message: {
            Text("This deletes your journal and its key from this iPhone. It cannot be undone.")
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
