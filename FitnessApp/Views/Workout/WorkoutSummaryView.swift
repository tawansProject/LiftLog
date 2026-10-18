import SwiftUI
import SwiftData

/// Shown after finishing (and from History): time, sets, volume, calories,
/// muscles worked, personal records, and next-time suggestions.
struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var engine: WorkoutEngine
    @Query private var records: [WorkoutRecord]
    @Bindable var record: WorkoutRecord
    var isFreshlyFinished = false
    @State private var refreshing = false
    @State private var editingIndex: Int?
    @State private var savedAsPlan = false

    var body: some View {
        let exercises = record.exercises
        let done = exercises.filter { $0.hasProgress }
        let sets = exercises.reduce(0) { $0 + $1.doneSets.count }
        let volume = exercises.reduce(0.0) { $0 + $1.volume }
        let prs = HistoryService.personalRecords(in: record, allRecords: records)

        List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        if isFreshlyFinished {
                            Text(record.finishedEarly ? "Workout saved (finished early)" : "Workout complete! 🎉")
                                .font(.headline)
                        }
                        Text(record.startedAt.formatted(date: .complete, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(title: "Total time", value: Format.duration(record.duration), symbol: "timer")
                        StatTile(title: "Exercises", value: "\(done.count)/\(exercises.count)", symbol: "list.bullet")
                        StatTile(title: "Sets", value: "\(sets)", symbol: "square.stack.3d.up")
                        StatTile(title: "Volume", value: Format.volume(volume), symbol: "scalemass")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    caloriesRow
                }
    
                if !prs.isEmpty {
                    Section("Personal records") {
                        ForEach(prs) { pr in
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                Text(pr.exerciseName)
                                Spacer()
                                Text("\(Format.weight(pr.weight)) × \(pr.reps)").bold()
                                Text("was \(Format.weight(pr.previousBest))").font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
    
                if record.isQuick && record.templateID == nil {
                    Section {
                        Button {
                            PlanSaver.save(record, in: context)
                            savedAsPlan = true
                        } label: {
                            Label("Save as workout plan", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.white)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("This quick session is saved in History. Save it as a plan to repeat it later.")
                    }
                } else if savedAsPlan {
                    Section {
                        Label("Saved to Workout plans", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section("Muscles worked") {
                    let loads = MuscleAnalysis.loads(logged: exercises)
                    MuscleMapView(loads: loads)
                        .padding(.vertical, 8)
                    MuscleOverview(loads: loads)
                        .padding(.vertical, 6)
                }
    
                Section("Exercises") {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                ExerciseThumbnail(name: exercise.name, gifUrl: exercise.gifUrl, targetMuscles: exercise.targetMuscles,
                                                  secondaryMuscles: exercise.secondaryMuscles, exerciseId: exercise.exerciseId, size: 44)
                                Text(exercise.name).font(.headline)
                                Spacer()
                                if exercise.status == .skipped || !exercise.hasProgress {
                                    Text("Skipped").font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                                Button { editingIndex = index } label: {
                                    Image(systemName: "pencil.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                            if exercise.hasProgress {
                                Text(exercise.performedSummary).font(.subheadline)
                            }
                            HStack(spacing: 10) {
                                if let effort = exercise.effort {
                                    Text("Effort \(effort) · \(EffortScale.label(effort))")
                                        .foregroundStyle(EffortScale.color(effort))
                                } else if exercise.hasProgress {
                                    Text("No effort rating").foregroundStyle(Theme.secondaryText)
                                }
                                if exercise.injured {
                                    Label(exercise.injuryNote.isEmpty ? "Injured" : exercise.injuryNote, systemImage: "bandage.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(.caption)
                            if exercise.hasProgress,
                               let next = ProgressionEngine.suggest(history: nextHistory(for: exercise)) {
                                SuggestionCard(suggestion: next)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isFreshlyFinished {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        engine.finishedRecordID = nil
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: Binding(get: { editingIndex.map(EditIndex.init) }, set: { editingIndex = $0?.value })) { item in
            if record.exercises.indices.contains(item.value) {
                EffortSheet(exercise: record.exercises[item.value], isLast: true) { effort, injured, note in
                    var all = record.exercises
                    all[item.value].effort = effort
                    all[item.value].injured = injured
                    all[item.value].injuryNote = injured ? note : ""
                    record.exercises = all
                    try? context.save()
                    editingIndex = nil
                }
            }
        }
    }

    /// History for this exercise up to and including this workout, newest first.
    private func nextHistory(for exercise: LoggedExercise) -> [LoggedExercise] {
        let earlier = HistoryService.logs(for: exercise.exerciseId, in: records, before: record.startedAt)
        return Array(([exercise] + earlier).prefix(5))
    }

    @ViewBuilder
    private var caloriesRow: some View {
        HStack {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                if let kcal = record.activeCalories {
                    Text("\(Int(kcal.rounded())) kcal").font(.headline)
                    Text(record.calorieSource?.label ?? "").font(.caption).foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Calculating calories…").font(.subheadline)
                    Text("Reading heart rate from Apple Health").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                if let hr = record.averageHeartRate {
                    Text("Avg heart rate \(Int(hr)) bpm" + (record.maxHeartRate.map { " · max \(Int($0))" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Button {
                refreshing = true
                Task {
                    await engine.refreshCalories(recordID: record.id, start: record.startedAt, end: record.endedAt)
                    refreshing = false
                }
            } label: {
                if refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct EditIndex: Identifiable {
    var value: Int
    var id: Int { value }
}
