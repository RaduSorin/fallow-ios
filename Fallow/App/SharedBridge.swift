import CryptoKit
import Foundation
import WidgetKit

/// Keeps the widgets and Siri in step with the vault: writes the neutral snapshot after every
/// change, and takes in what was dropped in the sealed inbox while Fallow was locked.
@MainActor
enum SharedBridge {
    /// What the widgets may show, from the vault. Pure, so it can be tested.
    static func snapshot(from contents: VaultContents, now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        let month = MonthID(now, calendar: calendar)
        let today = DayKey.string(now, calendar: calendar)
        var snapshot = WidgetSnapshot(writtenAt: now)

        let fridays = [month, month.next].flatMap { contents.plan(for: $0)?.fridays ?? [] }
        snapshot.fridays = fridays.map(\.date)
        snapshot.fridaysWithExercise = fridays.filter { contents.exercise($0.exerciseId) != nil }.map(\.date)

        let summary = MonthSummary(plan: contents.plan(for: month), notes: contents.notes(in: month))
        snapshot.monthFridays = summary.fridays
        snapshot.monthFridaysDone = summary.fridaysDone

        // The same rule as the Month page: the first week looks back on the month that ended.
        let day = calendar.component(.day, from: now)
        if day <= 7, contents.plan(for: month.previous) != nil, contents.reflection(for: month.previous) == nil {
            snapshot.reflectionUntil = DayKey.string(
                calendar.date(byAdding: .day, value: 7 - day, to: now) ?? now,
                calendar: calendar
            )
        }

        snapshot.rhythmCount = contents.rhythms.count
        snapshot.rhythmDay = today
        let ids = Set(contents.rhythms.map(\.id))
        snapshot.rhythmsDone = contents.rhythmsDone(on: today).filter { ids.contains($0) }.sorted()

        if contents.settings.widgetIntention, let intention = contents.plan(for: month)?.intention, !intention.isEmpty {
            snapshot.intention = intention
        }
        if contents.settings.widgetRhythms {
            snapshot.rhythms = contents.rhythms.map { .init(id: $0.id, title: $0.title) }
        }
        return snapshot
    }

    /// Called after every change to the vault.
    static func publish(_ contents: VaultContents) {
        if let raw = contents.inboxKey, let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            SharedStore.writePublicKey(key.publicKey.rawRepresentation)
        }
        let next = snapshot(from: contents)
        var previous = SharedStore.readSnapshot()
        previous?.writtenAt = next.writtenAt
        guard previous != next else { return }
        SharedStore.write(next)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// After Face ID: makes the inbox key if there is none yet, then opens every sealed entry,
    /// applies it and deletes it. Entries that cannot be opened (an old key) are dropped.
    static func drain(into vault: Vault, folder: URL = SharedStore.inboxFolder) {
        guard let contents = vault.contents else { return }
        if contents.inboxKey == nil {
            try? vault.update { $0.inboxKey = Curve25519.KeyAgreement.PrivateKey().rawRepresentation }
        }
        guard let raw = vault.contents?.inboxKey,
              let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) else { return }

        let files = Inbox.waiting(in: folder)
        guard !files.isEmpty else { return }
        let entries = files.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? Inbox.open($0, with: key) }
        }
        do {
            if !entries.isEmpty {
                try vault.update { contents in
                    for entry in entries { contents.apply(entry) }
                }
            }
            for url in files { try? FileManager.default.removeItem(at: url) }
        } catch {
            // Kept for the next time the vault opens.
        }
    }
}

extension VaultContents {
    /// Takes in one entry from the inbox.
    mutating func apply(_ entry: InboxEntry) {
        switch entry.kind {
        case .rhythm:
            guard let id = entry.rhythmID, rhythms.contains(where: { $0.id == id }) else { return }
            let kept = rhythmsDone(on: entry.day).contains(id)
            if kept != (entry.done ?? true) { toggleRhythm(id, on: entry.day) }
        case .note:
            let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let date = DayKey.date(entry.day) else { return }
            save(Note(date: entry.day, month: MonthID(date), kind: .free, text: text, createdAt: entry.createdAt))
        }
    }
}
