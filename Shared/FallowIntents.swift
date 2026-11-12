import AppIntents
import Foundation
import WidgetKit

/// Opens Fallow on tonight's Friday exercise (after Face ID).
struct StartExerciseIntent: AppIntent {
    static let title: LocalizedStringResource = "Start tonight's exercise"
    static var description: IntentDescription { IntentDescription("Opens Fallow on tonight's Friday exercise.") }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(FallowLink.url("friday")))
    }
}

/// Opens Fallow on a new note (after Face ID).
struct WriteNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Write in Fallow"
    static var description: IntentDescription { IntentDescription("Opens Fallow on a new note.") }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(FallowLink.url("note")))
    }
}

/// Opens Fallow on the worry list (after Face ID).
struct WorryListIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the worry list"
    static var description: IntentDescription { IntentDescription("Opens Fallow on the worry list: stone and clay.") }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(FallowLink.url("worry")))
    }
}

/// The rhythm button in the widget: marks a rhythm kept (or not) without opening Fallow.
/// The change goes into the sealed inbox; the vault takes it in at the next Face ID.
struct ToggleRhythmIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a rhythm"
    static let isDiscoverable = false

    @Parameter(title: "Rhythm")
    var rhythmID: String

    @Parameter(title: "Day")
    var day: String

    init() {}

    init(rhythmID: String, day: String) {
        self.rhythmID = rhythmID
        self.day = day
    }

    func perform() async throws -> some IntentResult {
        guard var snapshot = SharedStore.readSnapshot() else { return .result() }
        let done = !snapshot.done(on: day).contains(rhythmID)
        try Inbox.post(.rhythm(rhythmID, done: done, day: day))
        snapshot.set(rhythmID, done: done, on: day)
        SharedStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
