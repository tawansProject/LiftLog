import Foundation

/// UserDefaults keys and defaults shared by @AppStorage and non-view code.
enum SettingsKey {
    static let restBetweenSets = "restBetweenSets"
    static let restAfterExercise = "restAfterExercise"
    static let weeklyGoal = "weeklyGoal"
    static let bodyWeightKg = "bodyWeightKg"
    static let age = "age"
    static let sex = "sex"
    static let updateTemplateAfterWorkout = "updateTemplateAfterWorkout"
    static let restNotifications = "restNotifications"
    static let launchWatchWorkout = "launchWatchWorkout"
}

enum Sex: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

enum AppSettings {
    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.restBetweenSets: 90,
            SettingsKey.restAfterExercise: 120,
            SettingsKey.weeklyGoal: 3,
            SettingsKey.bodyWeightKg: 70.0,
            SettingsKey.age: 30,
            SettingsKey.sex: Sex.male.rawValue,
            SettingsKey.updateTemplateAfterWorkout: true,
            SettingsKey.restNotifications: true,
            SettingsKey.launchWatchWorkout: true,
        ])
    }

    static var restBetweenSets: Int { UserDefaults.standard.integer(forKey: SettingsKey.restBetweenSets) }
    static var restAfterExercise: Int { UserDefaults.standard.integer(forKey: SettingsKey.restAfterExercise) }
    static var weeklyGoal: Int { max(1, UserDefaults.standard.integer(forKey: SettingsKey.weeklyGoal)) }
    static var bodyWeightKg: Double { UserDefaults.standard.double(forKey: SettingsKey.bodyWeightKg) }
    static var age: Int { UserDefaults.standard.integer(forKey: SettingsKey.age) }
    static var sex: Sex { Sex(rawValue: UserDefaults.standard.string(forKey: SettingsKey.sex) ?? "") ?? .male }
    static var updateTemplateAfterWorkout: Bool { UserDefaults.standard.bool(forKey: SettingsKey.updateTemplateAfterWorkout) }
    static var restNotifications: Bool { UserDefaults.standard.bool(forKey: SettingsKey.restNotifications) }
    static var launchWatchWorkout: Bool { UserDefaults.standard.bool(forKey: SettingsKey.launchWatchWorkout) }
}
