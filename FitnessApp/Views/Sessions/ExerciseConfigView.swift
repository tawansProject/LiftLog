import SwiftUI
import SwiftData

/// Shows the exercise's target muscles and lets the user adjust sets
/// (warm-up / normal / drop), reps, weight and rest times.
struct ExerciseConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [WorkoutRecord]

    @State private var plan: PlannedExercise
    var isNew: Bool
    var prefillNote: String?
    var instructions: [String]
    var onSave: (PlannedExercise) -> Void

    init(plan: PlannedExercise, isNew: Bool, prefillNote: String? = nil, instructions: [String] = [],
         onSave: @escaping (PlannedExercise) -> Void) {
        _plan = State(initialValue: plan)
        self.isNew = isNew
        self.prefillNote = prefillNote
        self.instructions = instructions
        self.onSave = onSave
    }

    var body: some View {
        let history = HistoryService.logs(for: plan.exerciseId, in: records)
        Form {
            Group {
                Section {
                    if plan.gifUrl != nil {
                        ExerciseGIFView(urlString: plan.gifUrl, exerciseId: plan.exerciseId)
                            .frame(height: 200)
                            .listRowInsets(EdgeInsets())
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target muscles").font(.caption).foregroundStyle(Theme.secondaryText)
                        MuscleChips(target: plan.targetMuscles, secondary: plan.secondaryMuscles)
                        if !plan.equipments.isEmpty {
                            Text("Equipment: \(plan.equipments.joined(separator: ", ").capitalized)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 4)
                    if !instructions.isEmpty {
                        DisclosureGroup("How to do it") {
                            ForEach(Array(instructions.enumerated()), id: \.offset) { _, step in
                                Text(step).font(.caption)
                            }
                        }
                    }
                }
    
                if let last = history.first {
                    Section("Previous record") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(last.performedSummary).font(.subheadline)
                            HStack(spacing: 8) {
                                if let effort = last.effort {
                                    Text("Effort \(effort) · \(EffortScale.label(effort))")
                                        .foregroundStyle(EffortScale.color(effort))
                                }
                                if last.injured {
                                    Label("Injured", systemImage: "bandage.fill").foregroundStyle(.red)
                                }
                            }
                            .font(.caption)
                            if let suggestion = ProgressionEngine.suggest(history: Array(history.prefix(5))) {
                                SuggestionCard(suggestion: suggestion, applyTitle: "Use") {
                                    plan = ProgressionEngine.apply(suggestion, to: plan)
                                }
                            }
                        }
                    }
                }
    
                Section {
                    ForEach($plan.sets) { $set in
                        SetEditorRow(set: $set, label: label(for: set))
                    }
                    .onDelete { offsets in
                        if plan.sets.count - offsets.count >= 1 { plan.sets.remove(atOffsets: offsets) }
                    }
                    HStack {
                        addButton("Warm-up", kind: .warmup)
                        addButton("Set", kind: .normal)
                        addButton("Drop set", kind: .drop)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } header: {
                    Text("Sets")
                } footer: {
                    if let prefillNote { Text(prefillNote + ". Swipe a set to delete it.") }
                    else { Text("Weight in kg. Use 0 for bodyweight. Swipe a set to delete it.") }
                }
    
                Section("Rest timer") {
                    Stepper(value: $plan.restBetweenSets, in: 0...600, step: 15) {
                        LabeledContent("Between sets", value: Format.rest(plan.restBetweenSets))
                    }
                    Stepper(value: $plan.restAfterExercise, in: 0...900, step: 15) {
                        LabeledContent("Before next exercise", value: Format.rest(plan.restAfterExercise))
                    }
                }
    
                Section("Notes") {
                    TextField("Seat height, grip, cues…", text: $plan.notes, axis: .vertical)
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Done") { onSave(plan) }
                    .disabled(plan.sets.isEmpty)
            }
            if !isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func label(for set: PlannedSet) -> String {
        guard set.kind == .normal else { return set.kind.badge }
        let index = plan.sets.filter { $0.kind == .normal }.firstIndex { $0.id == set.id } ?? 0
        return "\(index + 1)"
    }

    private func addButton(_ title: String, kind: SetKind) -> some View {
        Button {
            let reference = plan.sets.last(where: { $0.kind == kind }) ?? plan.sets.last(where: { $0.kind == .normal }) ?? plan.sets.last
            var new = PlannedSet(kind: kind, reps: reference?.reps ?? 10, weight: reference?.weight ?? 0)
            switch kind {
            case .warmup:
                if reference?.kind != .warmup {
                    new.weight = ProgressionEngine.round((reference?.weight ?? 0) * 0.5, to: ProgressionEngine.increment(for: plan.equipments))
                }
                let index = plan.sets.firstIndex { $0.kind != .warmup } ?? plan.sets.count
                plan.sets.insert(new, at: index)
            case .normal:
                let index = plan.sets.lastIndex { $0.kind == .normal }.map { $0 + 1 } ?? plan.sets.count
                plan.sets.insert(new, at: index)
            case .drop:
                if reference?.kind != .drop {
                    new.weight = ProgressionEngine.round((reference?.weight ?? 0) * 0.8, to: ProgressionEngine.increment(for: plan.equipments))
                }
                plan.sets.append(new)
            }
        } label: {
            Text("+ \(title)").font(.caption)
        }
    }
}

struct SetEditorRow: View {
    @Binding var set: PlannedSet
    var label: String

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Type", selection: $set.kind) {
                    ForEach(SetKind.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Text(label)
                    .font(.subheadline.bold())
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.white)
                    .background(color, in: Circle())
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Reps").font(.caption2).foregroundStyle(Theme.secondaryText)
                TextField("Reps", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .font(.body.monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Weight (kg)").font(.caption2).foregroundStyle(Theme.secondaryText)
                TextField("kg", value: $set.weight, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .font(.body.monospacedDigit())
            }
            Spacer(minLength: 0)
            Text(set.kind.label).font(.caption2).foregroundStyle(Theme.secondaryText)
        }
    }

    private var color: Color {
        switch set.kind {
        case .warmup: return .orange
        case .normal: return .accentColor
        case .drop: return .purple
        }
    }
}
