import Foundation
import HealthKit

struct CalorieEstimate {
    var kilocalories: Double
    var source: CalorieSource
    var averageHeartRate: Double?
    var maxHeartRate: Double?
}

/// Reads heart rate, active energy and body data from Apple Health, and
/// launches the Watch workout so the Watch records heart rate and calories.
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    let store = HKHealthStore()
    @Published private(set) var isAuthorized = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.bodyMass),
            HKObjectType.workoutType(),
        ]
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    /// Opens the Watch app and starts a strength workout there, so heart rate
    /// and active energy are measured during the session.
    func startWatchWorkout() {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        store.startWatchApp(with: config) { _, _ in }
    }

    // MARK: Queries

    func activeEnergy(from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(.activeEnergyBurned), predicate: predicate),
            options: .cumulativeSum)
        guard let result = try? await descriptor.result(for: store),
              let sum = result.sumQuantity()?.doubleValue(for: .kilocalorie()),
              sum > 0 else { return nil }
        return sum
    }

    func heartRate(from start: Date, to end: Date) async -> (average: Double, max: Double)? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate),
            options: [.discreteAverage, .discreteMax])
        let bpm = HKUnit.count().unitDivided(by: .minute())
        guard let result = try? await descriptor.result(for: store),
              let avg = result.averageQuantity()?.doubleValue(for: bpm) else { return nil }
        let max = result.maximumQuantity()?.doubleValue(for: bpm) ?? avg
        return (avg, max)
    }

    func latestBodyMass() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    func age() -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthday = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: .now).year
    }

    func sex() -> Sex? {
        guard let value = try? store.biologicalSex().biologicalSex else { return nil }
        switch value {
        case .male: return .male
        case .female: return .female
        default: return nil
        }
    }

    // MARK: Calories

    /// Best available calorie number for a workout window:
    /// 1. Active energy recorded by Apple Watch during the window.
    /// 2. Average heart rate from Health, with the Keytel et al. (2005) formula.
    /// 3. A MET estimate for strength training (about 5 METs).
    func estimateCalories(from start: Date, to end: Date) async -> CalorieEstimate {
        let minutes = max(end.timeIntervalSince(start) / 60, 1)
        var weight = AppSettings.bodyWeightKg
        var age = Double(AppSettings.age)
        var sex = AppSettings.sex

        if isAvailable {
            if let hkWeight = await latestBodyMass() { weight = hkWeight }
            if let hkAge = self.age() { age = Double(hkAge) }
            if let hkSex = self.sex() { sex = hkSex }
        }

        let heart = isAvailable ? await heartRate(from: start, to: end) : nil

        if isAvailable, let measured = await activeEnergy(from: start, to: end) {
            return CalorieEstimate(kilocalories: measured, source: .appleWatch,
                                   averageHeartRate: heart?.average, maxHeartRate: heart?.max)
        }

        if let heart {
            let perMinute: Double
            switch sex {
            case .male:
                perMinute = (-55.0969 + 0.6309 * heart.average + 0.1988 * weight + 0.2017 * age) / 4.184
            case .female:
                perMinute = (-20.4022 + 0.4472 * heart.average - 0.1263 * weight + 0.074 * age) / 4.184
            }
            return CalorieEstimate(kilocalories: max(perMinute, 0) * minutes, source: .heartRate,
                                   averageHeartRate: heart.average, maxHeartRate: heart.max)
        }

        // kcal = MET × 3.5 × kg / 200 per minute
        let met = 5.0
        return CalorieEstimate(kilocalories: met * 3.5 * weight / 200 * minutes, source: .estimate,
                               averageHeartRate: nil, maxHeartRate: nil)
    }
}
