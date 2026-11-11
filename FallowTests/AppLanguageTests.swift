import Testing
@testable import Fallow

struct AppLanguageTests {
    @Test func unknownLanguageFallsBackToEnglish() {
        #expect(AppLanguage(rawValue: "de") == nil)
        #expect(AppLanguage.allCases.first == .english)
    }

    @Test func shipsEnglishAndRomanian() {
        #expect(AppLanguage.allCases.map(\.rawValue) == ["en", "ro"])
        #expect(AppLanguage.romanian.displayName == "Română")
    }

    @Test func everyTabHasAnIcon() {
        for tab in AppTab.allCases {
            #expect(!tab.systemImage.isEmpty)
        }
    }
}
