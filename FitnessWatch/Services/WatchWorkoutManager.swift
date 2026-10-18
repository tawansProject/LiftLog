import Foundation
import HealthKit

/// Runs an HKWorkoutSession on the Watch during the workout, so heart rate
/// and active calories are measured and saved to Apple Health, and the app
/// stays on screen.
final class WatchWorkoutManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WatchWorkoutManager()

    let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var discardOnEnd = false

    @Published private(set) var isRunning = false
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeEnergy: Double = 0

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        store.requestAuthorization(toShare: share, read: read) { _, _ in }
    }

    func start(configuration: HKWorkoutConfiguration?) {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let config = configuration ?? {
            let c = HKWorkoutConfiguration()
            c.activityType = .traditionalStrengthTraining
            c.locationType = .indoor
            return c
        }()
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            session = nil
            builder = nil
        }
    }

    func end() {
        discardOnEnd = false
        session?.end()
    }

    /// Ends the session without saving a workout to Apple Health.
    func discard() {
        discardOnEnd = true
        session?.end()
    }

    private func reset() {
        session = nil
        builder = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.heartRate = 0
            self.activeEnergy = 0
        }
    }

    // MARK: HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        if discardOnEnd {
            discardOnEnd = false
            builder?.discardWorkout()
            reset()
            return
        }
        builder?.endCollection(withEnd: date) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in
                self?.reset()
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        reset()
    }

    // MARK: HKLiveWorkoutBuilderDelegate

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            switch quantityType {
            case HKQuantityType(.heartRate):
                let bpm = HKUnit.count().unitDivided(by: .minute())
                let value = statistics.mostRecentQuantity()?.doubleValue(for: bpm) ?? 0
                DispatchQueue.main.async { self.heartRate = value }
            case HKQuantityType(.activeEnergyBurned):
                let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                DispatchQueue.main.async { self.activeEnergy = value }
            default:
                break
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
