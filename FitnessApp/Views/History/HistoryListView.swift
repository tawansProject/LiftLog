import SwiftUI
import SwiftData

/// Every recorded session (from a plan or quick), grouped by month.
struct HistoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var records: [WorkoutRecord]

    @State private var showDashboard = true

    var body: some View {
        NavigationStack {
            Group {
                if showDashboard {
                    ScrollView {
                        HistoryDashboardView(records: records)
                            .padding()
                    }
                    .background(Theme.background.ignoresSafeArea())
                } else {
                    list
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $showDashboard) {
                        Text("Dashboard").tag(true)
                        Text("List").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
    }

    private var list: some View {
            List {
                Group {
                    if records.isEmpty {
                        ContentUnavailableView("No sessions yet", systemImage: "clock",
                                               description: Text("Finished sessions, from a plan or quick, show up here."))
                    }
                    ForEach(months, id: \.self) { month in
                        Section(month.formatted(.dateTime.month(.wide).year())) {
                            ForEach(records.filter { Calendar.current.isDate($0.startedAt, equalTo: month, toGranularity: .month) }) { record in
                                NavigationLink {
                                    WorkoutSummaryView(record: record)
                                } label: {
                                    HistoryRow(record: record)
                                }
                            }
                            .onDelete { offsets in
                                let monthRecords = records.filter { Calendar.current.isDate($0.startedAt, equalTo: month, toGranularity: .month) }
                                for index in offsets { context.delete(monthRecords[index]) }
                                try? context.save()
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
    }

    private var months: [Date] {
        let starts = records.compactMap { Calendar.current.dateInterval(of: .month, for: $0.startedAt)?.start }
        return Array(Set(starts)).sorted(by: >)
    }
}

struct HistoryRow: View {
    var record: WorkoutRecord

    var body: some View {
        let exercises = record.exercises
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.name).font(.headline)
                if record.templateID == nil {
                    Label("Quick", systemImage: "bolt.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.accentSoft, in: Capsule())
                }
                if record.finishedEarly {
                    Text("Early").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
                if exercises.contains(where: \.injured) {
                    Image(systemName: "bandage.fill").foregroundStyle(.red).font(.caption)
                }
                Spacer()
                Text(record.startedAt.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            Text(summary(exercises))
                .font(.subheadline)
                .foregroundStyle(Theme.subtext)
        }
    }

    private func summary(_ exercises: [LoggedExercise]) -> String {
        let volume = exercises.reduce(0.0) { $0 + $1.volume }
        var text = "\(Format.shortDuration(record.duration)) · \(exercises.filter(\.hasProgress).count) exercises · \(Format.volume(volume))"
        if let kcal = record.activeCalories { text += " · \(Int(kcal)) kcal" }
        return text
    }
}
