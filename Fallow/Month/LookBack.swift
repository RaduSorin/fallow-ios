import Foundation

/// One Friday note with both feelings rated: how strong it was before and after the exercise.
struct FeelingPoint: Identifiable, Equatable, Sendable {
    var id: String
    /// "2026-11-13"
    var day: String
    var title: String?
    var before: Int
    var after: Int
    var fit: NoteFit?

    /// Positive when the feeling eased after the exercise.
    var change: Int { before - after }
}

/// Looking back on a month, from the notes only. No scores, no streaks.
enum LookBack {
    /// The rated Friday notes, oldest first.
    static func feelings(_ notes: [Note]) -> [FeelingPoint] {
        notes
            .filter { $0.kind == .friday && $0.before != nil && $0.after != nil }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
            .map { note in
                FeelingPoint(
                    id: note.id, day: note.date, title: note.title,
                    before: note.before ?? 0, after: note.after ?? 0, fit: note.fit
                )
            }
    }

    /// How much the feeling eased on average (negative: it grew). Nil without rated notes.
    static func averageChange(_ points: [FeelingPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return Double(points.map(\.change).reduce(0, +)) / Double(points.count)
    }

    /// How many Friday notes said each answer to "Did it fit?".
    static func fits(_ notes: [Note]) -> [NoteFit: Int] {
        notes.filter { $0.kind == .friday }.reduce(into: [:]) { counts, note in
            if let fit = note.fit { counts[fit, default: 0] += 1 }
        }
    }
}

extension Note {
    /// Whether the note contains the words searched for, ignoring case and diacritics
    /// ("gand" finds "gând"). Looks in the text, the title, the reflection answers and the worry list.
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        var haystack = [text, title ?? ""]
        haystack += answers?.values.map { $0 } ?? []
        if let worry {
            haystack += worry.stone + worry.clay + (worry.breakdown ?? [])
            haystack += [worry.step ?? "", worry.parent?.what ?? "", worry.parent?.hardest ?? "", worry.parent?.need ?? ""]
        }
        let all = haystack.joined(separator: "\n")
        return words.allSatisfy { all.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
