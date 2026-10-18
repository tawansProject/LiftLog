import SwiftUI
import SwiftData

@main
struct FitnessAppMain: App {
    @StateObject private var engine = WorkoutEngine.shared
    @StateObject private var health = HealthKitManager.shared

    init() {
        AppSettings.register()
        Theme.applyAppearance()
        NotificationManager.shared.configure()
        PhoneConnectivity.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(health)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(AppModel.container)
    }
}

struct RootView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @EnvironmentObject private var health: HealthKitManager
    @Query private var records: [WorkoutRecord]
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            SessionListView()
                .tabItem { Label("Workouts", systemImage: "dumbbell.fill") }
                .tag(0)
            HistoryListView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .safeAreaInset(edge: .bottom) {
            if engine.isActive && engine.isMinimized {
                ResumeWorkoutBar()
                    .padding(.horizontal)
                    .padding(.bottom, 56)
            }
        }
        .fullScreenCover(isPresented: liveWorkoutPresented) {
            LiveWorkoutView()
                .environmentObject(engine)
                .environmentObject(health)
        }
        .sheet(item: finishedRecord) { record in
            NavigationStack {
                WorkoutSummaryView(record: record, isFreshlyFinished: true)
            }
        }
        .task {
            await health.requestAuthorization()
        }
    }

    private var liveWorkoutPresented: Binding<Bool> {
        Binding(get: { engine.isActive && !engine.isMinimized },
                set: { presented in if !presented && engine.isActive { engine.isMinimized = true } })
    }

    private var finishedRecord: Binding<WorkoutRecord?> {
        Binding(get: {
            guard let id = engine.finishedRecordID, !engine.isActive else { return nil }
            return records.first { $0.id == id }
        }, set: { value in
            if value == nil { engine.finishedRecordID = nil }
        })
    }
}

struct ResumeWorkoutBar: View {
    @EnvironmentObject private var engine: WorkoutEngine

    var body: some View {
        Button {
            engine.isMinimized = false
        } label: {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.workout?.name ?? "Workout").font(.subheadline.bold())
                    if let start = engine.workout?.startedAt {
                        Text(start, style: .timer).font(.caption.monospacedDigit())
                    }
                }
                Spacer()
                Text("Resume").font(.subheadline.bold())
                Image(systemName: "chevron.up")
            }
            .padding()
            .foregroundStyle(.white)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
