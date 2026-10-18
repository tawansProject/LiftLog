import Foundation

/// The state the iPhone sends to the Watch. The Watch only renders it and
/// sends commands back; the iPhone owns the workout.
struct WatchSnapshot: Codable, Equatable {
    var isActive: Bool
    var sessionName: String = ""
    var startedAt: Date?
    var exerciseName: String = ""
    var exerciseIndex: Int = 0
    var exerciseCount: Int = 0
    /// 0-based index of the next set to do in the current exercise.
    var setIndex: Int = 0
    var setCount: Int = 0
    var setKind: SetKind = .normal
    var targetReps: Int = 0
    var targetWeight: Double = 0
    /// True when every set of the current exercise is done.
    var exerciseFinished: Bool = false
    /// All sets done but effort / injured not recorded yet.
    var needsRating: Bool = false
    /// Every exercise in the session is completed or skipped.
    var allExercisesDone: Bool = false
    /// Sent with an inactive snapshot when the workout was discarded, so the
    /// Watch throws away its Health workout instead of saving it.
    var discarded: Bool = false
    var restEndsAt: Date?
    var restTotal: Int = 0
    var restIsBetweenExercises: Bool = false
    var nextUp: String?
    var updatedAt: Date = Date()

    static let idle = WatchSnapshot(isActive: false)

    var isResting: Bool {
        guard let end = restEndsAt else { return false }
        return end > Date()
    }
}

enum WatchCommand: String, Codable {
    case completeSet
    case skipRest
    case addRest30
    /// Effort 1-10 and injured flag for the current exercise, then move on.
    /// Sent with `WatchKeys.effort` and `WatchKeys.injured`.
    case rateExercise
}

enum WatchKeys {
    static let snapshot = "snapshot"
    static let command = "command"
    static let effort = "effort"
    static let injured = "injured"
}

enum WatchCoding {
    static func encode(_ snapshot: WatchSnapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    static func decode(_ data: Any?) -> WatchSnapshot? {
        guard let data = data as? Data else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}
