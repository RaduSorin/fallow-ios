import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence, on this iPhone only: a short summary of the month for the reflection,
/// and a few ideas for next month's intention. Nothing leaves the phone.
/// Shown only where it works (a supported iPhone with Apple Intelligence on, in a language
/// it speaks); everywhere else the app is exactly as before.
enum OnDeviceAI {
    enum Failure: Error {
        case unavailable, failed
    }

    /// The app's language ("en" or "ro").
    static var appLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else { return false }
            return model.supportedLanguages.contains { $0.languageCode?.identifier == appLanguage }
        }
        #endif
        return false
    }

    // MARK: What the model reads (pure, so it can be tested)

    /// Longest text handed to the model, to stay well inside its context.
    static let maxCharacters = 6000

    /// The month in plain text: the intention, the sign, and the notes oldest first.
    static func digest(plan: MonthPlan?, notes: [Note]) -> String {
        var lines: [String] = []
        if let plan, !plan.intention.isEmpty {
            lines.append("Intention: \(plan.intention)")
            if let sign = plan.success, !sign.isEmpty { lines.append("Sign it went well: \(sign)") }
        }
        let sorted = notes.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        for note in sorted {
            var head = "\(note.date) \(note.kind.rawValue)"
            if let title = note.title, !title.isEmpty { head += " – \(title)" }
            if let before = note.before, let after = note.after { head += " (feeling \(before) → \(after) of 10)" }
            if let fit = note.fit { head += " [fit: \(fit.rawValue)]" }
            let body = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(body.isEmpty ? head : "\(head): \(body)")
        }
        let text = lines.joined(separator: "\n")
        return text.count > maxCharacters ? String(text.suffix(maxCharacters)) : text
    }

    private static var languageName: String {
        appLanguage == "ro" ? "Romanian" : "English"
    }

    private static var instructions: String {
        """
        You help one person look back on their own month in a private journal app called Fallow.
        Be warm, plain and brief. Never diagnose, never judge, never give medical advice.
        Use only what is in their notes; do not invent events. Write in \(languageName), \
        speaking to the person as "you".
        """
    }

    // MARK: Asking the model

    /// Three or four sentences: what came up this month and what seemed to help.
    static func monthSummary(plan: MonthPlan?, notes: [Note]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
            Here is my month. Summarize it in three or four sentences: what came up, \
            what seemed to help, and one gentle thing to notice.

            \(digest(plan: plan, notes: notes))
            """
            do {
                return try await session.respond(to: prompt).content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                throw Failure.failed
            }
        }
        #endif
        throw Failure.unavailable
    }

    /// Three short ideas for next month's intention, from the month that is ending.
    static func intentionIdeas(plan: MonthPlan?, notes: [Note]) async throws -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
            Based on my month below, suggest three different intentions for next month. \
            Each is one short sentence in the first person, kind and concrete, under 12 words.

            \(digest(plan: plan, notes: notes))
            """
            do {
                let ideas = try await session.respond(to: prompt, generating: IntentionIdeas.self).content.ideas
                return ideas
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .prefix(3)
                    .map { $0 }
            } catch {
                throw Failure.failed
            }
        }
        #endif
        throw Failure.unavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
struct IntentionIdeas {
    @Guide(description: "Three intentions for next month, each one short first-person sentence", .count(3))
    var ideas: [String]
}
#endif
