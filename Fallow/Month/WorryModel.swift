import Foundation

/// The weekly worry list: stone (not up to me), clay (up to me, biggest first),
/// the biggest clay broken into small steps, one first step, and the Good Parent's answers.
/// Field names match Răgaz so the import maps directly.
struct WorryList: Codable, Equatable, Sendable {
    var stone: [String] = []
    var clay: [String] = []
    var breakdown: [String]?
    var step: String?
    var parent: GoodParent?

    struct GoodParent: Codable, Equatable, Sendable {
        var what: String?
        var hardest: String?
        var need: String?
    }

    /// Splits pasted or typed lines into separate worries, without bullets or duplicates.
    static func items(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let clean = line
                .trimmingCharacters(in: .whitespaces)
                .replacing(/^[-•*\d.)\s]+/, with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, seen.insert(clean).inserted else { return nil }
            return clean
        }
    }

    /// The note's text: a short summary to reread later.
    func summary() -> String {
        var lines: [String] = []
        if !clay.isEmpty { lines.append(String(localized: "Clay: \(clay.joined(separator: "; "))")) }
        if !stone.isEmpty { lines.append(String(localized: "Stone: \(stone.joined(separator: "; "))")) }
        if let step, !step.isEmpty { lines.append(String(localized: "First step: \(step)")) }
        if let need = parent?.need, !need.isEmpty { lines.append(String(localized: "What I need: \(need)")) }
        return lines.joined(separator: "\n")
    }
}
