import Foundation

/// One exercise in the person's own bank: from a pack (maybe changed since), or written by them.
/// Fields match Răgaz so the import maps directly.
struct Exercise: Codable, Equatable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    /// e.g. "Self-compassion", "Awareness".
    var category: String?
    var minutes: Int?
    /// What to do, as plain text (paragraphs separated by empty lines).
    var steps: String = ""
    /// The pack it came from, and whether it was changed since. Nil: written by the person.
    var packId: String?
    var packTitle: String?
    var edited: Bool?
    /// Position inside its pack, to keep the program's order.
    var order: Int?
}

/// An exercise pack as a file: {id, title, description, author, exercises: [{title, category, minutes, steps}]}.
/// The same shape Răgaz shares, so a pack exported there opens here.
struct ExercisePack: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var title: String
        var category: String?
        var minutes: Int?
        var steps: String?
    }

    var id: String
    var title: String
    var description: String?
    var author: String?
    var exercises: [Item]

    enum PackError: Error, Equatable {
        case unreadable
        case empty
    }

    /// Reads a pack file, cleaning each exercise the way Răgaz does and skipping ones without a title.
    static func decode(_ data: Data) throws -> ExercisePack {
        guard var pack = try? JSONDecoder().decode(ExercisePack.self, from: data) else {
            throw PackError.unreadable
        }
        pack.title = String(pack.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        pack.exercises = pack.exercises.compactMap { item in
            let title = String(item.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            guard !title.isEmpty else { return nil }
            let category = item.category.map { String($0.trimmingCharacters(in: .whitespaces).prefix(60)) }
            return Item(
                title: title,
                category: category?.isEmpty == true ? nil : category,
                minutes: (item.minutes ?? 0) > 0 ? item.minutes : nil,
                steps: item.steps.map { String($0.prefix(8000)) }
            )
        }
        guard !pack.exercises.isEmpty, !pack.id.isEmpty else { throw PackError.empty }
        return pack
    }
}

extension VaultContents {
    func exercise(_ id: String?) -> Exercise? {
        guard let id else { return nil }
        return exercises.first { $0.id == id }
    }

    /// The bank in a stable order: packs in their own order, then the person's own by title.
    var sortedExercises: [Exercise] {
        exercises.sorted { a, b in
            switch (a.packTitle, b.packTitle) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                if let x = a.order, let y = b.order, x != y { return x < y }
                return a.title.localizedCompare(b.title) == .orderedAscending
            }
        }
    }

    mutating func save(_ exercise: Exercise) {
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            var changed = exercise
            if changed.packId != nil, changed != exercises[index] { changed.edited = true }
            exercises[index] = changed
        } else {
            exercises.append(exercise)
        }
    }

    mutating func deleteExercise(_ id: String) {
        exercises.removeAll { $0.id == id }
        // Fridays that pointed to it keep their title and become free text.
        for index in months.indices {
            for f in months[index].fridays.indices where months[index].fridays[f].exerciseId == id {
                months[index].fridays[f].exerciseId = nil
            }
        }
    }

    /// Imports a pack: exercises already imported and not changed since are updated,
    /// changed ones and the person's own stay as they are. Returns how many were added.
    @discardableResult
    mutating func importPack(_ pack: ExercisePack) -> Int {
        var added = 0
        for (order, item) in pack.exercises.enumerated() {
            let existing = exercises.firstIndex {
                $0.packId == pack.id && $0.title.lowercased() == item.title.lowercased()
            }
            if let existing, exercises[existing].edited == true { continue }
            let exercise = Exercise(
                id: existing.map { exercises[$0].id } ?? UUID().uuidString,
                title: item.title,
                category: item.category,
                minutes: item.minutes,
                steps: item.steps ?? "",
                packId: pack.id,
                packTitle: pack.title,
                edited: nil,
                order: order
            )
            if let existing {
                exercises[existing] = exercise
            } else {
                exercises.append(exercise)
                added += 1
            }
        }
        return added
    }
}
