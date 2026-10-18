import Foundation
import WatchConnectivity
import WatchKit

/// Watch side of the iPhone ⇄ Watch link. Receives the workout state and
/// sends commands (set done, skip rest, +30 s) to the iPhone.
final class WatchSessionStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionStore()

    @Published private(set) var snapshot: WatchSnapshot = .idle
    @Published private(set) var isSending = false
    @Published private(set) var isReachable = false

    private var restHaptic: DispatchWorkItem?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: WatchCommand, extra: [String: Any] = [:]) {
        let session = WCSession.default
        var message: [String: Any] = [WatchKeys.command: command.rawValue]
        message.merge(extra) { _, new in new }
        WKInterfaceDevice.current().play(.click)
        isSending = true
        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                self?.receive(reply)
                DispatchQueue.main.async { self?.isSending = false }
            }, errorHandler: { [weak self] _ in
                session.transferUserInfo(message)
                DispatchQueue.main.async { self?.isSending = false }
            })
        } else {
            session.transferUserInfo(message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.isSending = false }
        }
    }

    private func receive(_ payload: [String: Any]) {
        guard let snapshot = WatchCoding.decode(payload[WatchKeys.snapshot]) else { return }
        DispatchQueue.main.async { self.apply(snapshot) }
    }

    private func apply(_ new: WatchSnapshot) {
        // Ignore out-of-order deliveries.
        guard new.updatedAt >= snapshot.updatedAt || new.isActive != snapshot.isActive else { return }
        let wasActive = snapshot.isActive
        snapshot = new
        isSending = false

        let workout = WatchWorkoutManager.shared
        if new.isActive && !wasActive && !workout.isRunning {
            workout.start(configuration: nil)
        } else if !new.isActive && wasActive {
            if new.discarded { workout.discard() } else { workout.end() }
        }
        scheduleRestHaptic()
    }

    /// Tap the wrist when rest is over.
    private func scheduleRestHaptic() {
        restHaptic?.cancel()
        guard let end = snapshot.restEndsAt, end > Date() else { return }
        let item = DispatchWorkItem {
            WKInterfaceDevice.current().play(.notification)
        }
        restHaptic = item
        DispatchQueue.main.asyncAfter(deadline: .now() + end.timeIntervalSinceNow, execute: item)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive(session.receivedApplicationContext)
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }
}
