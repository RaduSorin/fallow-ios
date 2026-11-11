import Foundation

/// The herbarium: a pressed plant for showing up, never for how well it went. No streaks,
/// nothing is ever lost, and the feeling scales never count. Plants are worked out from what is
/// already in the vault, counting only what was made after the herbarium started. Ids match
/// Răgaz, so a herbarium brought over from Kitchen Tales keeps its plants.
struct HerbBook: Codable, Equatable, Sendable {
    /// When the herbarium started: only what is made from then on counts.
    var since: Date
    /// Months and exercises already in the vault at the start (never counted).
    var oldMonths: [String] = []
    var oldExercises: [String] = []
    /// Plant id to when it was earned. Month plants are "luna:2026-11".
    var earned: [String: Date] = [:]
    /// Plants already pressed into the herbarium.
    var seen: [String] = []
    /// The last day Fallow was opened ("2026-11-13"), for "Welcome back".
    var lastVisit: String?
    /// No moment when a plant comes: it waits in the herbarium instead.
    var quiet: Bool?

    /// A new herbarium that sets aside what the vault already holds.
    static func starting(_ contents: VaultContents, now: Date, calendar: Calendar = .current) -> HerbBook {
        HerbBook(
            since: now,
            oldMonths: contents.months.map(\.id.description),
            oldExercises: contents.exercises.map(\.id),
            lastVisit: DayKey.string(now, calendar: calendar)
        )
    }

    /// Earned and not yet pressed, oldest first.
    var pending: [String] {
        earned.keys.filter { !seen.contains($0) }.sorted { (earned[$0]!, $0) < (earned[$1]!, $1) }
    }
}

enum HerbGroup: String, CaseIterable, Sendable {
    case firstSteps, overTime, surprises, program

    var title: LocalizedStringResource {
        switch self {
        case .firstSteps: "First steps"
        case .overTime: "Over time"
        case .surprises: "Surprises"
        case .program: "Program"
        }
    }
}

struct Herb: Identifiable, Sendable {
    let id: String
    let group: HerbGroup
    let name: LocalizedStringResource
    /// What brings it, as a fact.
    let how: LocalizedStringResource
    /// The drawing ("plant-<art>" in the asset catalog) and the plant's own name.
    let art: String
    let plant: LocalizedStringResource
    /// The number written next to the plant, for a series.
    var level: Int?
    /// Shown as a sketch with "Surprise" until it comes.
    var secret = false

    var imageName: String { "plant-\(art)" }

    static let catalogue: [Herb] = [
        Herb(id: "intentie", group: .firstSteps, name: "First intention", how: "Your first month planned, with its intention.", art: "trifoi", plant: "clover"),
        Herb(id: "vineri", group: .firstSteps, name: "First Friday", how: "Your first note after a Friday exercise.", art: "lavanda", plant: "lavender"),
        Herb(id: "griji", group: .firstSteps, name: "Stone and clay", how: "Your first worry list taken to the end.", art: "feriga", plant: "fern"),
        Herb(id: "reflectie", group: .firstSteps, name: "Looking back", how: "Your first month's reflection.", art: "ginkgo", plant: "ginkgo"),
        Herb(id: "randuri", group: .firstSteps, name: "My own lines", how: "Your first free note in the journal.", art: "numauita", plant: "forget-me-not"),
        Herb(id: "exercitiu", group: .firstSteps, name: "My exercise", how: "The first exercise you wrote or changed in your bank.", art: "margareta", plant: "daisy"),
        Herb(id: "seri5", group: .overTime, name: "5 evenings for me", how: "5 notes after exercises, any time.", art: "spic", plant: "wheat", level: 5),
        Herb(id: "seri15", group: .overTime, name: "15 evenings for me", how: "15 notes after exercises, any time.", art: "spic", plant: "wheat", level: 15),
        Herb(id: "seri30", group: .overTime, name: "30 evenings for me", how: "30 notes after exercises, any time.", art: "spic", plant: "wheat", level: 30),
        Herb(id: "griji5", group: .overTime, name: "Lighter", how: "5 worry lists, in any weeks.", art: "coada", plant: "horsetail", level: 5),
        Herb(id: "griji12", group: .overTime, name: "Clear water", how: "12 worry lists, in any weeks.", art: "coada", plant: "horsetail", level: 12),
        Herb(id: "luni3", group: .overTime, name: "Three seasons", how: "3 months planned, any of them.", art: "mesteacan", plant: "birch", level: 3),
        Herb(id: "banca5", group: .overTime, name: "My bank", how: "5 of your own exercises in the bank, written or changed.", art: "rozmarin", plant: "rosemary", level: 5),
        Herb(id: "semn", group: .overTime, name: "The month's sign", how: "You said in the month's reflection that you saw the sign you chose.", art: "macese", plant: "wild rose"),
        Herb(id: "libera", group: .surprises, name: "A free evening", how: "A Friday left free. Rest is an exercise too.", art: "mac", plant: "poppy", secret: true),
        Herb(id: "pas", group: .surprises, name: "The small step", how: "A small step chosen in the worry list.", art: "fraga", plant: "wild strawberry", secret: true),
        Herb(id: "parinte", group: .surprises, name: "The good parent", how: "The three gentle questions, answered.", art: "musetel", plant: "chamomile", secret: true),
        Herb(id: "revenit", group: .surprises, name: "Welcome back", how: "You came back to Fallow after a pause of more than three weeks.", art: "papadie", plant: "dandelion", secret: true),
        Herb(id: "claude", group: .surprises, name: "I asked", how: "Your first conversation with Claude.", art: "clopotel", plant: "bellflower", secret: true),
        Herb(id: "program", group: .program, name: "The 28 days", how: "A note for each exercise of the 28-day program, in any order and at your own pace.", art: "cununa", plant: "wreath"),
    ]

    static func find(_ id: String) -> Herb? {
        if let month = monthOf(id) { return monthHerb(month) }
        return catalogue.first { $0.id == id }
    }

    /// "luna:2026-11" to its month.
    static func monthOf(_ id: String) -> MonthID? {
        guard id.hasPrefix("luna:") else { return nil }
        return MonthID(string: String(id.dropFirst(5)))
    }

    static func monthID(_ month: MonthID) -> String { "luna:\(month)" }

    /// The plant of each month of the year, by season.
    static func monthHerb(_ month: MonthID) -> Herb {
        let (art, plant): (String, LocalizedStringResource) = switch month.month {
        case 1: ("brad", "fir")
        case 2: ("ghiocel", "snowdrop")
        case 3: ("viorea", "squill")
        case 4: ("lalea", "tulip")
        case 5: ("lacramioara", "lily of the valley")
        case 6: ("tei", "linden")
        case 7: ("sunatoare", "St John's wort")
        case 8: ("floarea", "sunflower")
        case 9: ("vita", "grapevine")
        case 10: ("artar", "maple")
        case 11: ("stejar", "oak")
        default: ("vasc", "mistletoe")
        }
        let title = month.name.prefix(1).uppercased() + month.name.dropFirst()
        return Herb(
            id: monthID(month), group: .firstSteps,
            name: "\(title)",
            how: "\(month.nameWithYear), closed with the month's reflection.",
            art: art, plant: plant
        )
    }

    /// The catalogue plants a person can see: the program only when its pack is in the bank.
    static func visible(hasProgram: Bool) -> [Herb] {
        catalogue.filter { $0.id != "program" || hasProgram }
    }
}

/// What the rules look at, beyond the vault itself.
struct HerbFacts: Sendable {
    /// A message to Claude written after the start (the coach comes in a later version).
    var asked = false
    /// Fallow opened today after more than three weeks away.
    var returned = false
    /// Today, "2026-11-13".
    var today: String
}

/// The counts the rules need, from what was made after the start only.
struct HerbTally: Equatable, Sendable {
    var intention = 0
    var evenings = 0
    var worries = 0
    var reflections: [MonthID] = []
    var free = 0
    var own = 0
    var months = 0
    var sign = false
    var rest = false
    var step = false
    var parent = false
    /// [done, all] for the 28-day program, when its pack is in the bank.
    var program: (done: Int, all: Int)?

    static func == (a: HerbTally, b: HerbTally) -> Bool {
        a.intention == b.intention && a.evenings == b.evenings && a.worries == b.worries
            && a.reflections == b.reflections && a.free == b.free && a.own == b.own && a.months == b.months
            && a.sign == b.sign && a.rest == b.rest && a.step == b.step && a.parent == b.parent
            && a.program?.done == b.program?.done && a.program?.all == b.program?.all
    }
}

enum Herbarium {
    /// A pause long enough for "Welcome back".
    static let awayDays = 21

    /// The 28-day program: a pack in the bank with "28" in its name (only on the phones that have it).
    static func isProgramPack(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.contains(/\b28\b/)
    }

    static func hasProgram(_ contents: VaultContents) -> Bool {
        contents.exercises.contains { isProgramPack($0.packTitle) }
    }

    private static func filled(_ text: String?) -> Bool {
        !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func tally(_ book: HerbBook, _ contents: VaultContents, today: String) -> HerbTally {
        let notes = contents.notes.filter { $0.createdAt >= book.since }
        let months = contents.months.filter { !book.oldMonths.contains($0.id.description) && $0.savedAt >= book.since }
        let own = contents.exercises.filter { !book.oldExercises.contains($0.id) && ($0.packId == nil || $0.edited == true) }
        let worries = notes.filter { $0.kind == .worry }
        let reflections = notes.filter { $0.kind == .reflection }
        let program = contents.exercises.filter { isProgramPack($0.packTitle) }
        let done = Set(notes.compactMap(\.exerciseId))

        var t = HerbTally()
        t.intention = months.filter { filled($0.intention) }.count
        t.evenings = notes.filter { $0.kind == .friday }.count
        t.worries = worries.count
        t.reflections = reflections.map(\.month)
        t.free = notes.filter { $0.kind == .free }.count
        t.own = own.count
        t.months = months.count
        t.sign = reflections.contains { ["yes", "da"].contains($0.answers?[ReflectionQuestion.signKey] ?? "") }
        t.rest = months.contains { $0.fridays.contains { $0.exerciseId == nil && !filled($0.title) && $0.date <= today } }
        t.step = worries.contains { filled($0.worry?.step) }
        t.parent = worries.contains {
            let p = $0.worry?.parent
            return filled(p?.what) && filled(p?.hardest) && filled(p?.need)
        }
        if !program.isEmpty {
            t.program = (program.filter { done.contains($0.id) }.count, program.count)
        }
        return t
    }

    /// [done so far, needed] for a plant of the catalogue.
    static func progress(_ id: String, _ t: HerbTally, _ facts: HerbFacts) -> (Int, Int) {
        switch id {
        case "intentie": (t.intention, 1)
        case "vineri": (t.evenings, 1)
        case "griji": (t.worries, 1)
        case "reflectie": (t.reflections.count, 1)
        case "randuri": (t.free, 1)
        case "exercitiu": (t.own, 1)
        case "seri5": (t.evenings, 5)
        case "seri15": (t.evenings, 15)
        case "seri30": (t.evenings, 30)
        case "griji5": (t.worries, 5)
        case "griji12": (t.worries, 12)
        case "luni3": (t.months, 3)
        case "banca5": (t.own, 5)
        case "semn": (t.sign ? 1 : 0, 1)
        case "libera": (t.rest ? 1 : 0, 1)
        case "pas": (t.step ? 1 : 0, 1)
        case "parinte": (t.parent ? 1 : 0, 1)
        case "revenit": (facts.returned ? 1 : 0, 1)
        case "claude": (facts.asked ? 1 : 0, 1)
        case "program": t.program.map { ($0.done, $0.all) } ?? (0, 1)
        default: (0, 1)
        }
    }

    /// Gives every plant now due. Returns the plants just earned.
    @discardableResult
    static func earn(_ book: inout HerbBook, _ contents: VaultContents, facts: HerbFacts, now: Date) -> [String] {
        let t = tally(book, contents, today: facts.today)
        var fresh: [String] = []
        for herb in Herb.catalogue where book.earned[herb.id] == nil {
            let (have, need) = progress(herb.id, t, facts)
            if have >= need, need > 0, herb.id != "program" || t.program != nil { fresh.append(herb.id) }
        }
        for month in t.reflections {
            let id = Herb.monthID(month)
            if book.earned[id] == nil, !fresh.contains(id) { fresh.append(id) }
        }
        for id in fresh { book.earned[id] = now }
        return fresh
    }

    /// Whole days from one "2026-11-13" to another.
    static func daysBetween(_ a: String, _ b: String, calendar: Calendar = .current) -> Int {
        guard let from = DayKey.date(a, calendar: calendar), let to = DayKey.date(b, calendar: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

extension VaultContents {
    /// Starts the herbarium if needed and gives every plant now due. `visit`: Fallow was just
    /// opened (for "Welcome back"). Returns the plants just earned.
    @discardableResult
    mutating func checkHerbarium(visit: Bool = false, now: Date = .now, calendar: Calendar = .current) -> [String] {
        var book = herbarium ?? HerbBook.starting(self, now: now, calendar: calendar)
        let today = DayKey.string(now, calendar: calendar)
        let returned = visit && book.lastVisit.map { Herbarium.daysBetween($0, today, calendar: calendar) > Herbarium.awayDays } == true
        let fresh = Herbarium.earn(&book, self, facts: HerbFacts(returned: returned, today: today), now: now)
        if visit { book.lastVisit = today }
        if book != herbarium { herbarium = book }
        return fresh
    }

    /// The plant was pressed into the herbarium.
    mutating func pressPlant(_ id: String) {
        guard var book = herbarium, !book.seen.contains(id) else { return }
        book.seen.append(id)
        herbarium = book
    }

    /// [have, need] for a plant not yet earned.
    func herbProgress(_ id: String, now: Date = .now) -> (Int, Int) {
        guard let book = herbarium else { return (0, 1) }
        let today = DayKey.string(now)
        return Herbarium.progress(id, Herbarium.tally(book, self, today: today), HerbFacts(today: today))
    }
}
