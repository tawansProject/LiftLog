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
    @State private var askPlanName = false
    @State private var planName = ""
    @State private var savedPlanName: String?

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
                            .foregroundStyle(Theme.subtext)
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

                if record.templateID == nil || savedPlanName != nil {
                    Section {
                        if let savedPlanName {
                            Label("Saved as workout plan \"\(savedPlanName)\"", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                planName = record.name == "Quick session" ? "" : record.name
                                askPlanName = true
                            } label: {
                                Label("Save as workout plan", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.white)
                            .disabled(!exercises.contains(where: \.hasProgress))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    } footer: {
                        if savedPlanName == nil {
                            Text("Quick session. Save it as a plan to repeat and edit it later, starting from what you lifted today.")
                        }
                    }
                }
    
                if !prs.isEmpty {
                    Section("Personal records") {
                        ForEach(prs) { pr in
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                Text(pr.exerciseName)
                                Spacer()
                                Text("\(Format.weight(pr.weight)) × \(pr.reps)").bold()
                                Text("was \(Format.weight(pr.previousBest))").font(.caption).foregroundStyle(Theme.subtext)
                            }
                        }
                    }
                }
    
                Section("Muscles worked") {
                    BodyMapView(loads: MuscleAnalysis.loads(logged: exercises), height: 210)
                        .padding(.vertical, 8)
                    MuscleOverview(loads: MuscleAnalysis.loads(logged: exercises))
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
                                    Text("Skipped").font(.caption).foregroundStyle(Theme.subtext)
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
                                    Text("No effort rating").foregroundStyle(Theme.subtext)
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
        .alert("Save as workout plan", isPresented: $askPlanName) {
            TextField("Plan name", text: $planName)
            Button("Save") { saveAsPlan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The exercises, sets and weights from this session become a reusable plan.")
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

    /// Turns this quick session into a reusable plan and links the record to it.
    private func saveAsPlan() {
        let trimmed = planName.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? "Plan \(record.startedAt.formatted(date: .abbreviated, time: .omitted))" : trimmed
        let items = record.exercises.filter(\.hasProgress).map { log in
            var plan = log.asPlanned()
            plan.id = UUID()
            return plan
        }
        guard !items.isEmpty else { return }
        let template = SessionTemplate(name: name, items: items)
        template.lastPerformedAt = record.startedAt
        context.insert(template)
        record.templateID = template.id
        try? context.save()
        savedPlanName = name
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
                    Text(record.calorieSource?.label ?? "").font(.caption).foregroundStyle(Theme.subtext)
                } else {
                    Text("Calculating calories…").font(.subheadline)
                    Text("Reading heart rate from Apple Health").font(.caption).foregroundStyle(Theme.subtext)
                }
                if let hr = record.averageHeartRate {
                    Text("Avg heart rate \(Int(hr)) bpm" + (record.maxHeartRate.map { " · max \(Int($0))" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
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
