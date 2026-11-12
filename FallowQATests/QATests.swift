import CryptoKit
import Foundation
import Testing
@testable import Fallow

// Tests written during the QA review of November 2026: edge cases around the rules already
// covered elsewhere, and one regression test for each bug fixed in that review.

private let bucharest: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
    return calendar
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    bucharest.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// MARK: Bugs fixed in the review

struct QARegressionTests {
    @Test func worryListKeepsNumbersThatBelongToTheWorry() {
        let items = WorryList.items(from: "3 bills to pay\n2026 taxes\n1.5 kg to lose\n10 minute walk")
        #expect(items == ["3 bills to pay", "2026 taxes", "1.5 kg to lose", "10 minute walk"])
    }

    @Test func worryListStillDropsListMarks() {
        let items = WorryList.items(from: "1) Rent\n2. Dentist\n- Weather\n* Car\n• Exams\n– School\n12. Bills")
        #expect(items == ["Rent", "Dentist", "Weather", "Car", "Exams", "School", "Bills"])
    }

    @Test func longMonthDigestKeepsTheIntention() {
        let month = MonthID(year: 2026, month: 11)
        var plan = MonthPlan.blank(month, calendar: bucharest)
        plan.intention = "Make room for slowness"
        plan.success = "In bed before 11"
        let notes = (1...200).map {
            Note(date: String(format: "2026-11-%02d", ($0 % 28) + 1), month: month, kind: .free,
                 text: String(repeating: "x", count: 100) + "#\($0)", createdAt: Date(timeIntervalSince1970: Double($0)))
        }
        let digest = OnDeviceAI.digest(plan: plan, notes: notes)
        #expect(digest.count <= OnDeviceAI.maxCharacters)
        #expect(digest.hasPrefix("Intention: Make room for slowness\nSign it went well: In bed before 11\n"))
        // The latest notes are the ones kept (the last day, 28 November, ends with note 195).
        #expect(digest.hasSuffix("#195"))
    }

    @Test func shortMonthDigestIsUnchanged() {
        let month = MonthID(year: 2026, month: 11)
        var plan = MonthPlan.blank(month, calendar: bucharest)
        plan.intention = "Slowness"
        #expect(OnDeviceAI.digest(plan: plan, notes: []) == "Intention: Slowness")
        #expect(OnDeviceAI.digest(plan: nil, notes: []) == "")
    }

    @Test func replacingFromAFileKeepsThisPhonesInboxKey() {
        var here = VaultContents(createdAt: .now, settings: VaultSettings())
        here.inboxKey = Data(repeating: 1, count: 32)
        here.addRhythm("Old")
        var file = VaultContents(createdAt: .now, settings: VaultSettings())
        file.addRhythm("From the file")
        let next = TransferFile.replacing(here, with: file)
        #expect(next.inboxKey == here.inboxKey)
        #expect(next.rhythms.map(\.title) == ["From the file"])

        // A phone that never made a key takes the file's.
        var fresh = VaultContents(createdAt: .now, settings: VaultSettings())
        fresh.inboxKey = nil
        file.inboxKey = Data(repeating: 2, count: 32)
        #expect(TransferFile.replacing(fresh, with: file).inboxKey == file.inboxKey)
    }

    @MainActor
    @Test func aFridayWithItsOwnThemeIsNotFreeOnTheWidget() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: bucharest)
        plan.intention = "Slowness"
        plan.fridays[1].title = "A walk by the lake" // 13 November, no exercise from the bank
        contents.save(plan)
        let snapshot = SharedBridge.snapshot(from: contents, now: at(2026, 11, 13), calendar: bucharest)
        #expect(snapshot.fridaysWithExercise == ["2026-11-13"])
        #expect(WidgetFocus.for(snapshot, day: "2026-11-13", isMonday: false) == .fridayExercise)
        #expect(WidgetFocus.for(snapshot, day: "2026-11-20", isMonday: false) == .freeFriday)
        // The theme itself never goes to the widget.
        let json = String(decoding: (try? JSONEncoder.shared.encode(snapshot)) ?? Data(), as: UTF8.self)
        #expect(!json.contains("lake"))
    }

    @Test func freeFridaysGetAGentlerReminder() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        var exercise = Exercise(title: "Breathing", steps: "In\n\nOut")
        exercise.id = "ex"
        contents.save(exercise)
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: bucharest)
        plan.intention = "Slowness"
        plan.fridays[2].exerciseId = "ex" // 20 November
        plan.fridays[2].title = "Breathing"
        plan.fridays[3].title = "Tea with Ana" // 27 November, a theme
        contents.save(plan)
        let fridays = ReminderPlan.reminders(for: contents, now: at(2026, 11, 14), calendar: bucharest)
            .filter { $0.id.hasPrefix("friday-") }
        let kinds = Dictionary(uniqueKeysWithValues: fridays.map { ($0.id, $0.kind) })
        #expect(kinds["friday-2026-11-20"] == .friday)
        #expect(kinds["friday-2026-11-27"] == .friday)
        #expect(fridays.count == 2)
        // Free Fridays of this month: none left after the 14th, so plan December too.
        var december = MonthPlan.blank(MonthID(year: 2026, month: 12), calendar: bucharest)
        december.intention = "Rest"
        contents.save(december)
        let next = ReminderPlan.reminders(for: contents, now: at(2026, 11, 28), calendar: bucharest)
        #expect(next.first { $0.id == "friday-2026-12-04" }?.kind == .freeFriday)
        #expect(AppRoute(reminder: .freeFriday) == .friday)
        #expect(String(localized: ReminderScheduler.body(for: .freeFriday)) != String(localized: ReminderScheduler.body(for: .friday)))
    }

    @Test func importingAPackKeepsTwoExercisesWithTheSameTitle() throws {
        let json = #"""
        {"id":"p28","title":"The 28 days","exercises":[
          {"title":"Body scan","steps":"Day 1"},
          {"title":"Kind letter","steps":"Day 2"},
          {"title":"Body scan","steps":"Day 3"}
        ]}
        """#
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        let pack = try ExercisePack.decode(Data(json.utf8))
        #expect(contents.importPack(pack) == 3)
        #expect(contents.exercises.map(\.steps) == ["Day 1", "Day 2", "Day 3"])
        // Importing again updates both in place and adds nothing.
        #expect(contents.importPack(pack) == 0)
        #expect(contents.exercises.count == 3)
        #expect(contents.exercises.map(\.order) == [0, 1, 2])
    }

    @MainActor
    @Test func eraseTellsTheAppSoRemindersAndWidgetsGoToo() throws {
        let file = URL.temporaryDirectory.appending(path: "qa-\(UUID().uuidString).fallow")
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: file)
        var erased = 0
        vault.onErase = { erased += 1 }
        try vault.setUp(settings: VaultSettings())
        try vault.eraseEverything()
        #expect(erased == 1)
        #expect(vault.state == .notSetUp)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

// MARK: The vault

@MainActor
struct QAVaultTests {
    let folder = URL.temporaryDirectory.appending(path: "qa-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
    var file: URL { folder.appending(path: "vault.fallow") }

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test func aDamagedFileStaysLockedAndSaysSo() async throws {
        let keys = InMemoryKeyStore()
        let vault = Vault(keyStore: keys, fileURL: file)
        try vault.setUp(settings: VaultSettings())
        vault.lock()
        var bytes = try Data(contentsOf: file)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: file)

        await vault.unlock(reason: "test")
        #expect(vault.state == .locked)
        #expect(vault.contents == nil)
        #expect(vault.lastError == .wrongKey)

        try Data("FALLOW1".utf8).write(to: file)
        await vault.unlock(reason: "test")
        #expect(vault.lastError == .corrupted)
    }

    @Test func nothingIsSavedWhileLocked() throws {
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: file)
        #expect(throws: VaultError.noKey) { try vault.update { $0.addRhythm("x") } }
        try vault.setUp(settings: VaultSettings())
        vault.lock()
        #expect(throws: VaultError.noKey) { try vault.update { $0.addRhythm("x") } }
        #expect(throws: VaultError.noKey) { try vault.addPhoto(Data([1, 2, 3])) }
        #expect(vault.photo("anything") == nil)
    }

    @Test func everySaveIsWrittenAndTold() async throws {
        let keys = InMemoryKeyStore()
        let vault = Vault(keyStore: keys, fileURL: file)
        var told: [Int] = []
        vault.onChange = { told.append($0.rhythms.count) }
        try vault.setUp(settings: VaultSettings())
        try vault.update { $0.addRhythm("Walk") }
        try vault.update { $0.addRhythm("Tea") }
        #expect(told == [0, 1, 2])

        // A new launch reads what was written.
        let again = Vault(keyStore: keys, fileURL: file)
        #expect(again.state == .locked)
        await again.unlock(reason: "test")
        #expect(again.contents?.rhythms.map(\.title) == ["Walk", "Tea"])
    }

    @Test func unlockingTwiceAtOnceOpensOnce() async throws {
        let keys = InMemoryKeyStore()
        let vault = Vault(keyStore: keys, fileURL: file)
        try vault.setUp(settings: VaultSettings())
        vault.lock()
        var opened = 0
        vault.onChange = { _ in opened += 1 }
        async let a: Void = vault.unlock(reason: "a")
        async let b: Void = vault.unlock(reason: "b")
        _ = await (a, b)
        #expect(vault.state == .unlocked)
        #expect(opened == 1)
    }

    @Test func aFileWithoutItsKeyStartsOver() throws {
        // E.g. an iPhone restored from a device backup: the file came back, the key (this device only) did not.
        try Data("FALLOW1-something".utf8).write(to: file)
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: file)
        #expect(vault.state == .notSetUp)
    }

    @Test func photosStayUnreadableWithoutTheVault() throws {
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: file)
        try vault.setUp(settings: VaultSettings())
        let id = try vault.addPhoto(Data("jpeg bytes".utf8))
        let sealed = try #require(vault.photos.read(id))
        #expect(!String(decoding: sealed, as: UTF8.self).contains("jpeg bytes"))
        #expect(vault.photo(id) == Data("jpeg bytes".utf8))
        vault.lock()
        #expect(vault.photo(id) == nil)
    }
}

// MARK: The .fallow file and the backup

struct QATransferTests {
    func sample() -> VaultContents {
        var c = VaultContents(createdAt: Date(timeIntervalSince1970: 1_790_000_000), settings: VaultSettings())
        c.addRhythm("Plimbare fără telefon")
        return c
    }

    @Test func passphraseIsTheSameWhateverTheKeyboardSends() throws {
        // "ă" typed as one character (NFC) or as "a" + breve (NFD), with spaces around.
        let nfc = "liniște în pădure"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        #expect(nfc.utf8.count != nfd.utf8.count)
        let file = try TransferFile.seal(sample(), passphrase: nfc, rounds: 1_000)
        let opened = try TransferFile.open(file, passphrase: "  \(nfd)\n")
        #expect(opened.rhythms.map(\.title) == ["Plimbare fără telefon"])
    }

    @Test func aChangedOrCutFileIsRefused() throws {
        let file = try TransferFile.seal(sample(), passphrase: "quiet forest walk", rounds: 1_000)
        var changed = file
        changed[changed.count - 20] ^= 0x01
        #expect(throws: TransferFile.Failure.wrongPassphrase) { try TransferFile.open(changed, passphrase: "quiet forest walk") }
        #expect(throws: TransferFile.Failure.notAFallowFile) { try TransferFile.open(file.prefix(40), passphrase: "quiet forest walk") }
        var zeroRounds = file
        for i in 24..<28 { zeroRounds[i] = 0 }
        #expect(throws: TransferFile.Failure.notAFallowFile) { try TransferFile.open(zeroRounds, passphrase: "quiet forest walk") }
    }

    @Test func eachFileHasItsOwnSalt() throws {
        let a = try TransferFile.seal(sample(), passphrase: "quiet forest walk", rounds: 1_000)
        let b = try TransferFile.seal(sample(), passphrase: "quiet forest walk", rounds: 1_000)
        #expect(a.subdata(in: 8..<24) != b.subdata(in: 8..<24))
        #expect(a != b)
    }

    @Test func everythingTravelsInTheFile() throws {
        // Whole seconds: the file keeps dates to the second.
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        var c = VaultContents(createdAt: when, settings: VaultSettings())
        c.rhythms = [Rhythm(id: "r1", title: "Walk", createdAt: when)]
        c.rhythmLog = ["2026-11-13": ["r1"]]
        c.save(Note(date: "2026-11-13", month: MonthID(year: 2026, month: 11), kind: .friday, exerciseId: "ex",
                    title: "Breathing", before: 7, after: 3, fit: .partly, text: "Calmer", photos: ["p1"], createdAt: when))
        c.coach = CoachState(consent: true, level: .month, note: "Likes walks", messages: [.init(role: .user, text: "Hi", at: when)])
        c.checkHerbarium(visit: true, now: Date(timeIntervalSince1970: 1_790_000_000), calendar: bucharest)
        c.settings.widgetRhythms = true
        let file = try TransferFile.seal(c, passphrase: "quiet forest walk", rounds: 1_000)
        let opened = try TransferFile.open(file, passphrase: "quiet forest walk")
        #expect(opened == c)
    }
}

@MainActor
struct QABackupTests {
    let folder = URL.temporaryDirectory.appending(path: "qa-backup-\(UUID().uuidString)", directoryHint: .isDirectory)

    func make() throws -> (Backup, FolderBackupStore) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = FolderBackupStore(url: folder.appending(path: "vault.fallowbackup"))
        let backup = Backup(store: store, keys: InMemoryBackupKey(),
                            defaults: UserDefaults(suiteName: "qa-\(UUID().uuidString)")!,
                            photos: PhotoStore(folder: folder.appending(path: "Photos", directoryHint: .isDirectory)))
        return (backup, store)
    }

    @Test func aDamagedBackupSaysUnreadable() async throws {
        let (backup, store) = try make()
        await backup.backUp(VaultContents(createdAt: .now, settings: VaultSettings()))
        try await store.write(Data("not a backup".utf8))
        await #expect(throws: BackupError.unreadable) { try await backup.restore() }
    }

    @Test func turningTheBackupOffCancelsTheWaitingOne() async throws {
        let (backup, store) = try make()
        backup.delay = .seconds(30)
        var on = VaultContents(createdAt: .now, settings: VaultSettings())
        backup.schedule(on)
        #expect(backup.status != .off)
        on.settings.iCloudBackup = false
        backup.schedule(on)
        #expect(backup.status == .off)
        await backup.flush()
        #expect(try await store.read() == nil)
    }

    @Test func flushWritesTheWaitingBackupRightAway() async throws {
        let (backup, store) = try make()
        backup.delay = .seconds(30)
        var c = VaultContents(createdAt: .now, settings: VaultSettings())
        c.addRhythm("Walk")
        backup.schedule(c)
        await backup.flush()
        #expect(try await store.read() != nil)
        if case .saved = backup.status {} else { Issue.record("status \(backup.status)") }
        // Nothing waits any more: a second flush does nothing.
        await backup.flush()
    }
}

// MARK: Dates and months

struct QACalendarTests {
    @Test func monthsWithFiveFridaysAndShortFebruaries() {
        #expect(MonthID(year: 2027, month: 1).fridays(calendar: bucharest).count == 5)
        #expect(MonthID(year: 2027, month: 2).fridays(calendar: bucharest).count == 4)
        #expect(MonthID(year: 2026, month: 5).fridays(calendar: bucharest).map { DayKey.string($0, calendar: bucharest) }
                == ["2026-05-01", "2026-05-08", "2026-05-15", "2026-05-22", "2026-05-29"])
    }

    @Test func monthArithmeticStepsOverYears() {
        #expect(MonthID(year: 2026, month: 0) == MonthID(year: 2025, month: 12))
        #expect(MonthID(year: 2026, month: -11) == MonthID(year: 2025, month: 1))
        #expect(MonthID(year: 2026, month: 25) == MonthID(year: 2028, month: 1))
        #expect(MonthID(year: 2026, month: 12).next.description == "2027-01")
        #expect(MonthID(string: "2026-13") == nil)
        #expect(MonthID(string: "2026") == nil)
        #expect(MonthID(string: "nonsense") == nil)
    }

    @Test func daysAcrossSummerTimeAreWholeDays() {
        // Romania moves the clock on 29 March and 25 October 2026.
        #expect(Herbarium.daysBetween("2026-03-28", "2026-03-30", calendar: bucharest) == 2)
        #expect(Herbarium.daysBetween("2026-10-24", "2026-10-26", calendar: bucharest) == 2)
        #expect(Herbarium.daysBetween("2026-12-31", "2027-01-01", calendar: bucharest) == 1)
        #expect(Herbarium.daysBetween("bad", "2027-01-01", calendar: bucharest) == 0)
    }

    @Test func dayKeysRoundTrip() throws {
        let date = at(2026, 3, 29, 12, 30)
        let key = DayKey.string(date, calendar: bucharest)
        #expect(key == "2026-03-29")
        let back = try #require(DayKey.date(key, calendar: bucharest))
        #expect(DayKey.string(back, calendar: bucharest) == key)
        #expect(DayKey.date("2026-11", calendar: bucharest) == nil)
    }

    @Test func remindersReachIntoTheNextYear() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        var january = MonthPlan.blank(MonthID(year: 2027, month: 1), calendar: bucharest)
        january.intention = "New year"
        january.fridays = january.fridays.map { var f = $0; f.title = "Walk"; return f }
        contents.save(january)
        let reminders = ReminderPlan.reminders(for: contents, now: at(2026, 12, 20), calendar: bucharest)
        let ids = reminders.map(\.id)
        #expect(ids.contains("friday-2027-01-01"))
        #expect(ids.contains("reflection-2027-01"))
        #expect(ids.contains("reflection-2027-02"))
        // iOS keeps at most 64 waiting notifications per app.
        #expect(reminders.count < 64)
    }

    @Test func noReminderInThePast() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: bucharest)
        plan.intention = "x"
        contents.save(plan)
        let now = at(2026, 11, 13, 20, 0)
        let reminders = ReminderPlan.reminders(for: contents, now: now, calendar: bucharest)
        for reminder in reminders where !reminder.repeats {
            let date = bucharest.date(from: reminder.components)
            #expect(date.map { $0 > now } == true, "\(reminder.id) is not ahead")
        }
    }
}

// MARK: Rules and small models

struct QAModelTests {
    @Test func searchNeedsEveryWord() {
        let note = Note(date: "2026-11-13", month: MonthID(year: 2026, month: 11), kind: .free, text: "Am mers la pădure cu Ana")
        #expect(note.matches(""))
        #expect(note.matches("   "))
        #expect(note.matches("padure ana"))
        #expect(!note.matches("padure mare"))
    }

    @Test func searchLooksInsideTheWorryList() {
        var note = Note(date: "2026-11-16", month: MonthID(year: 2026, month: 11), kind: .worry)
        note.worry = WorryList(stone: ["Vremea"], clay: ["Dentistul"], breakdown: ["Sun la cabinet"], step: "Sun mâine",
                               parent: .init(what: nil, hardest: "Frica", need: "Odihnă"))
        for word in ["vremea", "dentistul", "cabinet", "maine", "frica", "odihna"] {
            #expect(note.matches(word), "\(word)")
        }
    }

    @Test func averageChangeCanBeNegative() {
        let points = [FeelingPoint(id: "a", day: "2026-11-06", before: 3, after: 6),
                      FeelingPoint(id: "b", day: "2026-11-13", before: 5, after: 6)]
        #expect(LookBack.averageChange(points) == -2)
        #expect(LookBack.averageChange([]) == nil)
    }

    @Test func aZeroLengthClockIsDoneAtOnce() {
        let clock = ExerciseClock(duration: -5, start: .now)
        #expect(clock.duration == 0)
        #expect(clock.isOver(at: .now))
        #expect(clock.progress(at: .now) == 1)
    }

    @Test func stepsIgnoreExtraBlankLines() {
        let exercise = Exercise(title: "x", steps: "\n\nOne\n\n\n\nTwo\n  \n\nThree\n")
        #expect(exercise.stepList == ["One", "Two", "Three"])
        #expect(Exercise(title: "x").stepList.isEmpty)
    }

    @Test func plantsWaitOldestFirst() {
        var book = HerbBook(since: Date(timeIntervalSince1970: 0))
        book.earned = ["b": Date(timeIntervalSince1970: 20), "a": Date(timeIntervalSince1970: 20), "c": Date(timeIntervalSince1970: 10)]
        #expect(book.pending == ["c", "a", "b"])
        book.seen = ["a"]
        #expect(book.pending == ["c", "b"])
    }

    @Test func monthPlantsHaveTheirSeason() {
        for month in 1...12 {
            let herb = Herb.monthHerb(MonthID(year: 2026, month: month))
            #expect(Herb.monthOf(herb.id) == MonthID(year: 2026, month: month))
            #expect(Herb.find(herb.id)?.art == herb.art)
        }
        #expect(Herb.monthOf("luna:2026-13") == nil)
        #expect(Herb.find("nothing") == nil)
    }

    @Test func inboxIgnoresNotesWithABadDay() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        contents.apply(InboxEntry(kind: .note, day: "someday", createdAt: .now, text: "Hello"))
        #expect(contents.notes.isEmpty)
    }

    @Test func coachSendsOnlyTheIntentionLevelAskedFor() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: bucharest)
        plan.intention = "Slowness"
        plan.success = "In bed before 11"
        contents.save(plan)
        contents.save(Note(date: "2026-11-13", month: MonthID(year: 2026, month: 11), kind: .free, text: "secret diary line"))
        let now = at(2026, 11, 14)
        #expect(contents.coachContext(.chat, english: true, today: now, calendar: bucharest) == "")
        let intention = contents.coachContext(.intention, english: true, today: now, calendar: bucharest)
        #expect(intention.contains("Slowness") && intention.contains("In bed before 11"))
        #expect(!intention.contains("Fridays"))
        let month = contents.coachContext(.month, english: false, today: now, calendar: bucharest)
        #expect(month.contains("Vineri cu exercițiul făcut"))
        for level in CoachState.Level.allCases {
            #expect(!contents.coachContext(level, english: true, today: now, calendar: bucharest).contains("secret"))
        }
    }

    @Test func remindersNeverShowWhatWasWritten() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: bucharest)
        plan.intention = "Private intention"
        plan.fridays[2].title = "Private theme"
        contents.save(plan)
        for reminder in ReminderPlan.reminders(for: contents, now: at(2026, 11, 14), calendar: bucharest) {
            let text = String(localized: ReminderScheduler.title(for: reminder.kind)) + String(localized: ReminderScheduler.body(for: reminder.kind))
            #expect(!text.contains("Private"))
            #expect(!reminder.id.contains("Private"))
        }
    }
}

// MARK: Decisions taken after the review (November 2026)

struct QADecisionTests {
    @Test func theReflectionComesInTheEveningNotWithTheWorryList() throws {
        let contents = VaultContents(createdAt: .now, settings: VaultSettings())
        let reminders = ReminderPlan.reminders(for: contents, now: at(2026, 11, 12), calendar: bucharest)
        let reflection = try #require(reminders.first { $0.id == "reflection-2026-12" })
        #expect(reflection.components.day == 7)
        #expect(reflection.components.hour == 20 && reflection.components.minute == 0)
        let worry = try #require(reminders.first { $0.kind == .worry })
        #expect(worry.components.hour != reflection.components.hour)
    }

    @Test func theFirstMondaysReflectionIsStillAheadThatMorning() {
        let contents = VaultContents(createdAt: .now, settings: VaultSettings())
        // Monday 7 December 2026 at 9:00: the reflection at 20:00 is still to come.
        let ids = ReminderPlan.reminders(for: contents, now: at(2026, 12, 7, 9, 0), calendar: bucharest).map(\.id)
        #expect(ids.contains("reflection-2026-12"))
    }

    /// The month planned on the 20th: its free Fridays already past were not chosen.
    @Test func pastFreeFridaysDoNotBringAFreeEvening() {
        let start = at(2026, 11, 1)
        var c = VaultContents(createdAt: start, settings: VaultSettings())
        c.checkHerbarium(visit: true, now: start, calendar: bucharest)
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: bucharest)
        plan.intention = "Slower"
        plan.savedAt = at(2026, 11, 20)
        plan.plannedAt = plan.savedAt
        c.save(plan)
        let earned = c.checkHerbarium(now: at(2026, 11, 22), calendar: bucharest)
        #expect(earned.contains("intentie"))
        #expect(!earned.contains("libera"))
        // The next free Friday, the 27th, is a chosen one.
        #expect(c.checkHerbarium(now: at(2026, 11, 27, 21), calendar: bucharest).contains("libera"))
    }

    @Test func editingThePlanLaterKeepsTheFridaysChosenFree() {
        let start = at(2026, 11, 1)
        var c = VaultContents(createdAt: start, settings: VaultSettings())
        c.checkHerbarium(visit: true, now: start, calendar: bucharest)
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: bucharest)
        plan.intention = "Slower"
        plan.plannedAt = at(2026, 11, 2)
        // Changed on the 10th, before the app was opened after the free Friday on the 6th.
        plan.savedAt = at(2026, 11, 10)
        c.save(plan)
        #expect(c.checkHerbarium(now: at(2026, 11, 10, 13), calendar: bucharest).contains("libera"))
    }

    @Test func olderPlansWithoutAPlanningDayUseTheirSaveDay() throws {
        let json = #"{"id":"2026-11","intention":"x","fridays":[],"savedAt":"2026-11-01T10:00:00Z"}"#
        let plan = try VaultCoding.decoder.decode(MonthPlan.self, from: Data(json.utf8))
        #expect(plan.plannedAt == nil)
    }

    @Test func aDraftTravelsEncryptedWithTheVaultAndKeepsItsPhotos() throws {
        var c = VaultContents(createdAt: at(2026, 11, 1), settings: VaultSettings())
        // Whole seconds: the vault keeps dates to the second.
        var note = Note(date: "2026-11-12", month: MonthID(year: 2026, month: 11), kind: .free, createdAt: at(2026, 11, 12))
        note.text = "Half a thought"
        note.photos = ["p1"]
        c.draft = note
        #expect(c.photoIDs.contains("p1"))
        let back = try VaultCoding.decoder.decode(VaultContents.self, from: VaultCoding.encoder.encode(c))
        #expect(back.draft == note)
        #expect(back.notes.isEmpty)
    }

    @MainActor
    @Test func aDraftSurvivesLockingAndUnlocking() async throws {
        let folder = URL.temporaryDirectory.appending(path: "qa-draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: folder.appending(path: "vault.fallow"))
        try vault.setUp(settings: VaultSettings())
        var note = Note(date: "2026-11-12", month: MonthID(year: 2026, month: 11), kind: .free)
        note.text = "Written before the lock"
        try vault.update { $0.draft = note }
        vault.lock()
        await vault.unlock(reason: "test")
        #expect(vault.contents?.draft?.text == "Written before the lock")
        #expect(vault.contents?.notes.isEmpty == true)
    }
}
