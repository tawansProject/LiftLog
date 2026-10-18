import SwiftUI
import SwiftData

/// The workout screen: total elapsed time, the current exercise in order,
/// its sets with a Done button each, the rest timer, and Finish (early) any time.
struct LiveWorkoutView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @Query private var records: [WorkoutRecord]
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var showAddExercise = false

    var body: some View {
        NavigationStack {
            if let workout = engine.workout {
                content(workout)
                    .navigationTitle(workout.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar(workout) }
                    .safeAreaInset(edge: .bottom) {
                        if workout.isResting { RestBanner(workout: workout) }
                    }
                    .sheet(isPresented: effortSheetBinding) {
                        if let index = workout.effortPendingIndex, workout.exercises.indices.contains(index) {
                            EffortSheet(exercise: workout.exercises[index], isLast: isLastPending(index, in: workout)) { effort, injured, note in
                                engine.submitEffort(exercise: index, effort: effort, injured: injured, note: note)
                            }
                            .id(index) // fresh values when ratings chain
                            .presentationDetents([.medium, .large])
                        }
                    }
                    .sheet(isPresented: $showAddExercise) {
                        ExercisePickerFlow { plan in
                            engine.addExercise(plan)
                            showAddExercise = false
                        }
                    }
                    .confirmationDialog(finishTitle(workout), isPresented: $confirmFinish, titleVisibility: .visible) {
                        Button(workout.allDone ? "Finish workout" : "Finish early") { engine.requestFinish() }
                        Button("Discard workout", role: .destructive) { confirmDiscard = true }
                        Button("Keep going", role: .cancel) {}
                    }
                    .alert("Discard this workout?", isPresented: $confirmDiscard) {
                        Button("Discard", role: .destructive) { engine.discard() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Nothing from this workout will be saved.")
                    }
            }
        }
    }

    private var effortSheetBinding: Binding<Bool> {
        Binding(get: { engine.workout?.effortPendingIndex != nil },
                set: { shown in if !shown { engine.cancelEffort() } })
    }

    private func finishTitle(_ workout: ActiveWorkout) -> String {
        if workout.allDone {
            return workout.unratedIndex == nil ? "All exercises done" : "All exercises done. You'll rate the last one first."
        }
        return "\(workout.finishedCount) of \(workout.exercises.count) exercises done"
    }

    private func isLastPending(_ index: Int, in workout: ActiveWorkout) -> Bool {
        !workout.exercises.indices.contains { $0 != index && workout.exercises[$0].status == .pending }
    }

    @ToolbarContentBuilder
    private func toolbar(_ workout: ActiveWorkout) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { engine.isMinimized = true } label: { Image(systemName: "chevron.down") }
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(workout.name).font(.subheadline.bold()).lineLimit(1)
                Text(workout.startedAt, style: .timer)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") { confirmFinish = true }
                .bold()
        }
    }

    @ViewBuilder
    private func content(_ workout: ActiveWorkout) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ElapsedHeader(workout: workout)
                if workout.exercises.indices.contains(workout.currentIndex) {
                    CurrentExerciseCard(index: workout.currentIndex, exercise: workout.exercises[workout.currentIndex],
                                        history: HistoryService.logs(for: workout.exercises[workout.currentIndex].exerciseId, in: records))
                }
                if workout.allDone {
                    Button { engine.requestFinish() } label: {
                        Label("Finish & see summary", systemImage: "flag.checkered")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                ExerciseQueue(workout: workout)
                Button { showAddExercise = true } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct ElapsedHeader: View {
    var workout: ActiveWorkout

    var body: some View {
        let setsDone = workout.exercises.reduce(0) { $0 + $1.doneSets.count }
        let setsTotal = workout.exercises.reduce(0) { $0 + $1.sets.count }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total time").font(.caption).foregroundStyle(.secondary)
                Text(workout.startedAt, style: .timer)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Exercise \(workout.currentIndex + 1) of \(workout.exercises.count)")
                    .font(.subheadline.bold())
                Text("\(setsDone)/\(setsTotal) sets").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(setsDone), total: Double(max(setsTotal, 1)))
                    .frame(width: 110)
            }
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CurrentExerciseCard: View {
    @EnvironmentObject private var engine: WorkoutEngine
    var index: Int
    var exercise: LoggedExercise
    var history: [LoggedExercise]
    @State private var showGIF = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name).font(.title3.bold())
                    MuscleChips(target: exercise.targetMuscles, secondary: exercise.secondaryMuscles, compact: true)
                }
                Spacer()
                if exercise.gifUrl != nil {
                    Button { showGIF.toggle() } label: {
                        Image(systemName: showGIF ? "photo.fill" : "photo")
                    }
                }
            }
            if showGIF {
                ExerciseGIFView(urlString: exercise.gifUrl).frame(height: 180)
            }

            if let suggestion = ProgressionEngine.suggest(history: Array(history.prefix(5))),
               !exercise.hasProgress {
                SuggestionCard(suggestion: suggestion, lastSummary: history.first?.performedSummary) {
                    engine.apply(suggestion, toExercise: index)
                }
            }

            VStack(spacing: 8) {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                    LiveSetRow(exerciseIndex: index, setIndex: setIndex, set: set,
                               label: label(for: setIndex),
                               isNext: engine.nextSetIndex(in: exercise) == setIndex)
                }
            }

            HStack {
                Menu {
                    Button("Warm-up set") { engine.addSet(exercise: index, kind: .warmup) }
                    Button("Normal set") { engine.addSet(exercise: index, kind: .normal) }
                    Button("Drop set") { engine.addSet(exercise: index, kind: .drop) }
                } label: {
                    Label("Add set", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    engine.requestFinishExercise(index)
                } label: {
                    Label("Done with exercise", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!exercise.hasProgress)
            }
            Text("Rest \(Format.rest(exercise.restBetweenSets)) between sets, \(Format.rest(exercise.restAfterExercise)) before the next exercise")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func label(for setIndex: Int) -> String {
        let set = exercise.sets[setIndex]
        guard set.kind == .normal else { return set.kind.badge }
        let number = exercise.sets.prefix(setIndex + 1).filter { $0.kind == .normal }.count
        return "\(number)"
    }
}

struct LiveSetRow: View {
    @EnvironmentObject private var engine: WorkoutEngine
    var exerciseIndex: Int
    var setIndex: Int
    var set: LoggedSet
    var label: String
    var isNext: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.bold())
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(badgeColor, in: Circle())
                .contextMenu {
                    ForEach(SetKind.allCases) { kind in
                        Button(kind.label) { engine.updateSet(exercise: exerciseIndex, set: setIndex, kind: kind) }
                    }
                    Button("Delete set", role: .destructive) { engine.removeSet(exercise: exerciseIndex, set: setIndex) }
                }

            VStack(alignment: .leading, spacing: 0) {
                Text("Reps").font(.caption2).foregroundStyle(.secondary)
                TextField("Reps", value: Binding(get: { set.reps },
                                                 set: { engine.updateSet(exercise: exerciseIndex, set: setIndex, reps: $0) }),
                          format: .number)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("kg").font(.caption2).foregroundStyle(.secondary)
                TextField("kg", value: Binding(get: { set.weight },
                                               set: { engine.updateSet(exercise: exerciseIndex, set: setIndex, weight: $0) }),
                          format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit())
            }
            Spacer(minLength: 0)
            if set.reps != set.targetReps || set.weight != set.targetWeight {
                Text("plan \(set.targetReps)×\(Format.number(set.targetWeight))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                engine.toggleSet(exercise: exerciseIndex, set: setIndex)
            } label: {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 34))
                    .foregroundStyle(set.isDone ? Color.green : (isNext ? Color.accentColor : Color.secondary))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(isNext ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .opacity(set.isDone ? 0.7 : 1)
    }

    private var badgeColor: Color {
        switch set.kind {
        case .warmup: return .orange
        case .normal: return .accentColor
        case .drop: return .purple
        }
    }
}

/// All exercises in order. Tap one to jump to it.
struct ExerciseQueue: View {
    @EnvironmentObject private var engine: WorkoutEngine
    var workout: ActiveWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session order").font(.headline)
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                Button { engine.focus(exercise: index) } label: {
                    HStack {
                        Image(systemName: icon(exercise, index: index))
                            .foregroundStyle(color(exercise, index: index))
                        VStack(alignment: .leading) {
                            Text(exercise.name).font(.subheadline)
                            Text(detail(exercise))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if exercise.status == .pending && index != workout.currentIndex {
                            Menu {
                                Button("Skip exercise", role: .destructive) { engine.skipExercise(index) }
                            } label: { Image(systemName: "ellipsis").padding(8) }
                        }
                    }
                    .padding(10)
                    .background(index == workout.currentIndex ? Color.accentColor.opacity(0.1) : Theme.card,
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detail(_ exercise: LoggedExercise) -> String {
        var text = "\(exercise.doneSets.count)/\(exercise.sets.count) sets"
        if let effort = exercise.effort { text += " · effort \(effort)" }
        if exercise.injured { text += " · injured" }
        if exercise.status == .skipped { text += " · skipped" }
        return text
    }

    private func icon(_ exercise: LoggedExercise, index: Int) -> String {
        switch exercise.status {
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "forward.circle.fill"
        case .pending: return index == workout.currentIndex ? "play.circle.fill" : "circle"
        }
    }

    private func color(_ exercise: LoggedExercise, index: Int) -> Color {
        switch exercise.status {
        case .completed: return .green
        case .skipped: return .gray
        case .pending: return index == workout.currentIndex ? .accentColor : .secondary
        }
    }
}

/// Countdown between sets / exercises, with +30 s and Skip.
struct RestBanner: View {
    @EnvironmentObject private var engine: WorkoutEngine
    var workout: ActiveWorkout

    var body: some View {
        if let end = workout.restEndsAt {
            VStack(spacing: 8) {
                HStack {
                    Text(workout.restBetweenExercises ? "Rest before next exercise" : "Rest between sets")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(timerInterval: Date()...max(end, Date()), countsDown: true)
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                }
                ProgressView(timerInterval: end.addingTimeInterval(TimeInterval(-workout.restTotal))...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.orange)
                if let next = engine.nextUpDescription() {
                    Text(next).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("+30 s") { engine.addRest(seconds: 30) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Skip rest") { engine.skipRest() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }
}
