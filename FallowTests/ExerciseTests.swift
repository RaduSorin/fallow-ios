import Foundation
import Testing
@testable import Fallow

struct ExercisePackTests {
    let packJSON = #"""
    {"id":"pack-1","title":"  Calm basics ","author":"Ana","exercises":[
      {"title":"Body scan","category":"Awareness","minutes":10,"steps":"Lie down.\n\nBreathe."},
      {"title":"   ","steps":"no title, skipped"},
      {"title":"Kind letter","minutes":-3}
    ]}
    """#

    @Test func decodesAndCleansAPackLikeRagaz() throws {
        let pack = try ExercisePack.decode(Data(packJSON.utf8))
        #expect(pack.title == "Calm basics")
        #expect(pack.exercises.map(\.title) == ["Body scan", "Kind letter"])
        #expect(pack.exercises[1].minutes == nil)
    }

    @Test func rejectsFilesThatAreNotPacks() {
        #expect(throws: ExercisePack.PackError.unreadable) {
            try ExercisePack.decode(Data("{\"recipes\":[]}".utf8))
        }
        #expect(throws: ExercisePack.PackError.empty) {
            try ExercisePack.decode(Data(#"{"id":"x","title":"Empty","exercises":[]}"#.utf8))
        }
    }

    @Test func importAddsThenUpdatesButKeepsEditedOnes() throws {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        let pack = try ExercisePack.decode(Data(packJSON.utf8))
        #expect(contents.importPack(pack) == 2)

        // The person changes one exercise.
        var scan = try #require(contents.exercises.first { $0.title == "Body scan" })
        scan.steps = "My own way"
        contents.save(scan)
        #expect(contents.exercise(scan.id)?.edited == true)

        // Importing again adds nothing, updates the untouched one and keeps the changed one.
        var newer = pack
        newer.exercises[0].steps = "New text"
        newer.exercises[1].minutes = 15
        #expect(contents.importPack(newer) == 0)
        #expect(contents.exercises.count == 2)
        #expect(contents.exercise(scan.id)?.steps == "My own way")
        #expect(contents.exercises.first { $0.title == "Kind letter" }?.minutes == 15)
    }

    @Test func ownExercisesAreNeverMarkedEdited() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        var mine = Exercise(title: "Tea in silence")
        contents.save(mine)
        mine.steps = "Changed"
        contents.save(mine)
        #expect(contents.exercise(mine.id)?.edited == nil)
    }

    @Test func deletingAnExerciseFreesItsFridays() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        let exercise = Exercise(title: "Body scan")
        contents.save(exercise)
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11))
        plan.fridays[0].exerciseId = exercise.id
        plan.fridays[0].title = exercise.title
        contents.save(plan)

        contents.deleteExercise(exercise.id)
        let friday = contents.plan(for: MonthID(year: 2026, month: 11))?.fridays[0]
        #expect(friday?.exerciseId == nil)
        #expect(friday?.title == "Body scan")
        #expect(contents.exercises.isEmpty)
    }

    @Test func bankListsPacksInOrderThenOwnByTitle() throws {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        contents.save(Exercise(title: "Zebra walk"))
        contents.save(Exercise(title: "Apple tasting"))
        contents.importPack(try ExercisePack.decode(Data(packJSON.utf8)))
        #expect(contents.sortedExercises.map(\.title) == ["Body scan", "Kind letter", "Apple tasting", "Zebra walk"])
    }
}
