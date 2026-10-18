import Foundation

/// Lookups over past workouts: previous records of an exercise, personal
/// records, and what to pre-fill when an exercise is picked again.
enum HistoryService {
    /// Logs of one exercise, newest first, only where something was done.
    static func logs(for exerciseId: String, in records: [WorkoutRecord], before date: Date? = nil) -> [LoggedExercise] {
        records
            .filter { record in date.map { record.startedAt < $0 } ?? true }
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap { record in record.exercises.filter { $0.exerciseId == exerciseId && $0.hasProgress } }
    }

    static func lastLog(for exerciseId: String, in records: [WorkoutRecord]) -> LoggedExercise? {
        logs(for: exerciseId, in: records).first
    }

    /// Most recent log of an exercise together with the date of its workout.
    static func lastLogWithDate(for exerciseId: String, in records: [WorkoutRecord]) -> (log: LoggedExercise, date: Date)? {
        for record in records.sorted(by: { $0.startedAt > $1.startedAt }) {
            if let log = record.exercises.first(where: { $0.exerciseId == exerciseId && $0.hasProgress }) {
                return (log: log, date: record.endedAt)
            }
        }
        return nil
    }

    static func suggestion(for exerciseId: String, in records: [WorkoutRecord]) -> OverloadSuggestion? {
        ProgressionEngine.suggest(history: Array(logs(for: exerciseId, in: records).prefix(5)))
    }

    /// The plan to start from when this exercise is added to a session:
    /// the last performed record, else the same exercise in another saved
    /// session, else a fresh default.
    static func prefill(for dto: ExerciseDTO, records: [WorkoutRecord], templates: [SessionTemplate],
                        restBetweenSets: Int, restAfterExercise: Int) -> (plan: PlannedExercise, source: PrefillSource) {
        if let last = lastLog(for: dto.exerciseId, in: records) {
            var plan = last.asPlanned()
            plan.id = UUID()
            return (plan: plan, source: .lastWorkout)
        }
        let fromTemplate = templates
            .sorted { $0.updatedAt > $1.updatedAt }
            .lazy
            .compactMap { $0.items.first { $0.exerciseId == dto.exerciseId } }
            .first
        if var plan = fromTemplate {
            plan.id = UUID()
            plan.sets = plan.sets.map { PlannedSet(kind: $0.kind, reps: $0.reps, weight: $0.weight) }
            return (plan: plan, source: .otherSession)
        }
        let fresh = dto.planned(defaultRestBetweenSets: restBetweenSets, defaultRestAfterExercise: restAfterExercise)
        return (plan: fresh, source: PrefillSource.none)
    }

    enum PrefillSource {
        case lastWorkout, otherSession, none

        var note: String? {
            switch self {
            case .lastWorkout: return "Filled in from your last workout"
            case .otherSession: return "Filled in from another saved session"
            case .none: return nil
            }
        }
    }

    /// Best weight ever lifted for an exercise before a date (for PR detection).
    static func bestWeight(for exerciseId: String, in records: [WorkoutRecord], before date: Date) -> Double {
        logs(for: exerciseId, in: records, before: date).compactMap { $0.topSet?.weight }.max() ?? 0
    }

    /// Estimated one-rep max (Epley).
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    struct PersonalRecord: Identifiable {
        var exerciseName: String
        var weight: Double
        var reps: Int
        var previousBest: Double
        var id: String { exerciseName }
    }

    /// Exercises in this record where the top weight beat every earlier session.
    static func personalRecords(in record: WorkoutRecord, allRecords: [WorkoutRecord]) -> [PersonalRecord] {
        record.exercises.compactMap { exercise in
            guard let top = exercise.topSet, top.weight > 0 else { return nil }
            let previous = bestWeight(for: exercise.exerciseId, in: allRecords, before: record.startedAt)
            guard previous > 0, top.weight > previous else { return nil }
            return PersonalRecord(exerciseName: exercise.name, weight: top.weight, reps: top.reps, previousBest: previous)
        }
    }
}
