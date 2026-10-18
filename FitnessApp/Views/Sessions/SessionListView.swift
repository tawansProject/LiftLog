import SwiftUI
import SwiftData

/// Workouts tab: start a quick session, or create, edit and start workout
/// plans (unlimited). Recent sessions from both are listed underneath.
struct SessionListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var engine: WorkoutEngine
    @Query(sort: \SessionTemplate.updatedAt, order: .reverse) private var templates: [SessionTemplate]
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var records: [WorkoutRecord]
    @State private var builder: BuilderTarget?
    @State private var savedPlanName: String?

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
                        StartChoiceCards(disabled: engine.isActive,
                                         onQuick: { builder = .quick },
                                         onPlan: { builder = .new })
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } footer: {
                        if engine.isActive { Text("A workout is in progress. Finish it before starting another.") }
                    }
                    Section {
                        if templates.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No workout plans yet").font(.headline)
                                Text("A plan is a reusable list like \"Plan A: Dumbbell bench press 30 kg, 3 × 12\". Start it any time; each run is saved as a session in History.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
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
                    }
                    if !records.isEmpty {
                        Section {
                            ForEach(records.prefix(5)) { record in
                                NavigationLink {
                                    WorkoutSummaryView(record: record)
                                } label: {
                                    RecentSessionRow(record: record)
                                }
                                .swipeActions {
                                    if record.isQuick && record.templateID == nil {
                                        Button {
                                            savedPlanName = PlanSaver.save(record, in: context).name
                                        } label: { Label("Save as plan", systemImage: "square.and.arrow.down") }
                                            .tint(.indigo)
                                    }
                                }
                            }
                        } header: {
                            Text("Recent sessions")
                        } footer: {
                            Text("Quick sessions can be saved as a workout plan: swipe left, or open one and tap Save as plan.")
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
                    Menu {
                        Button { builder = .quick } label: { Label("Quick session", systemImage: "bolt.fill") }
                        Button { builder = .new } label: { Label("New workout plan", systemImage: "list.bullet.clipboard") }
                    } label: { Label("New", systemImage: "plus") }
                }
            }
            .fullScreenCover(item: $builder) { target in
                SessionBuilderView(template: target.template, isQuick: target.isQuick)
            }
            .alert("Saved as a workout plan", isPresented: Binding(get: { savedPlanName != nil },
                                                                   set: { if !$0 { savedPlanName = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\"\(savedPlanName ?? "")\" is now in Workout plans.")
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
    case quick
    case edit(SessionTemplate)

    var id: String {
        switch self {
        case .new: return "new"
        case .quick: return "quick"
        case .edit(let template): return template.id.uuidString
        }
    }

    var isQuick: Bool {
        if case .quick = self { return true }
        return false
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
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 6) {
                ForEach(Array(groups)) { entry in
                    Text(entry.group.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(entry.group.color)
                        .background(entry.group.color.opacity(0.25), in: Capsule())
                }
                Spacer()
                if let last = template.lastPerformedAt {
                    Text(last, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
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
                        Label(engine.isActive ? "A workout is in progress" : "Start workout", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.white)
                    .disabled(engine.isActive || items.isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section("Muscles worked") {
                    let loads = MuscleAnalysis.loads(planned: items)
                    MuscleMapView(loads: loads)
                        .padding(.vertical, 8)
                    MuscleOverview(loads: loads)
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
                                    Text(item.setSummary).font(.caption).foregroundStyle(Theme.secondaryText)
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

/// The two ways to work out: a quick session that starts right away, or a
/// reusable workout plan.
struct StartChoiceCards: View {
    var disabled: Bool
    var onQuick: () -> Void
    var onPlan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onQuick) {
                card(title: "Quick session", detail: "Pick exercises and start now", symbol: "bolt.fill",
                     foreground: Theme.onHighlight, background: Theme.highlight)
            }
            Button(action: onPlan) {
                card(title: "Workout plan", detail: "Build a reusable plan", symbol: "list.bullet.clipboard",
                     foreground: .white, background: Theme.cardRaised)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func card(title: String, detail: String, symbol: String, foreground: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.headline)
            Text(detail).font(.caption).opacity(0.8)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(14)
        .background(background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.outline, lineWidth: 1))
    }
}

struct RecentSessionRow: View {
    var record: WorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.name).font(.headline).lineLimit(1)
                Text(record.isQuick ? "Quick" : "Plan")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(record.isQuick ? Theme.onHighlight : .white)
                    .background(record.isQuick ? Theme.highlight : Theme.accent.opacity(0.5), in: Capsule())
                Spacer()
                Text(record.startedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            let exercises = record.exercises.filter(\.hasProgress)
            Text("\(Format.shortDuration(record.duration)) · \(exercises.count) exercises")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 2)
    }
}

/// Turns a recorded quick session into a reusable workout plan, using what
/// was actually lifted.
@MainActor
enum PlanSaver {
    @discardableResult
    static func save(_ record: WorkoutRecord, in context: ModelContext) -> SessionTemplate {
        let items = record.exercises.filter { $0.hasProgress || $0.status != .skipped }.map { log -> PlannedExercise in
            var plan = log.asPlanned()
            plan.id = UUID()
            return plan
        }
        let plan = SessionTemplate(name: record.name, items: items)
        plan.lastPerformedAt = record.startedAt
        context.insert(plan)
        if record.templateID == nil { record.templateID = plan.id }
        try? context.save()
        return plan
    }
}
