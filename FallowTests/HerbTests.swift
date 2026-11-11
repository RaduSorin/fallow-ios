import Foundation
import Testing
import UIKit
@testable import Fallow

struct HerbTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return calendar
    }()

    func fresh() -> VaultContents {
        var c = VaultContents(createdAt: start, settings: VaultSettings())
        c.checkHerbarium(visit: true, now: start, calendar: calendar)
        return c
    }

    func note(_ kind: NoteKind, month: MonthID = MonthID(year: 2026, month: 9), at: Date? = nil) -> Note {
        Note(date: "2026-09-25", month: month, kind: kind, createdAt: at ?? start.addingTimeInterval(60))
    }

    @Test func startsEmptyAndSetsAsideWhatWasThere() {
        var c = VaultContents(createdAt: start, settings: VaultSettings())
        var old = MonthPlan.blank(MonthID(year: 2026, month: 9), calendar: calendar)
        old.intention = "Rest more"
        old.savedAt = start.addingTimeInterval(-86_400)
        c.save(old)
        c.save(Exercise(title: "Mine"))
        c.save(note(.free, at: start.addingTimeInterval(-60)))

        let earned = c.checkHerbarium(visit: true, now: start, calendar: calendar)
        #expect(earned.isEmpty)
        #expect(c.herbarium?.oldMonths == ["2026-09"])
        #expect(c.herbarium?.oldExercises.count == 1)

        // Saving the old month again later still does not count it.
        old.savedAt = start.addingTimeInterval(120)
        c.save(old)
        #expect(c.checkHerbarium(now: start.addingTimeInterval(180), calendar: calendar).isEmpty)
    }

    @Test func firstStepsComeOnceAndNeverGoAway() {
        var c = fresh()
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 10), calendar: calendar)
        plan.intention = "Slow mornings"
        plan.savedAt = start.addingTimeInterval(30)
        c.save(plan)
        c.save(note(.free))
        c.save(note(.friday))
        let now = start.addingTimeInterval(90)
        let earned = c.checkHerbarium(now: now, calendar: calendar)
        #expect(Set(earned) == ["intentie", "randuri", "vineri"])
        #expect(c.herbarium?.pending.count == 3)

        // Deleting the note keeps the plant.
        c.notes.removeAll()
        #expect(c.checkHerbarium(now: now, calendar: calendar).isEmpty)
        #expect(c.herbarium?.earned["randuri"] == now)
    }

    @Test func seriesCountEveningsWorriesAndOwnExercises() {
        var c = fresh()
        for _ in 0..<5 { c.save(note(.friday)) }
        for _ in 0..<4 { c.save(note(.worry)) }
        let earned = Set(c.checkHerbarium(now: start.addingTimeInterval(90), calendar: calendar))
        #expect(earned.isSuperset(of: ["vineri", "seri5", "griji"]))
        #expect(!earned.contains("seri15"))
        #expect(!earned.contains("griji5"))
        let progress = c.herbProgress("griji5", now: start.addingTimeInterval(90))
        #expect(progress.0 == 4 && progress.1 == 5)

        // A pack exercise counts only once it is changed.
        c.save(Exercise(title: "From a pack", packId: "p", packTitle: "Basics", edited: false))
        #expect(!c.checkHerbarium(now: start.addingTimeInterval(100), calendar: calendar).contains("exercitiu"))
        c.exercises[0].edited = true
        #expect(c.checkHerbarium(now: start.addingTimeInterval(110), calendar: calendar).contains("exercitiu"))
    }

    @Test func reflectionBringsTheMonthPlantAndTheSign() {
        var c = fresh()
        var reflection = note(.reflection, month: MonthID(year: 2026, month: 11))
        reflection.answers = [ReflectionQuestion.signKey: "yes"]
        c.save(reflection)
        let earned = Set(c.checkHerbarium(now: start.addingTimeInterval(90), calendar: calendar))
        #expect(earned == ["reflectie", "semn", "luna:2026-11"])
        #expect(Herb.find("luna:2026-11")?.art == "stejar")
    }

    @Test func surprisesForRestStepAndTheGoodParent() {
        var c = fresh()
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 9), calendar: calendar)
        plan.savedAt = start.addingTimeInterval(30)
        c.save(plan) // Fridays left free, one already past on the 25th
        var worry = note(.worry)
        worry.worry = WorryList(stone: ["Rain"], clay: ["Sleep"], step: "Bed at 11",
                                parent: .init(what: "Tired", hardest: "Evenings", need: "Rest"))
        c.save(worry)
        let earned = Set(c.checkHerbarium(now: Date(timeIntervalSince1970: 1_790_500_000), calendar: calendar))
        #expect(earned.isSuperset(of: ["libera", "pas", "parinte"]))
    }

    @Test func welcomeBackAfterMoreThanThreeWeeks() {
        var c = fresh()
        let soon = start.addingTimeInterval(10 * 86_400)
        #expect(!c.checkHerbarium(visit: true, now: soon, calendar: calendar).contains("revenit"))
        let later = soon.addingTimeInterval(22 * 86_400)
        #expect(!c.checkHerbarium(now: later, calendar: calendar).contains("revenit")) // not a visit
        #expect(c.checkHerbarium(visit: true, now: later, calendar: calendar).contains("revenit"))
    }

    @Test func programPlantOnlyWithThe28DayPack() {
        var c = fresh()
        #expect(!Herbarium.hasProgram(c))
        #expect(Herb.visible(hasProgram: false).allSatisfy { $0.id != "program" })
        let pack = ExercisePack(id: "p28", title: "Program 28 de zile", exercises: [.init(title: "A"), .init(title: "B")])
        _ = c.importPack(pack)
        #expect(Herbarium.hasProgram(c))
        for exercise in c.exercises {
            var n = note(.friday)
            n.exerciseId = exercise.id
            c.save(n)
        }
        #expect(c.checkHerbarium(now: start.addingTimeInterval(90), calendar: calendar).contains("program"))
    }

    @Test func pressingMovesAPlantOutOfPending() {
        var c = fresh()
        c.save(note(.free))
        c.checkHerbarium(now: start.addingTimeInterval(90), calendar: calendar)
        c.pressPlant("randuri")
        c.pressPlant("randuri")
        #expect(c.herbarium?.pending.isEmpty == true)
        #expect(c.herbarium?.seen == ["randuri"])
    }

    @Test func oldVaultFilesStillOpen() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var c = VaultContents(createdAt: start, settings: VaultSettings())
        c.herbarium = nil
        let data = try encoder.encode(c)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(VaultContents.self, from: data).herbarium == nil)
    }

    @Test func everyPlantHasADrawingInTheCatalog() {
        let herbs = Herb.catalogue + (1...12).map { Herb.monthHerb(MonthID(year: 2026, month: $0)) }
        for herb in herbs {
            #expect(UIImage(named: herb.imageName) != nil, "missing \(herb.imageName)")
        }
        #expect(Set(Herb.catalogue.map(\.id)).count == Herb.catalogue.count)
    }

    @MainActor
    @Test func vaultChecksTheHerbariumOnEverySave() throws {
        let file = URL.temporaryDirectory.appending(path: "herb-\(UUID().uuidString).fallow")
        defer { try? FileManager.default.removeItem(at: file) }
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: file)
        try vault.setUp(settings: VaultSettings())
        #expect(vault.contents?.herbarium != nil)
        try vault.update { $0.save(Note(date: "2026-11-11", month: .current(), kind: .free)) }
        #expect(vault.contents?.herbarium?.pending == ["randuri"])
    }
}
