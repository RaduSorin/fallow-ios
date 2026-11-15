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
        let context = WatchPayload.context(snapshot: SharedStore.readSnapshot(), publicKey: SharedStore.readPublicKey())
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
        guard Self.receive(userInfo) else { return }
        WidgetCenter.shared.reloadAllTimelines()
        sendCurrent()
    }
}
