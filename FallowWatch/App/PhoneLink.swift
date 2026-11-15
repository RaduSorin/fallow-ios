import Foundation
import WatchConnectivity
import WidgetKit

/// The watch's end of the link with Fallow on the iPhone. It keeps the iPhone's neutral snapshot
/// and the inbox's public key in the watch's own App Group (for the complications), and sends
/// sealed boxes back. It cannot read anything it has sealed.
final class PhoneLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneLink()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Seals an entry with the vault's public key and queues it for the iPhone (delivered even if
    /// the iPhone is out of reach right now). Throws when the iPhone has not sent its key yet.
    func send(_ entry: InboxEntry) throws {
        guard let key = SharedStore.readPublicKey() else { throw Inbox.InboxError.noKey }
        let box = try Inbox.seal(entry, to: key)
        WCSession.default.transferUserInfo(WatchPayload.outgoing(entry, box: box))
    }

    /// Stores what the iPhone sent. Kept apart for clarity: the whole context replaces the copy.
    static func take(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        if WatchPayload.isErased(context) {
            SharedStore.eraseAll()
        } else {
            if let key = WatchPayload.publicKey(in: context) { SharedStore.writePublicKey(key) }
            if let snapshot = WatchPayload.snapshot(in: context) { SharedStore.write(snapshot) }
        }
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in WatchModel.shared.reload() }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        guard state == .activated else { return }
        Self.take(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Self.take(applicationContext)
    }
}
