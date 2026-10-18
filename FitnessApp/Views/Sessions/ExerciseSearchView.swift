import SwiftUI
import SwiftData

/// Search → pick → configure, in one sheet. Calls `onAdd` with the finished plan.
struct ExercisePickerFlow: View {
    var onAdd: (PlannedExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var records: [WorkoutRecord]
    @Query private var templates: [SessionTemplate]
    @State private var path: [PickedExercise] = []

    var body: some View {
        NavigationStack(path: $path) {
            ExerciseSearchView { dto in
                cache(dto)
                let prefill = HistoryService.prefill(for: dto, records: records, templates: templates,
                                                     restBetweenSets: AppSettings.restBetweenSets,
                                                     restAfterExercise: AppSettings.restAfterExercise)
                path.append(PickedExercise(dto: dto, plan: prefill.plan, note: prefill.source.note))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(for: PickedExercise.self) { picked in
                ExerciseConfigView(plan: picked.plan, isNew: true, prefillNote: picked.note,
                                   instructions: picked.dto.instructions, onSave: onAdd)
            }
        }
    }

    private func cache(_ dto: ExerciseDTO) {
        let id = dto.exerciseId
        let descriptor = FetchDescriptor<CachedExercise>(predicate: #Predicate { $0.exerciseId == id })
        if let existing = try? context.fetch(descriptor).first {
            if !existing.isCustom { existing.update(from: dto) }
        } else {
            context.insert(CachedExercise(dto: dto))
        }
        try? context.save()
    }
}

struct PickedExercise: Hashable {
    var dto: ExerciseDTO
    var plan: PlannedExercise
    var note: String?
}

/// Searches ExerciseDB by name, optionally filtered by body part, and shows
/// each result's target muscles. Previously used and cached exercises show
/// first and work offline.
struct ExerciseSearchView: View {
    var onPick: (ExerciseDTO) -> Void

    @Query(sort: \CachedExercise.name) private var cached: [CachedExercise]
    @State private var query = ""
    @State private var bodyPart: String?
    @State private var remote: [ExerciseDTO] = []
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCustom = false

    var body: some View {
        List {
            Group {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            filterChip(nil, title: "All")
                            ForEach(ExerciseDBClient.bodyParts, id: \.self) { part in
                                filterChip(part, title: part.capitalized)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
    
                if !recent.isEmpty {
                    Section(query.isEmpty ? "Recently used" : "Saved on this phone") {
                        ForEach(recent, id: \.exerciseId) { item in
                            ExerciseResultRow(dto: item.dto) { onPick(item.dto) }
                        }
                    }
                }
    
                Section {
                    ForEach(remoteResults) { dto in
                        ExerciseResultRow(dto: dto) { onPick(dto) }
                    }
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if nextCursor != nil {
                        Button("Load more") { Task { await load(more: true) } }
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                    }
                } header: {
                    Text("Exercise Library")
                } footer: {
                    Text("Search more than 1,500 exercises with animations.")
                }
    
                Section {
                    Button { showCustom = true } label: {
                        Label("Create a custom exercise", systemImage: "square.and.pencil")
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("Add exercise")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search e.g. bench press")
        .autocorrectionDisabled()
        .task(id: "\(query)|\(bodyPart ?? "")") {
            try? await Task.sleep(nanoseconds: 350_000_000) // debounce typing
            guard !Task.isCancelled else { return }
            await load(more: false)
        }
        .sheet(isPresented: $showCustom) {
            NavigationStack {
                CustomExerciseView { dto in
                    showCustom = false
                    onPick(dto)
                }
            }
        }
    }

    private func filterChip(_ part: String?, title: String) -> some View {
        let selected = bodyPart == part
        return Button(title) { bodyPart = part }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Theme.card, in: Capsule())
            .buttonStyle(.plain)
    }

    /// Cached exercises matching the query (or recently used when empty).
    private var recent: [CachedExercise] {
        let filtered = cached.filter { item in
            (bodyPart == nil || item.bodyParts.contains(bodyPart!)) &&
                (query.isEmpty ? item.lastUsedAt != nil : SearchRanking.score(item.name, query: query) > 0)
        }
        if query.isEmpty {
            return Array(filtered.sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }.prefix(8))
        }
        return Array(filtered.sorted { SearchRanking.score($0.name, query: query) > SearchRanking.score($1.name, query: query) }.prefix(15))
    }

    private var remoteResults: [ExerciseDTO] {
        let shown = Set(recent.map(\.exerciseId))
        let unique = remote.filter { !shown.contains($0.exerciseId) }
        guard !query.isEmpty else { return unique }
        return unique.sorted { SearchRanking.score($0.name, query: query) > SearchRanking.score($1.name, query: query) }
    }

    private func load(more: Bool) async {
        if !more {
            remote = []
            nextCursor = nil
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await ExerciseDBClient.shared.search(name: query, bodyPart: bodyPart, cursor: more ? nextCursor : nil)
            let existing = Set(remote.map(\.exerciseId))
            remote += page.data.filter { !existing.contains($0.exerciseId) }
            nextCursor = (page.meta?.hasNextPage ?? false) ? page.meta?.nextCursor : nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = "Couldn't reach the Exercise Library. Showing exercises saved on this phone."
        }
    }
}

enum SearchRanking {
    /// Higher is better; 0 means not a match. Every word of the query must appear.
    static func score(_ name: String, query: String) -> Int {
        let name = name.lowercased()
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 1 }
        let words = q.split(separator: " ").map(String.init)
        guard words.allSatisfy({ name.contains($0) }) else { return 0 }
        var score = 10
        if name == q { score += 100 }
        if name.hasPrefix(q) { score += 40 }
        if name.contains(q) { score += 30 }
        score -= name.count / 4 // shorter names first
        return max(score, 1)
    }
}

struct ExerciseResultRow: View {
    var dto: ExerciseDTO
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ExerciseGIFView(urlString: dto.gifUrl, exerciseId: dto.exerciseId)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(dto.displayName).font(.subheadline.bold())
                    MuscleChips(target: dto.targetMuscles, secondary: dto.secondaryMuscles, compact: true)
                    if !dto.equipments.isEmpty {
                        Text(dto.equipments.joined(separator: ", ").capitalized)
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// For exercises missing from ExerciseDB, or when offline.
struct CustomExerciseView: View {
    var onCreate: (ExerciseDTO) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var target: Set<String> = []
    @State private var secondary: Set<String> = []
    @State private var equipment = "dumbbell"

    static let muscles = ["pectorals", "latissimus dorsi", "upper back", "trapezius", "rhomboids", "erector spinae",
                          "deltoids", "rear deltoids", "biceps", "triceps", "forearms", "abdominals", "obliques",
                          "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]
    static let equipments = ["dumbbell", "barbell", "cable", "leverage machine", "smith machine", "kettlebell", "band", "body weight"]

    var body: some View {
        Form {
            Group {
                TextField("Exercise name", text: $name)
                Picker("Equipment", selection: $equipment) {
                    ForEach(Self.equipments, id: \.self) { Text($0.capitalized).tag($0) }
                }
                Section("Target muscles") {
                    musclePicker(selection: $target)
                }
                Section("Secondary muscles (optional)") {
                    musclePicker(selection: $secondary)
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("Custom exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { create() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || target.isEmpty)
            }
        }
    }

    private func musclePicker(selection: Binding<Set<String>>) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Self.muscles, id: \.self) { muscle in
                let on = selection.wrappedValue.contains(muscle)
                Button(muscle.capitalized) {
                    if on { selection.wrappedValue.remove(muscle) } else { selection.wrappedValue.insert(muscle) }
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? MuscleGroup.group(forMuscle: muscle).color : Theme.card, in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func create() {
        let dto = ExerciseDTO(exerciseId: "custom-\(UUID().uuidString)", name: name.trimmingCharacters(in: .whitespaces),
                              gifUrl: nil, bodyParts: Self.bodyParts(for: Array(target) + Array(secondary)), equipments: [equipment],
                              targetMuscles: Array(target).sorted(), secondaryMuscles: Array(secondary).sorted(),
                              instructions: [])
        context.insert(CachedExercise(dto: dto, isCustom: true))
        try? context.save()
        onCreate(dto)
    }

    /// ExerciseDB body-part names for the chosen muscles, so the body-part
    /// filter chips also find custom exercises.
    static func bodyParts(for muscles: [String]) -> [String] {
        var parts: [String] = []
        for muscle in muscles {
            let part: String
            switch muscle {
            case "forearms": part = "lower arms"
            case "biceps", "triceps": part = "upper arms"
            case "calves": part = "lower legs"
            default:
                switch MuscleGroup.group(forMuscle: muscle) {
                case .chest: part = "chest"
                case .back: part = "back"
                case .shoulders: part = "shoulders"
                case .arms: part = "upper arms"
                case .core: part = "waist"
                case .legs: part = "upper legs"
                case .cardio: part = "cardio"
                case .other: continue
                }
            }
            if !parts.contains(part) { parts.append(part) }
        }
        return parts
    }
}
