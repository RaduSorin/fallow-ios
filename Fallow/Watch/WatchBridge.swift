import Foundation
import WatchConnectivity
import WidgetKit

/// The iPhone's end of the link with the Fallow app on the Apple Watch.
///
/// The watch gets only what the widgets may show (the neutral snapshot) and the inbox's public
/// key. What the watch writes (rhythm ticks, lines) arrives already sealed and goes into the same
/// inbox as the widget's buttons, to be opened after the next Face ID.
final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchBridge()

    private let lock = NSLock()
    private var exercise: WatchExercise?
    private var feelingHandler: (@Sendable (WatchPayload.Feeling) -> Void)?

    /// Where a feeling rated on the watch goes (the running exercise). Set once at launch.
    var onFeeling: (@Sendable (WatchPayload.Feeling) -> Void)? {
        get { lock.withLock { feelingHandler } }
        set { lock.withLock { feelingHandler = newValue } }
    }

    /// The running exercise as the watch may mirror it; nil when none runs.
    func setExercise(_ state: WatchExercise?) {
        let changed = lock.withLock {
            defer { exercise = state }
            return exercise != state
        }
        if changed { sendCurrent() }
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the snapshot and the key as they are in the App Group now. Only the latest
    /// context is delivered, so sending often costs nothing.
    func sendCurrent() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let running = lock.withLock { exercise }
        let context = WatchPayload.context(snapshot: SharedStore.readSnapshot(), publicKey: SharedStore.readPublicKey(), exercise: running)
        try? session.updateApplicationContext(context)
    }

    /// Takes in one transfer from the watch: the sealed box goes into the inbox, a rhythm tick
    /// also into the snapshot. Returns whether anything was stored. Kept apart for the tests.
    @discardableResult
    static func receive(
        _ info: [String: Any],
        folder: URL = SharedStore.inboxFolder,
        readSnapshot: () -> WidgetSnapshot? = SharedStore.readSnapshot,
        writeSnapshot: (WidgetSnapshot) -> Void = SharedStore.write
    ) -> Bool {
        guard let box = WatchPayload.box(in: info), (try? Inbox.store(box, folder: folder)) != nil else { return false }
        if let tick = WatchPayload.tick(in: info), var snapshot = readSnapshot() {
            snapshot.set(tick.rhythmID, done: tick.done, on: tick.day)
            writeSnapshot(snapshot)
        }
        return true
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        if state == .activated { sendCurrent() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // The person switched to another watch: talk to the new one.
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        sendCurrent()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let feeling = WatchPayload.feeling(in: userInfo) {
            onFeeling?(feeling)
            return
        }
        if let interval = WatchPayload.mindful(in: userInfo) {
            // Breathing on the watch: saved only while the person keeps mindful minutes on.
            guard SharedStore.readSnapshot()?.healthMindful == true else { return }
            Task { await MindfulHealth.save(interval) }
            return
        }
        guard Self.receive(userInfo) else { return }
        WidgetCenter.shared.reloadAllTimelines()
        sendCurrent()
    }
}
