import SwiftUI
import SwiftData

/// Create or edit a session: name it, search and add exercises, adjust sets,
/// reps, weight and rest, then review the muscle overview and confirm.
struct SessionBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var engine: WorkoutEngine

    var template: SessionTemplate?

    @State private var name: String
    @State private var items: [PlannedExercise]
    @State private var showSearch = false
    @State private var editing: PlannedExercise?
    @State private var showReview = false

    init(template: SessionTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _items = State(initialValue: template?.items ?? [])
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section("Name") {
                        TextField("e.g. Session A: Push", text: $name)
                    }
                    Section {
                        ForEach(items) { item in
                            BuilderRow(item: item) { editing = item }
                        }
                        .onDelete { items.remove(atOffsets: $0) }
                        .onMove { items.move(fromOffsets: $0, toOffset: $1) }
    
                        Button {
                            showSearch = true
                        } label: {
                            Label("Add exercise", systemImage: "magnifyingglass")
                        }
                    } header: {
                        HStack {
                            Text("Exercises (in order)")
                            Spacer()
                            if items.count > 1 { EditButton().font(.caption) }
                        }
                    } footer: {
                        if !items.isEmpty { Text("Tap an exercise to edit sets and rest. Use Edit to reorder.") }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(template == nil ? "New session" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") { showReview = true }
                        .disabled(items.isEmpty)
                }
            }
            .navigationDestination(isPresented: $showReview) {
                ReviewSessionView(name: displayName, items: items,
                                  onSave: { save(start: false) },
                                  onStart: { save(start: true) })
            }
            .sheet(isPresented: $showSearch) {
                ExercisePickerFlow { plan in
                    items.append(plan)
                    showSearch = false
                }
            }
            .sheet(item: $editing) { item in
                NavigationStack {
                    ExerciseConfigView(plan: item, isNew: false) { updated in
                        if let index = items.firstIndex(where: { $0.id == updated.id }) { items[index] = updated }
                        editing = nil
                    }
                }
            }
        }
    }

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Session \(Date().formatted(date: .abbreviated, time: .omitted))" : trimmed
    }

    private func save(start: Bool) {
        let saved: SessionTemplate
        if let template {
            template.name = displayName
            template.items = items
            saved = template
        } else {
            saved = SessionTemplate(name: displayName, items: items)
            context.insert(saved)
        }
        for item in items { markUsed(item) }
        try? context.save()
        dismiss()
        if start && !engine.isActive {
            // Start once this full-screen builder has closed; SwiftUI can't
            // present the workout screen while the builder is still on screen.
            let workoutEngine = engine
            let name = saved.name, id = saved.id, plans = items
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                workoutEngine.start(name: name, templateID: id, items: plans)
            }
        }
    }

    private func markUsed(_ item: PlannedExercise) {
        let id = item.exerciseId
        let descriptor = FetchDescriptor<CachedExercise>(predicate: #Predicate { $0.exerciseId == id })
        if let cached = try? context.fetch(descriptor).first {
            cached.lastUsedAt = .now
        }
    }
}

struct BuilderRow: View {
    var item: PlannedExercise
    var onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The thumbnail opens its own preview; the rest of the row edits.
            ExerciseThumbnail(name: item.name, gifUrl: item.gifUrl, targetMuscles: item.targetMuscles,
                              secondaryMuscles: item.secondaryMuscles, exerciseId: item.exerciseId)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name).font(.headline)
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                }
                Text(item.setSummary).font(.subheadline)
                Text("Rest \(Format.rest(item.restBetweenSets)) between sets · \(Format.rest(item.restAfterExercise)) after")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MuscleChips(target: item.targetMuscles, compact: true)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
        }
        .padding(.vertical, 4)
    }
}

/// Confirmation page: overall muscle target of the session, then confirm.
struct ReviewSessionView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    var name: String
    var items: [PlannedExercise]
    var onSave: () -> Void
    var onStart: () -> Void

    var body: some View {
        List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.title2.bold())
                        Text("\(items.count) exercises · \(totalSets) sets · about \(restMinutes) min of rest")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Muscles you'll hit") {
                    MuscleOverview(loads: MuscleAnalysis.loads(planned: items))
                        .padding(.vertical, 6)
                }
                Section("Order") {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.headline.monospacedDigit()).frame(width: 24)
                            ExerciseThumbnail(name: item.name, gifUrl: item.gifUrl, targetMuscles: item.targetMuscles,
                                              secondaryMuscles: item.secondaryMuscles, exerciseId: item.exerciseId, size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                Text(item.setSummary).font(.caption).foregroundStyle(.secondary)
                                MuscleChips(target: item.targetMuscles, compact: true)
                            }
                        }
                    }
                }
                Section {
                    Button(action: onStart) {
                        Label("Confirm & start", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isActive)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
    
                    Button(action: onSave) {
                        Text("Save for later").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                } footer: {
                    if engine.isActive { Text("Finish your current workout before starting another.") }
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("Confirm session")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var totalSets: Int { items.reduce(0) { $0 + $1.sets.count } }

    private var restMinutes: Int {
        let seconds = items.reduce(0) { total, item in
            total + item.restBetweenSets * max(item.sets.count - 1, 0) + item.restAfterExercise
        }
        return seconds / 60
    }
}
