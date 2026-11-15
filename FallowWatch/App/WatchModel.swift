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
