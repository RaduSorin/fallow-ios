import Foundation

/// A small daily rhythm, e.g. "Walk without the phone". No streaks: a missed day costs nothing.
struct Rhythm: Codable, Equatable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var createdAt: Date = .now
}

/// How well a Friday exercise fitted. Raw values match Răgaz ("da", "partial", "nu").
enum NoteFit: String, Codable, CaseIterable, Sendable, Identifiable {
    case yes = "da"
    case partly = "partial"
    case no = "nu"

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .yes: "It fitted"
        case .partly: "Partly"
        case .no: "Not for me"
        }
    }
}

extension VaultContents {
    /// Which rhythms were kept on a day ("2026-11-13").
    func rhythmsDone(on day: String) -> Set<String> {
        Set(rhythmLog[day] ?? [])
    }

    mutating func toggleRhythm(_ id: String, on day: String) {
        var done = rhythmsDone(on: day)
        if done.contains(id) { done.remove(id) } else { done.insert(id) }
        rhythmLog[day] = done.isEmpty ? nil : done.sorted()
    }

    mutating func addRhythm(_ title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        rhythms.append(Rhythm(title: clean))
    }

    /// Removes the rhythm; days it was kept stay in the log but are no longer shown.
    mutating func removeRhythm(_ id: String) {
        rhythms.removeAll { $0.id == id }
    }

    /// The last seven days ending today, oldest first, and whether the rhythm was kept on each.
    func week(for rhythm: String, endingOn today: Date, calendar: Calendar = .current) -> [Bool] {
        (0..<7).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return rhythmsDone(on: DayKey.string(day, calendar: calendar)).contains(rhythm)
        }
    }

    func notes(on day: String) -> [Note] {
        notes.filter { $0.date == day && $0.kind != .reflection }.sorted { $0.createdAt > $1.createdAt }
    }

    mutating func deleteNote(_ id: String) {
        notes.removeAll { $0.id == id }
    }
}
