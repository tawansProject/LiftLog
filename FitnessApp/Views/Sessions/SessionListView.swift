import SwiftUI
import SwiftData

/// Workouts tab. Two ways to train:
/// - Quick session: starts immediately, exercises are added on the go, and it's
///   saved as a session when finished.
/// - Workout plans: reusable, editable templates (unlimited). Starting one
///   records a session from it.
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
                    Section {
                        StartOptionsRow(isActive: engine.isActive,
                                        onQuick: { engine.startQuick() },
                                        onNewPlan: { builder = .new })
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } footer: {
                        if engine.isActive { Text("A workout is in progress. Finish it before starting another.") }
                    }
                    Section {
                        if templates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No workout plans yet").font(.headline)
                                Text("A plan is a reusable template, like \"Push day: Dumbbell bench press 30 kg, 3 × 12\". Start it any time; each run is recorded as a session.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.subtext)
                                Button("Create workout plan") { builder = .new }
                                    .buttonStyle(.white)
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
                    } header: {
                        Text("Workout plans")
                    } footer: {
                        if !templates.isEmpty { Text("Plans are templates you can edit and reuse. Every time you start one, it's recorded under Sessions.") }
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
                    Button { builder = .new } label: { Label("New workout plan", systemImage: "plus") }
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

/// The two ways to start: a quick session now, or a new reusable plan.
struct StartOptionsRow: View {
    var isActive: Bool
    var onQuick: () -> Void
    var onNewPlan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onQuick) {
                card(symbol: "bolt.fill", title: "Quick session", detail: "Start now, add exercises as you go",
                     foreground: Theme.onHighlight, background: Theme.highlight)
            }
            .disabled(isActive)
            .opacity(isActive ? 0.5 : 1)
            Button(action: onNewPlan) {
                card(symbol: "list.bullet.clipboard", title: "Workout plan", detail: "Build a reusable template",
                     foreground: .white, background: Theme.cardRaised)
            }
        }
        .buttonStyle(.plain)
    }

    private func card(symbol: String, title: String, detail: String, foreground: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.headline)
            Text(detail).font(.caption).opacity(0.75).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .background(background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.outline, lineWidth: 1))
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
                .foregroundStyle(Theme.subtext)
            HStack(spacing: 6) {
                ForEach(Array(groups)) { entry in
                    Text(entry.group.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(entry.group.color)
                        .background(entry.group.color.opacity(0.24), in: Capsule())
                }
                Spacer()
                if let last = template.lastPerformedAt {
                    Text(last, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Overview of a workout plan with its muscle map, and the Start button.
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
                        Label(engine.isActive ? "A workout is in progress" : "Start session", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.white)
                    .disabled(engine.isActive || items.isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section("Muscles you'll hit") {
                    BodyMapView(loads: MuscleAnalysis.loads(planned: items))
                        .padding(.vertical, 8)
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
                                    Text(item.setSummary).font(.caption).foregroundStyle(Theme.subtext)
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
