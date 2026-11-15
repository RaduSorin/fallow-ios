import Foundation
import Observation
import WatchKit
import WidgetKit

/// What the watch app shows: the iPhone's latest snapshot, and whether ticks can be sealed.
@MainActor
@Observable
final class WatchModel {
    static let shared = WatchModel()

    private(set) var snapshot: WidgetSnapshot? = SharedStore.readSnapshot()
    private(set) var canWrite = SharedStore.readPublicKey() != nil
    /// Shown under the rhythms when a tick could not be sealed.
    var problem: LocalizedStringResource?
    /// The exercise running on the iPhone, mirrored. In memory only.
    private(set) var exercise: WatchExercise?
    /// Set when a new exercise starts, so the watch opens it on its own.
    var showExercise = false

    func updateExercise(_ next: WatchExercise?) {
        let isNew = next != nil && next?.session != exercise?.session
        var merged = next
        // A rating made here and not yet echoed back by the iPhone stays.
        if let current = exercise, current.session == next?.session {
            merged?.before = next?.before ?? current.before
            merged?.after = next?.after ?? current.after
        }
        exercise = merged
        if isNew { showExercise = true }
        if next == nil { showExercise = false }
    }

    /// Rates the feeling before or after, 0 to 10, and sends it to the iPhone.
    func rate(before: Int? = nil, after: Int? = nil) {
        guard var current = exercise else { return }
        if let before { current.before = before }
        if let after { current.after = after }
        exercise = current
        PhoneLink.shared.sendFeeling(.init(session: current.session, before: before, after: after))
        WKInterfaceDevice.current().play(.success)
    }

    func reload() {
        snapshot = SharedStore.readSnapshot()
        canWrite = SharedStore.readPublicKey() != nil
        if canWrite { problem = nil }
    }

    func isDone(_ rhythm: WatchRhythm, on day: String) -> Bool {
        snapshot?.done(on: day).contains(rhythm.id) ?? false
    }

    /// Ticks (or unticks) a rhythm: sealed to the iPhone, and kept in the copy right away so the
    /// ring and the complications move.
    func toggle(_ rhythm: WatchRhythm, on day: String) {
        guard var next = snapshot else { return }
        let done = !next.done(on: day).contains(rhythm.id)
        do {
            try PhoneLink.shared.send(.rhythm(rhythm.id, done: done, day: day))
        } catch {
            problem = "Open Fallow on your iPhone once, then try again."
            WKInterfaceDevice.current().play(.failure)
            return
        }
        next.set(rhythm.id, done: done, on: day)
        SharedStore.write(next)
        snapshot = next
        problem = nil
        WidgetCenter.shared.reloadAllTimelines()
        WKInterfaceDevice.current().play(done ? .success : .click)
    }
}
