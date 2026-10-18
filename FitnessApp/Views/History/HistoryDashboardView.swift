import SwiftUI
import SwiftData
import Charts

/// Report-style dashboard: line graphs of volume, time, calories and effort
/// over time, plus strength progress for one exercise.
struct HistoryDashboardView: View {
    var records: [WorkoutRecord]
    @State private var range: DashboardRange = .threeMonths
    @State private var exerciseId: String?

    var body: some View {
        let inRange = records.filter { $0.startedAt >= range.startDate }
        let buckets = DashboardData.buckets(for: inRange, range: range)
        let exercises = DashboardData.exerciseOptions(records)
        let selected = exerciseId ?? exercises.first?.id

        VStack(spacing: 14) {
            Picker("Range", selection: $range) {
                ForEach(DashboardRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "Workouts", value: "\(inRange.count)", symbol: "dumbbell.fill")
                StatTile(title: "Total time", value: Format.shortDuration(inRange.reduce(0.0) { $0 + $1.duration }), symbol: "timer")
                StatTile(title: "Volume", value: Format.volume(buckets.reduce(0.0) { $0 + $1.volume }),
                         symbol: "scalemass", tint: .purple)
                StatTile(title: "Calories", value: "\(Int(buckets.reduce(0.0) { $0 + $1.calories })) kcal",
                         symbol: "flame.fill", tint: .orange)
            }

            if inRange.isEmpty {
                Text("No workouts in this range yet. Finish a workout to start your graphs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            } else {
                LineCard(title: "Volume lifted", unit: "kg", color: Theme.accent, unitLabel: range.bucketLabel,
                         points: buckets.map { ChartPoint(date: $0.start, value: $0.volume) })
                LineCard(title: "Training time", unit: "min", color: .teal, unitLabel: range.bucketLabel,
                         points: buckets.map { ChartPoint(date: $0.start, value: $0.minutes) })
                LineCard(title: "Calories burned", unit: "kcal", color: .orange, unitLabel: range.bucketLabel,
                         points: buckets.map { ChartPoint(date: $0.start, value: $0.calories) })
                LineCard(title: "Average effort", unit: "/10", color: .pink, unitLabel: range.bucketLabel,
                         points: buckets.compactMap { b in b.effort.map { ChartPoint(date: b.start, value: $0) } },
                         yDomain: 0...10)
            }

            if !exercises.isEmpty, let selected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Strength progress").font(.headline)
                        Spacer()
                        Picker("Exercise", selection: Binding(get: { selected }, set: { exerciseId = $0 })) {
                            ForEach(exercises) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                    }
                    let progress = DashboardData.strength(for: selected, in: records, since: range.startDate)
                    if progress.isEmpty {
                        Text("Not done in this range.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(progress) { point in
                                LineMark(x: .value("Date", point.date), y: .value("kg", point.topWeight),
                                         series: .value("Series", "Top weight"))
                                    .foregroundStyle(by: .value("Series", "Top weight"))
                                PointMark(x: .value("Date", point.date), y: .value("kg", point.topWeight))
                                    .foregroundStyle(by: .value("Series", "Top weight"))
                                LineMark(x: .value("Date", point.date), y: .value("kg", point.oneRepMax),
                                         series: .value("Series", "Est. 1RM"))
                                    .foregroundStyle(by: .value("Series", "Est. 1RM"))
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                if point.injured {
                                    PointMark(x: .value("Date", point.date), y: .value("kg", point.topWeight))
                                        .symbol(.cross)
                                        .symbolSize(120)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .chartForegroundStyleScale(["Top weight": Theme.accent, "Est. 1RM": Color.green])
                        .frame(height: 200)
                        if let first = progress.first, let last = progress.last, progress.count > 1 {
                            let change = last.topWeight - first.topWeight
                            Text("\(change >= 0 ? "▲" : "▼") \(Format.weight(abs(change))) since \(first.date.formatted(.dateTime.day().month(.abbreviated))) · red ✕ = injured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

enum DashboardRange: String, CaseIterable, Identifiable {
    case month, threeMonths, sixMonths, year
    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        }
    }

    /// Short ranges are drawn per day, longer ones per week.
    var bucket: Calendar.Component { self == .month ? .day : .weekOfYear }
    var bucketLabel: String { self == .month ? "per day" : "per week" }

    var startDate: Date {
        let months: Int
        switch self {
        case .month: months = 1
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .year: months = 12
        }
        return StatsCalculator.calendar.date(byAdding: .month, value: -months, to: Date()) ?? .distantPast
    }
}

struct ChartPoint: Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// One line graph card in the dashboard.
struct LineCard: View {
    var title: String
    var unit: String
    var color: Color
    var unitLabel: String
    var points: [ChartPoint]
    var yDomain: ClosedRange<Double>? = nil

    var body: some View {
        let latest = points.last(where: { $0.value > 0 })?.value
        let average = points.isEmpty ? 0 : points.reduce(0.0) { $0 + $1.value } / Double(points.count)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let latest {
                    Text("\(Format.number((latest * 10).rounded() / 10)) \(unit)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(color)
                }
            }
            Text("\(unitLabel) · avg \(Format.number((average * 10).rounded() / 10)) \(unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
            chart
                .frame(height: 150)
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var chart: some View {
        let base = Chart(points) { point in
            AreaMark(x: .value("Date", point.date), y: .value(unit, point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Date", point.date), y: .value(unit, point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            if point.value > 0 {
                PointMark(x: .value("Date", point.date), y: .value(unit, point.value))
                    .foregroundStyle(color)
                    .symbolSize(24)
            }
        }
        if let yDomain {
            base.chartYScale(domain: yDomain)
        } else {
            base
        }
    }
}

struct StrengthPoint: Identifiable {
    var date: Date
    var topWeight: Double
    var oneRepMax: Double
    var injured: Bool
    var id: Date { date }
}

struct ExerciseOption: Identifiable, Hashable {
    var id: String
    var name: String
}

struct DashboardBucket {
    var start: Date
    var volume: Double = 0
    var minutes: Double = 0
    var calories: Double = 0
    var effort: Double?
}

enum DashboardData {
    /// Zero-filled buckets (days or weeks) from the range start to today.
    static func buckets(for records: [WorkoutRecord], range: DashboardRange) -> [DashboardBucket] {
        let cal = StatsCalculator.calendar
        guard var cursor = cal.dateInterval(of: range.bucket, for: range.startDate)?.start else { return [] }
        var result: [DashboardBucket] = []
        let now = Date()
        while cursor <= now {
            guard let next = cal.date(byAdding: range.bucket, value: 1, to: cursor) else { break }
            let inBucket = records.filter { $0.startedAt >= cursor && $0.startedAt < next }
            var bucket = DashboardBucket(start: cursor)
            let logs = inBucket.flatMap(\.exercises)
            bucket.volume = logs.reduce(0.0) { $0 + $1.volume }
            bucket.minutes = inBucket.reduce(0.0) { $0 + $1.duration } / 60
            bucket.calories = inBucket.reduce(0.0) { $0 + ($1.activeCalories ?? 0) }
            let efforts = logs.compactMap(\.effort)
            if !efforts.isEmpty { bucket.effort = Double(efforts.reduce(0, +)) / Double(efforts.count) }
            result.append(bucket)
            cursor = next
        }
        return result
    }

    /// Exercises done at least once, most frequent first.
    static func exerciseOptions(_ records: [WorkoutRecord]) -> [ExerciseOption] {
        var counts: [String: (name: String, count: Int)] = [:]
        for record in records {
            for log in record.exercises where log.hasProgress {
                counts[log.exerciseId] = (log.name, (counts[log.exerciseId]?.count ?? 0) + 1)
            }
        }
        return counts.sorted { $0.value.count > $1.value.count }.map { ExerciseOption(id: $0.key, name: $0.value.name) }
    }

    static func strength(for exerciseId: String, in records: [WorkoutRecord], since: Date) -> [StrengthPoint] {
        records
            .filter { $0.startedAt >= since }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { record in
                guard let log = record.exercises.first(where: { $0.exerciseId == exerciseId && $0.hasProgress }),
                      let top = log.topSet else { return nil }
                let best1RM = log.doneWorkingSets.map { HistoryService.estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0
                return StrengthPoint(date: record.startedAt, topWeight: top.weight, oneRepMax: (best1RM * 10).rounded() / 10,
                                     injured: log.injured)
            }
    }
}
