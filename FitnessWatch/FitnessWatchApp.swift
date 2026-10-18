import SwiftUI
import HealthKit
import WatchKit

@main
struct FitnessWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var store = WatchSessionStore.shared
    @StateObject private var workout = WatchWorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .environmentObject(workout)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchSessionStore.shared.activate()
        WatchWorkoutManager.shared.requestAuthorization()
    }

    /// Called when the iPhone starts a workout with `startWatchApp(with:)`.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchWorkoutManager.shared.start(configuration: workoutConfiguration)
    }
}
