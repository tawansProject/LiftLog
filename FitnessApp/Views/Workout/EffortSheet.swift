import SwiftUI

/// Asked after each exercise: how hard was it (1-10), and was there pain or
/// injury. Both feed the progressive-overload suggestion for next time.
struct EffortSheet: View {
    var exercise: LoggedExercise
    var isLast: Bool
    var onSave: (Int?, Bool, String) -> Void

    @State private var effort: Int
    @State private var injured: Bool
    @State private var note: String

    init(exercise: LoggedExercise, isLast: Bool, onSave: @escaping (Int?, Bool, String) -> Void) {
        self.exercise = exercise
        self.isLast = isLast
        self.onSave = onSave
        _effort = State(initialValue: exercise.effort ?? 7)
        _injured = State(initialValue: exercise.injured)
        _note = State(initialValue: exercise.injuryNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Text(exercise.performedSummary).font(.subheadline)
                    } header: {
                        Text(exercise.name)
                    }
    
                    Section("Effort") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("\(effort)")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(EffortScale.color(effort))
                                VStack(alignment: .leading) {
                                    Text(EffortScale.label(effort)).font(.headline)
                                    Text(hint).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                                ForEach(1...10, id: \.self) { value in
                                    Button { effort = value } label: {
                                        Text("\(value)")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                            .foregroundStyle(value == effort ? Color.white : Color.primary)
                                            .background(value == effort ? EffortScale.color(value) : Theme.cardRaised,
                                                        in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
    
                    Section {
                        Toggle(isOn: $injured) {
                            Label("Injured / felt pain", systemImage: "bandage.fill")
                        }
                        .tint(.red)
                        if injured {
                            TextField("Where? e.g. left shoulder", text: $note)
                        }
                    } footer: {
                        Text(injured ? "Next time you'll get a lighter suggestion for this exercise."
                                     : "Effort and injury are used to suggest your next weight and reps.")
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("How did it feel?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLast ? "Save" : "Save & next") { onSave(effort, injured, note) }
                }
            }
        }
    }

    private var hint: String {
        switch effort {
        case ...3: return "Could do many more reps"
        case 4...6: return "3-5 reps left in the tank"
        case 7: return "About 3 reps left"
        case 8: return "About 2 reps left"
        case 9: return "Maybe 1 more rep"
        default: return "Nothing left, true max"
        }
    }
}
