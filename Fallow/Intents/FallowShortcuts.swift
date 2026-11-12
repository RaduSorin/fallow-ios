import AppIntents
import Foundation

/// "Note in Fallow": dictate a line to Siri without opening the app. The line is sealed
/// in the inbox right away and lands in the journal at the next Face ID.
struct NoteInFallowIntent: AppIntent {
    static let title: LocalizedStringResource = "Note in Fallow"
    static var description: IntentDescription {
        IntentDescription("Saves a line in your journal without opening Fallow. It is sealed right away; you see it after Face ID.")
    }

    @Parameter(title: "Note", requestValueDialog: "What do you want to note?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .result(dialog: "Nothing to save.") }
        do {
            try Inbox.post(.note(clean, day: DayKey.string(.now)))
        } catch {
            return .result(dialog: "Open Fallow once with Face ID, then try again.")
        }
        return .result(dialog: "Saved. It will be in your journal the next time you open Fallow.")
    }
}

/// The phrases Siri knows, and the actions offered for the Action button and in Shortcuts.
struct FallowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartExerciseIntent(),
            phrases: [
                "Start my exercise in \(.applicationName)",
                "Start tonight's exercise in \(.applicationName)",
            ],
            shortTitle: "Friday exercise",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: NoteInFallowIntent(),
            phrases: [
                "Note in \(.applicationName)",
                "Add a note to \(.applicationName)",
            ],
            shortTitle: "Quick note",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: WriteNoteIntent(),
            phrases: [
                "Write in \(.applicationName)",
                "Open my \(.applicationName) journal",
            ],
            shortTitle: "Write a note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: WorryListIntent(),
            phrases: [
                "Open my worry list in \(.applicationName)",
                "Sort my worries in \(.applicationName)",
            ],
            shortTitle: "Worry list",
            systemImageName: "scalemass"
        )
    }
}
