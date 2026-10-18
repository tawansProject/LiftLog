import Foundation
import WatchConnectivity

/// iPhone side of the iPhone ⇄ Watch link. Pushes the current workout state to
/// the Watch and applies commands (set done, skip rest) coming back from it.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func push(_ snapshot: WatchSnapshot) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = WatchCoding.encode(snapshot) else { return }
        let payload: [String: Any] = [WatchKeys.snapshot: data]
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in WorkoutEngine.shared.pushToWatch() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message, reply: nil)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message, reply: replyHandler)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo, reply: nil)
    }

    private func handle(_ message: [String: Any], reply: (([String: Any]) -> Void)?) {
        guard let raw = message[WatchKeys.command] as? String, let command = WatchCommand(rawValue: raw) else {
            reply?([:])
            return
        }
        var rating: (effort: Int, injured: Bool)?
        if command == .rateExercise {
            rating = (effort: message[WatchKeys.effort] as? Int ?? 7, injured: message[WatchKeys.injured] as? Bool ?? false)
        }
        let watchRating = rating
        Task { @MainActor in
            let snapshot = WorkoutEngine.shared.handle(command, rating: watchRating)
            if let data = WatchCoding.encode(snapshot) {
                reply?([WatchKeys.snapshot: data])
            } else {
                reply?([:])
            }
        }
    }
}
