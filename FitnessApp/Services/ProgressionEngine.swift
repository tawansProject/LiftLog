import Foundation

/// A progressive-overload recommendation for the next time an exercise is done.
struct OverloadSuggestion: Equatable {
    enum Action: Equatable {
        case increaseWeight
        case increaseReps
        case hold
        case decrease
        case deload
        case recover

        var label: String {
            switch self {
            case .increaseWeight: return "Add weight"
            case .increaseReps: return "Add reps"
            case .hold: return "Repeat"
            case .decrease: return "Lighten"
            case .deload: return "Deload"
            case .recover: return "Recover"
            }
        }

        var symbol: String {
            switch self {
            case .increaseWeight, .increaseReps: return "arrow.up.circle.fill"
            case .hold: return "equal.circle.fill"
            case .decrease, .deload: return "arrow.down.circle.fill"
            case .recover: return "cross.circle.fill"
            }
        }
    }

    var action: Action
    var previousWeight: Double
    var previousReps: Int
    var weight: Double
    var reps: Int
    var reason: String

    var headline: String {
        "\(action.label): \(Format.weight(weight)) × \(reps)"
    }

    var isChange: Bool { weight != previousWeight || reps != previousReps }
}

/// Progressive overload rules. Inputs are the most recent logs of one exercise
/// (newest first). Effort (1-10) and the injured flag drive the decision:
///
/// - Injured last time: drop the load ~20% (or reps ~30% for bodyweight).
/// - Injured in 2 of the last 3 sessions: same, plus advise swapping the exercise.
/// - All working sets hit their target reps:
///   - effort <= 5: big jump (2 weight steps, or +2 reps)
///   - effort 6-7: one weight step (or +1 rep)
///   - effort 8: add one rep per set; once at the rep ceiling, add weight and reset reps
///   - effort 9-10: repeat the same numbers
///   - first session back after an injury: at most one small step
/// - Missed reps: repeat if at least 85% of target reps were done, otherwise drop ~10%.
/// - Stalled (same top weight 3 sessions running without hitting targets): deload 10%.
enum ProgressionEngine {
    static let repCeiling = 15
    static let repFloor = 6

    static func suggest(history: [LoggedExercise]) -> OverloadSuggestion? {
        let logs = history.filter { !$0.doneWorkingSets.isEmpty }
        guard let last = logs.first, let top = last.topSet else { return nil }

        let step = Self.increment(for: last.equipments)
        let isBodyweight = top.weight == 0
        let topWeight = top.weight
        // Conservative: the lowest rep count among the sets done at top weight.
        let repsAtTop = last.doneWorkingSets.filter { $0.weight == topWeight }.map(\.reps).min() ?? top.reps
        let targetReps = last.workingSets.map(\.targetReps).max() ?? repsAtTop
        let effort = last.effort ?? 7

        let working = last.workingSets
        let hitAll = working.allSatisfy { $0.isDone && $0.reps >= $0.targetReps }
        let targetTotal = working.reduce(0) { $0 + $1.targetReps }
        let doneTotal = working.filter(\.isDone).reduce(0) { $0 + $1.reps }
        let completion = targetTotal > 0 ? Double(doneTotal) / Double(targetTotal) : 1

        func make(_ action: OverloadSuggestion.Action, weight: Double, reps: Int, _ reason: String) -> OverloadSuggestion {
            var reason = reason
            if last.effort == nil && action != .recover {
                reason += " (No effort was recorded last time, so effort 7 was assumed.)"
            }
            return OverloadSuggestion(action: action, previousWeight: topWeight, previousReps: repsAtTop,
                                      weight: max(0, weight), reps: max(1, reps), reason: reason)
        }

        // 1. Injury always wins.
        let recentInjuries = logs.prefix(3).filter(\.injured).count
        if last.injured {
            var reason = "You flagged an injury last time. Go about 20% lighter and keep every rep pain-free."
            if recentInjuries >= 2 {
                reason += " It's been flagged in \(recentInjuries) of your last 3 sessions, so consider swapping this exercise or resting it."
            }
            if !last.injuryNote.isEmpty { reason += " Note: \(last.injuryNote)" }
            if isBodyweight {
                return make(.recover, weight: 0, reps: Int((Double(repsAtTop) * 0.7).rounded()), reason)
            }
            return make(.recover, weight: round(topWeight * 0.8, to: step), reps: repsAtTop, reason)
        }

        let returningFromInjury = logs.count > 1 && logs[1].injured

        // 2. Stalled: same top weight three sessions in a row without hitting targets.
        if logs.count >= 3 && !isBodyweight {
            let lastThree = Array(logs.prefix(3))
            let sameWeight = lastThree.allSatisfy { $0.topSet?.weight == topWeight }
            let noneHit = lastThree.allSatisfy { log in
                !log.workingSets.allSatisfy { $0.isDone && $0.reps >= $0.targetReps }
            }
            if sameWeight && noneHit {
                return make(.deload, weight: round(topWeight * 0.9, to: step), reps: targetReps,
                            "Stuck at \(Format.weight(topWeight)) for 3 sessions. Deload 10% and build back up.")
            }
        }

        // 3. Hit every target.
        if hitAll {
            if returningFromInjury {
                if isBodyweight {
                    return make(.increaseReps, weight: 0, reps: repsAtTop + 1, "First clean session after an injury. Add just one rep.")
                }
                return make(.increaseWeight, weight: topWeight + step, reps: repsAtTop,
                            "First clean session after an injury. One small step up only.")
            }
            switch effort {
            case ...5:
                if isBodyweight {
                    return make(.increaseReps, weight: 0, reps: repsAtTop + 2, "Felt easy (effort \(effort)). Add 2 reps per set.")
                }
                return make(.increaseWeight, weight: topWeight + step * 2, reps: repsAtTop,
                            "Felt easy (effort \(effort)). Jump up \(Format.weight(step * 2)).")
            case 6...7:
                if isBodyweight {
                    return make(.increaseReps, weight: 0, reps: repsAtTop + 1, "Solid work (effort \(effort)). Add a rep per set.")
                }
                return make(.increaseWeight, weight: topWeight + step, reps: repsAtTop,
                            "Solid work (effort \(effort)). Add \(Format.weight(step)).")
            case 8:
                if isBodyweight || repsAtTop < repCeiling {
                    return make(.increaseReps, weight: topWeight, reps: repsAtTop + 1,
                                "Hard but complete (effort 8). Add one rep per set before adding weight.")
                }
                return make(.increaseWeight, weight: topWeight + step, reps: max(repFloor, repsAtTop - 4),
                            "You're at \(repsAtTop) reps. Add \(Format.weight(step)) and drop to \(max(repFloor, repsAtTop - 4)) reps.")
            default:
                return make(.hold, weight: topWeight, reps: repsAtTop,
                            "Done, but near your limit (effort \(effort)). Repeat it until it feels easier.")
            }
        }

        // 4. Missed reps.
        if completion >= 0.85 && effort < 10 {
            return make(.hold, weight: topWeight, reps: targetReps,
                        "Almost there (\(Int(completion * 100))% of target reps). Repeat the same target.")
        }
        if isBodyweight {
            return make(.decrease, weight: 0, reps: max(1, repsAtTop),
                        "Missed reps. Aim for \(max(1, repsAtTop)) clean reps per set.")
        }
        return make(.decrease, weight: round(topWeight * 0.9, to: step), reps: targetReps,
                    "Missed a good chunk of reps (\(Int(completion * 100))%). Drop about 10% and hit every rep.")
    }

    /// Smallest sensible weight step for the equipment, in kg.
    static func increment(for equipments: [String]) -> Double {
        let eq = equipments.map { $0.lowercased() }
        // Dumbbells and kettlebells usually go up in 2 kg steps; barbells,
        // machines and cables in 2.5 kg.
        if eq.contains(where: { $0.contains("dumbbell") || $0.contains("kettlebell") }) { return 2 }
        return 2.5
    }

    static func round(_ weight: Double, to increment: Double) -> Double {
        guard increment > 0 else { return weight }
        return (weight / increment).rounded() * increment
    }

    /// Applies a suggestion to a planned exercise. Working sets take the new
    /// weight and reps; warm-up and drop sets keep their ratio to the top set.
    static func apply(_ suggestion: OverloadSuggestion, to plan: PlannedExercise) -> PlannedExercise {
        var plan = plan
        let step = Self.increment(for: plan.equipments)
        let oldTop = plan.workingSets.map(\.weight).max() ?? suggestion.previousWeight
        let ratio = oldTop > 0 ? suggestion.weight / oldTop : 1
        plan.sets = plan.sets.map { set in
            var set = set
            switch set.kind {
            case .normal:
                set.weight = suggestion.weight
                set.reps = suggestion.reps
            case .warmup, .drop:
                if set.weight > 0 { set.weight = round(set.weight * ratio, to: step) }
            }
            return set
        }
        return plan
    }
}
