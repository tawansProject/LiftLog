import SwiftUI

/// Dark blue theme matching the iPhone app.
enum WatchTheme {
    static let accent = Color(red: 0.302, green: 0.553, blue: 1.0)
    /// Navy text on white buttons.
    static let ink = Color(red: 0.039, green: 0.090, blue: 0.180)
    static let background = LinearGradient(colors: [Color(red: 0.075, green: 0.157, blue: 0.290),
                                                     Color(red: 0.020, green: 0.050, blue: 0.110)],
                                           startPoint: .top, endPoint: .bottom)
}

/// The Watch shows one thing at a time: the current set with a big Done
/// button, or the rest countdown.
struct WatchRootView: View {
    @EnvironmentObject private var store: WatchSessionStore

    var body: some View {
        let snapshot = store.snapshot
        Group {
            if !snapshot.isActive {
                IdleView()
            } else if snapshot.needsRating {
                // Outside the rest / current-set switch so the selection
                // survives the rest timer ending.
                EffortRatingView(snapshot: snapshot)
                    .id(snapshot.exerciseIndex)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let end = snapshot.restEndsAt, end > context.date {
                        RestView(snapshot: snapshot, end: end)
                    } else {
                        CurrentSetView(snapshot: snapshot)
                    }
                }
            }
        }
        .tint(WatchTheme.accent)
        .background(WatchTheme.background.ignoresSafeArea())
    }
}

struct IdleView: View {
    @EnvironmentObject private var store: WatchSessionStore

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("No workout")
                .font(.headline)
            Text("Start a session on your iPhone. It will show up here.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if !store.isReachable {
                Label("iPhone not reachable", systemImage: "iphone.slash")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }
}

/// Header line: total time, heart rate and calories.
struct WorkoutMetricsLine: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    var startedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            if let startedAt {
                Text(startedAt, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
            if workout.heartRate > 0 {
                Label("\(Int(workout.heartRate))", systemImage: "heart.fill")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.red)
            }
            if workout.activeEnergy > 0 {
                Text("\(Int(workout.activeEnergy)) kcal")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange)
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

struct CurrentSetView: View {
    @EnvironmentObject private var store: WatchSessionStore
    var snapshot: WatchSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                WorkoutMetricsLine(startedAt: snapshot.startedAt)
                Text(snapshot.exerciseName)
                    .font(.headline)
                    .lineLimit(2)
                Text("Exercise \(snapshot.exerciseIndex + 1)/\(snapshot.exerciseCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if snapshot.exerciseFinished {
                    Label(snapshot.allExercisesDone ? "Workout complete" : "Exercise done", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Text(snapshot.allExercisesDone ? "Tap Finish on your iPhone to see the summary." : "Pick the next exercise on your iPhone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(setTitle).font(.subheadline.bold()).foregroundStyle(kindColor)
                        Spacer()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(snapshot.targetReps)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("reps").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(snapshot.targetWeight > 0 ? Format.number(snapshot.targetWeight) : "BW")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        if snapshot.targetWeight > 0 {
                            Text("kg").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        store.send(.completeSet)
                    } label: {
                        Label(store.isSending ? "Sending…" : "Done", systemImage: "checkmark")
                            .font(.headline)
                            .foregroundStyle(WatchTheme.ink)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .disabled(store.isSending)
                }

                if let next = snapshot.nextUp {
                    Text(next)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var setTitle: String {
        let position = "Set \(min(snapshot.setIndex + 1, snapshot.setCount)) of \(snapshot.setCount)"
        switch snapshot.setKind {
        case .warmup: return "\(position) · Warm-up"
        case .drop: return "\(position) · Drop set"
        case .normal: return position
        }
    }

    private var kindColor: Color {
        switch snapshot.setKind {
        case .warmup: return .orange
        case .drop: return .purple
        case .normal: return .primary
        }
    }
}

/// After the last set: effort 1-10 (Digital Crown or − / +) and an Injured
/// toggle, on its own screen. Both feed the progressive-overload suggestion.
struct EffortRatingView: View {
    @EnvironmentObject private var store: WatchSessionStore
    var snapshot: WatchSnapshot
    @State private var crown: Double = 7
    @State private var injured = false

    private var effort: Int { Int(crown.rounded()) }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(snapshot.exerciseName).font(.caption2).lineLimit(1)
                Spacer(minLength: 4)
                if let end = snapshot.restEndsAt, end > Date() {
                    Text(timerInterval: Date()...max(end, Date()), countsDown: true)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.orange)
                        .frame(maxWidth: 44)
                }
            }
            Text("Effort").font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button { crown = max(1, crown.rounded() - 1) } label: { Image(systemName: "minus") }
                    .frame(width: 40)
                VStack(spacing: 0) {
                    Text("\(effort)")
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Self.color(effort))
                    Text(Self.label(effort)).font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .focusable()
                .digitalCrownRotation($crown, from: 1, through: 10, by: 1, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                Button { crown = min(10, crown.rounded() + 1) } label: { Image(systemName: "plus") }
                    .frame(width: 40)
            }
            Toggle(isOn: $injured) {
                Label("Injured", systemImage: "bandage.fill").font(.caption)
            }
            .tint(.red)
            Button {
                store.send(.rateExercise, extra: [WatchKeys.effort: effort, WatchKeys.injured: injured])
            } label: {
                Text(store.isSending ? "Sending…" : "Save & next")
                    .foregroundStyle(WatchTheme.ink)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .disabled(store.isSending)
        }
    }

    static func label(_ effort: Int) -> String {
        switch effort {
        case ...3: return "Easy"
        case 4...6: return "Moderate"
        case 7...8: return "Hard"
        case 9: return "Very hard"
        default: return "Max"
        }
    }

    static func color(_ effort: Int) -> Color {
        switch effort {
        case ...3: return .green
        case 4...6: return .mint
        case 7...8: return .orange
        default: return .red
        }
    }
}

struct RestView: View {
    @EnvironmentObject private var store: WatchSessionStore
    var snapshot: WatchSnapshot
    var end: Date

    var body: some View {
        let remaining = max(end.timeIntervalSinceNow, 0)
        let total = max(Double(snapshot.restTotal), remaining, 1)
        ScrollView {
            VStack(spacing: 6) {
                WorkoutMetricsLine(startedAt: snapshot.startedAt)
                Text(snapshot.restIsBetweenExercises ? "Rest · next exercise" : "Rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: remaining / total)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timerInterval: Date()...max(end, Date()), countsDown: true)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                }
                .frame(width: 110, height: 110)
                if let next = snapshot.nextUp {
                    Text(next).font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                HStack {
                    Button("+30s") { store.send(.addRest30) }
                    Button("Skip") { store.send(.skipRest) }
                        .tint(.orange)
                }
                .disabled(store.isSending)
            }
        }
    }
}
