import Foundation

/// Claude in Fallow: the conversation, the "What Claude knows about me" note and the settings.
/// All of it stays in the encrypted vault. Each message goes to Claude with only what the person
/// allowed (the context level); the server keeps nothing.
struct CoachState: Codable, Equatable, Sendable {
    /// What Claude gets besides the conversation.
    enum Level: String, Codable, CaseIterable, Sendable {
        /// Only the conversation.
        case chat
        /// The month's intention and its sign (default).
        case intention
        /// The intention and the month's numbers (Fridays done, what helped).
        case month
    }

    struct Message: Codable, Equatable, Sendable, Identifiable {
        enum Role: String, Codable, Sendable { case user, assistant }
        var id: String = UUID().uuidString
        var role: Role
        var text: String
        var at: Date = .now
    }

    /// The person said yes to what is sent, on the first visit.
    var consent = false
    var level: Level = .intention
    var note = ""
    var messages: [Message] = []

    /// Messages kept on the phone, and how many recent ones go with each message.
    static let keep = 300
    static let send = 24
    static let maxNote = 6000

    mutating func append(_ message: Message) {
        messages.append(message)
        if messages.count > Self.keep { messages.removeFirst(messages.count - Self.keep) }
    }
}

extension VaultContents {
    /// What Claude may know about this month, for the chosen level. Never the journal's text.
    func coachContext(_ level: CoachState.Level, english: Bool, today: Date = .now, calendar: Calendar = .current) -> String {
        guard level != .chat else { return "" }
        let month = MonthID(today, calendar: calendar)
        let plan = plan(for: month)
        var lines: [String] = []
        if let plan, !plan.intention.trimmingCharacters(in: .whitespaces).isEmpty {
            let sign = (plan.success ?? "").isEmpty ? "" : (english ? " (the sign: \(plan.success!))" : " (semnul: \(plan.success!))")
            lines.append(english ? "Intention for \(month.nameWithYear): \(plan.intention)\(sign)" : "Intenția pentru \(month.nameWithYear): \(plan.intention)\(sign)")
        } else {
            lines.append(english ? "No intention chosen yet for \(month.nameWithYear)." : "Intenția pentru \(month.nameWithYear) nu e aleasă încă.")
        }
        if level == .month {
            let summary = MonthSummary(plan: plan, notes: notes(in: month))
            lines.append(english
                ? "Fridays with the exercise done: \(summary.fridaysDone) of \(summary.fridays)."
                : "Vineri cu exercițiul făcut: \(summary.fridaysDone) din \(summary.fridays).")
        }
        return lines.joined(separator: "\n")
    }

    /// For the herbarium's "I asked": a message to Claude written after it started.
    var askedClaude: Bool {
        guard let since = herbarium?.since else { return false }
        return coach?.messages.contains { $0.role == .user && $0.at >= since } ?? false
    }
}
