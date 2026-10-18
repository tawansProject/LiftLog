import SwiftUI
import SwiftData

/// Saved sessions (unlimited). Start one, edit it, or create a new one.
struct SessionListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var engine: WorkoutEngine
    @Query(sort: \SessionTemplate.updatedAt, order: .reverse) private var templates: [SessionTemplate]
    @Query private var records: [WorkoutRecord]
    @State private var builder: BuilderTarget?

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if !records.isEmpty {
                        Section {
                            StreakHeader(records: records)
                        }
                    }
                    Section("Saved sessions") {
                        if templates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No sessions yet").font(.headline)
                                Text("Create a session like \"Session A: Dumbbell bench press 30 kg, 3 × 12\". It's saved so you can repeat it any time.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button("Create session") { builder = .new }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 6)
                        }
                        ForEach(templates) { template in
                            NavigationLink(value: template.id) {
                                SessionRow(template: template)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    context.delete(template)
                                    try? context.save()
                                } label: { Label("Delete", systemImage: "trash") }
                                Button {
                                    duplicate(template)
                                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                    .tint(.indigo)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("Workouts")
            .navigationDestination(for: UUID.self) { id in
                if let template = templates.first(where: { $0.id == id }) {
                    SessionDetailView(template: template) { builder = .edit(template) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { builder = .new } label: { Label("New session", systemImage: "plus") }
                }
            }
            .fullScreenCover(item: $builder) { target in
                SessionBuilderView(template: target.template)
            }
        }
    }

    private func duplicate(_ template: SessionTemplate) {
        let copy = SessionTemplate(name: template.name + " copy", items: template.items.map { item in
            var item = item
            item.id = UUID()
            return item
        })
        context.insert(copy)
        try? context.save()
    }
}

enum BuilderTarget: Identifiable {
    case new
    case edit(SessionTemplate)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let template): return template.id.uuidString
        }
    }

    var template: SessionTemplate? {
        if case .edit(let template) = self { return template }
        return nil
    }
}

struct SessionRow: View {
    var template: SessionTemplate

    var body: some View {
        let items = template.items
        let groups = MuscleAnalysis.groupTotals(MuscleAnalysis.loads(planned: items)).prefix(4)
        VStack(alignment: .leading, spacing: 6) {
            Text(template.name).font(.headline)
            Text("\(items.count) exercises · \(items.reduce(0) { $0 + $1.sets.count }) sets")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(groups)) { entry in
                    Text(entry.group.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(entry.group.color)
                        .background(entry.group.color.opacity(0.12), in: Capsule())
                }
                Spacer()
                if let last = template.lastPerformedAt {
                    Text(last, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Overview of a saved session with its muscle map, and the Start button.
struct SessionDetailView: View {
    @EnvironmentObject private var engine: WorkoutEngine
    @Query private var records: [WorkoutRecord]
    var template: SessionTemplate
    var onEdit: () -> Void

    var body: some View {
        let items = template.items
        List {
            Group {
                Section {
                    Button {
                        engine.start(name: template.name, templateID: template.id, items: items)
                    } label: {
                        Label(engine.isActive ? "A workout is in progress" : "Start workout", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isActive || items.isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section("Muscles worked") {
                    MuscleOverview(loads: MuscleAnalysis.loads(planned: items))
                        .padding(.vertical, 6)
                }
                Section("Exercises") {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 12) {
                                ExerciseThumbnail(name: item.name, gifUrl: item.gifUrl, targetMuscles: item.targetMuscles,
                                                  secondaryMuscles: item.secondaryMuscles, exerciseId: item.exerciseId, size: 64)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(index + 1). \(item.name)").font(.headline)
                                    Text(item.setSummary).font(.caption).foregroundStyle(.secondary)
                                    MuscleChips(target: item.targetMuscles, secondary: item.secondaryMuscles, compact: true)
                                }
                            }
                            if let suggestion = HistoryService.suggestion(for: item.exerciseId, in: records) {
                                SuggestionCard(suggestion: suggestion)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(template.name)
        .toolbar {
            Button("Edit", action: onEdit)
        }
    }
}
