import Foundation
import SwiftData

/// A workout plan: a saved, reusable list of exercises ("Plan A: Bench, Rows, ...").
/// Each time it is started it becomes a recorded session (`WorkoutRecord`).
/// The exercise list is stored as JSON so the nested sets stay simple and stable.
@Model
final class SessionTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var lastPerformedAt: Date?
    var itemsData: Data

    init(id: UUID = UUID(), name: String, items: [PlannedExercise]) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.itemsData = JSONCoding.encode(items)
    }

    var items: [PlannedExercise] {
        get { JSONCoding.decode([PlannedExercise].self, from: itemsData) ?? [] }
        set {
            itemsData = JSONCoding.encode(newValue)
            updatedAt = .now
        }
    }
}

/// A recorded session: a finished (or finished-early) workout, started from a
/// workout plan or as a quick session.
@Model
final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var templateID: UUID?
    var startedAt: Date
    var endedAt: Date
    var finishedEarly: Bool
    /// Done as a quick session rather than from a workout plan.
    var isQuick: Bool = false
    var activeCalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var calorieSourceRaw: String?
    var exercisesData: Data

    init(id: UUID = UUID(), name: String, templateID: UUID?, startedAt: Date, endedAt: Date,
         finishedEarly: Bool, exercises: [LoggedExercise]) {
        self.id = id
        self.name = name
        self.templateID = templateID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.finishedEarly = finishedEarly
        self.exercisesData = JSONCoding.encode(exercises)
    }

    var exercises: [LoggedExercise] {
        get { JSONCoding.decode([LoggedExercise].self, from: exercisesData) ?? [] }
        set { exercisesData = JSONCoding.encode(newValue) }
    }

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var calorieSource: CalorieSource? { calorieSourceRaw.flatMap(CalorieSource.init(rawValue:)) }
}

/// Exercise metadata cached from ExerciseDB (or created by hand), so search
/// works offline and history keeps names and muscles.
@Model
final class CachedExercise {
    @Attribute(.unique) var exerciseId: String
    var name: String
    var gifUrl: String?
    var bodyParts: [String]
    var targetMuscles: [String]
    var secondaryMuscles: [String]
    var equipments: [String]
    var instructions: [String]
    var isCustom: Bool
    var lastUsedAt: Date?

    init(dto: ExerciseDTO, isCustom: Bool = false) {
        exerciseId = dto.exerciseId
        name = dto.name
        gifUrl = dto.gifUrl
        bodyParts = dto.bodyParts
        targetMuscles = dto.targetMuscles
        secondaryMuscles = dto.secondaryMuscles
        equipments = dto.equipments
        instructions = dto.instructions
        self.isCustom = isCustom
    }

    func update(from dto: ExerciseDTO) {
        name = dto.name
        gifUrl = dto.gifUrl
        bodyParts = dto.bodyParts
        targetMuscles = dto.targetMuscles
        secondaryMuscles = dto.secondaryMuscles
        equipments = dto.equipments
        if !dto.instructions.isEmpty { instructions = dto.instructions }
    }

    var dto: ExerciseDTO {
        ExerciseDTO(exerciseId: exerciseId, name: name, gifUrl: gifUrl, bodyParts: bodyParts,
                    equipments: equipments, targetMuscles: targetMuscles,
                    secondaryMuscles: secondaryMuscles, instructions: instructions)
    }
}

enum CalorieSource: String, Codable {
    case appleWatch
    case heartRate
    case estimate

    var label: String {
        switch self {
        case .appleWatch: return "Measured by Apple Watch"
        case .heartRate: return "Estimated from heart rate"
        case .estimate: return "Rough estimate (no heart rate data)"
        }
    }
}

enum JSONCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

@MainActor
enum AppModel {
    static let container: ModelContainer = {
        let schema = Schema([SessionTemplate.self, WorkoutRecord.self, CachedExercise.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
    }()
}
