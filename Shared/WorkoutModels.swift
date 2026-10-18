import Foundation

/// Kind of set. Warm-up sets are ignored by progression and volume stats,
/// drop sets follow the top set's weight when a suggestion is applied.
enum SetKind: String, Codable, CaseIterable, Identifiable {
    case warmup
    case normal
    case drop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .warmup: return "Warm-up"
        case .normal: return "Normal"
        case .drop: return "Drop set"
        }
    }

    /// Short badge shown in front of a set row ("W", "1", "D").
    var badge: String {
        switch self {
        case .warmup: return "W"
        case .normal: return ""
        case .drop: return "D"
        }
    }
}

/// A set as planned in a saved session (template).
struct PlannedSet: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: SetKind = .normal
    var reps: Int = 10
    /// Weight in kilograms. 0 means bodyweight.
    var weight: Double = 0
}

/// One exercise inside a saved session, with its sets and rest times.
struct PlannedExercise: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var exerciseId: String
    var name: String
    var gifUrl: String?
    var bodyParts: [String] = []
    var targetMuscles: [String] = []
    var secondaryMuscles: [String] = []
    var equipments: [String] = []
    var sets: [PlannedSet] = [PlannedSet(), PlannedSet(), PlannedSet()]
    /// Seconds of rest between two sets of this exercise.
    var restBetweenSets: Int = 90
    /// Seconds of rest after the last set, before the next exercise.
    var restAfterExercise: Int = 120
    var notes: String = ""

    var workingSets: [PlannedSet] { sets.filter { $0.kind == .normal } }

    /// "3 × 12 @ 30 kg" style summary of the working sets.
    var setSummary: String {
        let working = workingSets
        guard let first = working.first else { return "\(sets.count) sets" }
        let sameReps = working.allSatisfy { $0.reps == first.reps }
        let maxWeight = working.map(\.weight).max() ?? 0
        var text = sameReps ? "\(working.count) × \(first.reps)" : "\(working.count) sets"
        if maxWeight > 0 { text += " @ \(Format.weight(maxWeight))" }
        let warmups = sets.filter { $0.kind == .warmup }.count
        let drops = sets.filter { $0.kind == .drop }.count
        if warmups > 0 { text += " · \(warmups)W" }
        if drops > 0 { text += " · \(drops)D" }
        return text
    }
}

/// A set as performed during a workout.
struct LoggedSet: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: SetKind
    var targetReps: Int
    var targetWeight: Double
    var reps: Int
    var weight: Double
    var isDone: Bool = false
    var completedAt: Date?

    init(planned: PlannedSet) {
        kind = planned.kind
        targetReps = planned.reps
        targetWeight = planned.weight
        reps = planned.reps
        weight = planned.weight
    }

    var volume: Double { isDone ? Double(reps) * weight : 0 }
}

enum ExerciseStatus: String, Codable {
    case pending
    case completed
    case skipped
}

/// One exercise as performed in a workout, including the effort and injury
/// flags the user records when finishing it.
struct LoggedExercise: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var exerciseId: String
    var name: String
    var gifUrl: String?
    var bodyParts: [String]
    var targetMuscles: [String]
    var secondaryMuscles: [String]
    var equipments: [String]
    var sets: [LoggedSet]
    var restBetweenSets: Int
    var restAfterExercise: Int
    /// Effort 1...10 (RPE-style), recorded after finishing the exercise.
    var effort: Int?
    var injured: Bool = false
    var injuryNote: String = ""
    var status: ExerciseStatus = .pending
    var completedAt: Date?

    init(planned: PlannedExercise) {
        exerciseId = planned.exerciseId
        name = planned.name
        gifUrl = planned.gifUrl
        bodyParts = planned.bodyParts
        targetMuscles = planned.targetMuscles
        secondaryMuscles = planned.secondaryMuscles
        equipments = planned.equipments
        sets = planned.sets.map(LoggedSet.init(planned:))
        restBetweenSets = planned.restBetweenSets
        restAfterExercise = planned.restAfterExercise
    }

    var doneSets: [LoggedSet] { sets.filter(\.isDone) }
    var workingSets: [LoggedSet] { sets.filter { $0.kind == .normal } }
    var doneWorkingSets: [LoggedSet] { workingSets.filter(\.isDone) }
    var volume: Double { sets.filter { $0.kind != .warmup }.reduce(0.0) { $0 + $1.volume } }
    var hasProgress: Bool { sets.contains(where: \.isDone) }
    var allSetsDone: Bool { !sets.isEmpty && sets.allSatisfy(\.isDone) }
    /// Completed, skipped, or every set ticked (even if the effort sheet was dismissed).
    var isFinished: Bool { status != .pending || allSetsDone }

    /// Heaviest completed working set.
    var topSet: LoggedSet? {
        doneWorkingSets.max { lhs, rhs in
            lhs.weight == rhs.weight ? lhs.reps < rhs.reps : lhs.weight < rhs.weight
        }
    }

    /// Turns what was actually performed back into a plan, so the next session
    /// starts from the previous record instead of from scratch.
    func asPlanned() -> PlannedExercise {
        var plan = PlannedExercise(exerciseId: exerciseId, name: name)
        plan.gifUrl = gifUrl
        plan.bodyParts = bodyParts
        plan.targetMuscles = targetMuscles
        plan.secondaryMuscles = secondaryMuscles
        plan.equipments = equipments
        plan.restBetweenSets = restBetweenSets
        plan.restAfterExercise = restAfterExercise
        plan.sets = sets.map { set in
            PlannedSet(kind: set.kind,
                       reps: set.isDone ? set.reps : set.targetReps,
                       weight: set.isDone ? set.weight : set.targetWeight)
        }
        return plan
    }
}

enum Format {
    static func weight(_ kg: Double) -> String {
        if kg == 0 { return "BW" }
        let rounded = (kg * 100).rounded() / 100
        if rounded == rounded.rounded() { return "\(Int(rounded)) kg" }
        return String(format: "%.1f kg", rounded)
    }

    static func number(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func shortDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes) min"
    }

    static func rest(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func volume(_ kg: Double) -> String {
        if kg >= 10_000 { return String(format: "%.1f t", kg / 1000) }
        return "\(Int(kg.rounded())) kg"
    }
}
