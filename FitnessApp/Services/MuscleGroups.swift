import SwiftUI

/// Broad muscle groups used for overviews and summaries. ExerciseDB muscle
/// names are mapped onto these.
enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest, back, shoulders, arms, core, legs, cardio, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        case .legs: return "Legs"
        case .cardio: return "Cardio"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .chest: return .red
        case .back: return .blue
        case .shoulders: return .orange
        case .arms: return .purple
        case .core: return .yellow
        case .legs: return .green
        case .cardio: return .pink
        case .other: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rower"
        case .shoulders: return "figure.arms.open"
        case .arms: return "dumbbell.fill"
        case .core: return "figure.core.training"
        case .legs: return "figure.step.training"
        case .cardio: return "heart.fill"
        case .other: return "figure.mixed.cardio"
        }
    }

    static func group(forMuscle muscle: String) -> MuscleGroup {
        switch muscle.lowercased() {
        case "pectorals", "serratus anterior", "chest":
            return .chest
        case "latissimus dorsi", "lats", "upper back", "rhomboids", "trapezius", "traps",
             "erector spinae", "back", "levator scapulae", "lower back", "spine":
            return .back
        case "deltoids", "delts", "rear deltoids", "rotator cuff", "shoulders":
            return .shoulders
        case "biceps", "triceps", "brachialis", "forearms", "wrist flexors", "wrist extensors",
             "grip muscles", "wrists", "hands":
            return .arms
        case "abdominals", "abs", "obliques", "core", "hip flexors":
            return .core
        case "quadriceps", "quads", "hamstrings", "glutes", "calves", "adductors", "abductors",
             "soleus", "tibialis anterior", "ankles", "ankle stabilizers", "feet", "groin", "inner thighs", "shins":
            return .legs
        case "cardiovascular system":
            return .cardio
        default:
            return .other
        }
    }
}

/// How much work each muscle gets in a session. Working sets count fully for
/// target muscles and half for secondary muscles.
struct MuscleLoad: Identifiable {
    var muscle: String
    var group: MuscleGroup
    var primarySets: Double
    var secondarySets: Double

    var id: String { muscle }
    var score: Double { primarySets + secondarySets * 0.5 }
}

struct MuscleInput {
    var target: [String]
    var secondary: [String]
    var sets: Int
}

enum MuscleAnalysis {
    static func loads(of exercises: [MuscleInput]) -> [MuscleLoad] {
        var table: [String: MuscleLoad] = [:]
        for exercise in exercises {
            let sets = Double(max(exercise.sets, 1))
            for muscle in exercise.target {
                var load = table[muscle] ?? MuscleLoad(muscle: muscle, group: .group(forMuscle: muscle), primarySets: 0, secondarySets: 0)
                load.primarySets += sets
                table[muscle] = load
            }
            for muscle in exercise.secondary where !exercise.target.contains(muscle) {
                var load = table[muscle] ?? MuscleLoad(muscle: muscle, group: .group(forMuscle: muscle), primarySets: 0, secondarySets: 0)
                load.secondarySets += sets
                table[muscle] = load
            }
        }
        return table.values.sorted { $0.score > $1.score }
    }

    static func loads(planned: [PlannedExercise]) -> [MuscleLoad] {
        loads(of: planned.map { MuscleInput(target: $0.targetMuscles, secondary: $0.secondaryMuscles, sets: $0.workingSets.count) })
    }

    static func loads(logged: [LoggedExercise]) -> [MuscleLoad] {
        loads(of: logged.filter(\.hasProgress).map { exercise in
            let drops = exercise.sets.filter { $0.kind == .drop && $0.isDone }.count
            return MuscleInput(target: exercise.targetMuscles, secondary: exercise.secondaryMuscles,
                               sets: exercise.doneWorkingSets.count + drops)
        })
    }

    static func groupTotals(_ loads: [MuscleLoad]) -> [GroupTotal] {
        var totals: [MuscleGroup: Double] = [:]
        for load in loads { totals[load.group, default: 0] += load.score }
        return totals.map { GroupTotal(group: $0.key, score: $0.value) }.sorted { $0.score > $1.score }
    }
}

struct GroupTotal: Identifiable {
    var group: MuscleGroup
    var score: Double
    var id: MuscleGroup { group }
}
