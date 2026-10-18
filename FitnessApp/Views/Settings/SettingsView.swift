import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var health: HealthKitManager
    @AppStorage(SettingsKey.restBetweenSets) private var restBetweenSets = 90
    @AppStorage(SettingsKey.restAfterExercise) private var restAfterExercise = 120
    @AppStorage(SettingsKey.weeklyGoal) private var weeklyGoal = 3
    @AppStorage(SettingsKey.bodyWeightKg) private var bodyWeightKg = 70.0
    @AppStorage(SettingsKey.age) private var age = 30
    @AppStorage(SettingsKey.sex) private var sex = Sex.male.rawValue
    @AppStorage(SettingsKey.updateTemplateAfterWorkout) private var updateTemplate = true
    @AppStorage(SettingsKey.restNotifications) private var restNotifications = true
    @AppStorage(SettingsKey.launchWatchWorkout) private var launchWatch = true
    @Query private var cached: [CachedExercise]

    @State private var downloading = false
    @State private var downloadProgress = ""
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Default rest timers") {
                        Stepper(value: $restBetweenSets, in: 0...600, step: 15) {
                            LabeledContent("Between sets", value: Format.rest(restBetweenSets))
                        }
                        Stepper(value: $restAfterExercise, in: 0...900, step: 15) {
                            LabeledContent("Between exercises", value: Format.rest(restAfterExercise))
                        }
                        Toggle("Notify when rest is over", isOn: $restNotifications)
                    }
    
                    Section {
                        Stepper(value: $weeklyGoal, in: 1...7) {
                            LabeledContent("Weekly goal", value: "\(weeklyGoal) workouts")
                        }
                        Toggle("Save last weights into the plan", isOn: $updateTemplate)
                    } header: {
                        Text("Progress")
                    } footer: {
                        Text("On: after a session, its workout plan is updated with what you actually lifted, so next time starts from your previous record. Off: the plan keeps its own numbers, and only newer records of the same exercise from other sessions are pulled in.")
                    }
    
                    Section {
                        Toggle("Start workout on Apple Watch", isOn: $launchWatch)
                        Button("Connect Apple Health") {
                            Task {
                                await health.requestAuthorization()
                                await pullProfile()
                            }
                        }
                        if let healthMessage {
                            Text(healthMessage).font(.caption).foregroundStyle(Theme.subtext)
                        }
                    } header: {
                        Text("Apple Watch & Health")
                    } footer: {
                        Text("The Watch records heart rate and active calories during the workout. Without it, calories are estimated from any heart rate in Apple Health, or from duration and body weight.")
                    }
    
                    Section("Body (for calorie estimates)") {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("kg", value: $bodyWeightKg, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("kg").foregroundStyle(Theme.subtext)
                        }
                        Stepper(value: $age, in: 12...100) { LabeledContent("Age", value: "\(age)") }
                        Picker("Sex", selection: $sex) {
                            ForEach(Sex.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    }
    
                    Section {
                        LabeledContent("Exercises on this phone", value: "\(cached.count)")
                        Button {
                            Task { await downloadLibrary() }
                        } label: {
                            if downloading {
                                HStack { ProgressView(); Text(downloadProgress) }
                            } else {
                                Text("Download full library for offline search")
                            }
                        }
                        .disabled(downloading)
                    } header: {
                        Text("Exercise library")
                    } footer: {
                        Text("Downloads every exercise and its details so search works without internet. Animations still load online.")
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("Settings")
        }
    }

    private func pullProfile() async {
        var found: [String] = []
        if let kg = await health.latestBodyMass() { bodyWeightKg = (kg * 10).rounded() / 10; found.append("weight") }
        if let years = health.age() { age = years; found.append("age") }
        if let value = health.sex() { sex = value.rawValue; found.append("sex") }
        healthMessage = found.isEmpty ? "Connected. No body data found in Health, so the values below are used."
                                      : "Connected. Updated \(found.joined(separator: ", ")) from Health."
    }

    private func downloadLibrary() async {
        downloading = true
        defer { downloading = false }
        do {
            let all = try await ExerciseDBClient.shared.fetchAll { done, total in
                Task { @MainActor in downloadProgress = "\(done) / \(total)" }
            }
            let existing = Dictionary(uniqueKeysWithValues: cached.map { ($0.exerciseId, $0) })
            for dto in all {
                if let item = existing[dto.exerciseId] {
                    if !item.isCustom { item.update(from: dto) }
                } else {
                    context.insert(CachedExercise(dto: dto))
                }
            }
            try? context.save()
            downloadProgress = "Done"
        } catch {
            downloadProgress = error.localizedDescription
        }
    }
}
