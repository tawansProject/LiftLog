import Foundation

enum SummaryPeriod: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var label: String { self == .week ? "Week" : "Month" }
    var component: Calendar.Component { self == .week ? .weekOfYear : .month }
}

struct PeriodStats {
    var interval: DateInterval
    var workouts: Int = 0
    var duration: TimeInterval = 0
    var sets: Int = 0
    var volume: Double = 0
    var calories: Double = 0
    var activeDays: Int = 0
    var injuries: Int = 0
    var averageEffort: Double?
    var muscleLoads: [MuscleLoad] = []
    var dailyVolume: [DayVolume] = []
    var topExercises: [ExerciseCount] = []
    var personalRecords: [HistoryService.PersonalRecord] = []
}

struct DayVolume: Identifiable {
    var day: Date
    var volume: Double
    var id: Date { day }
}

struct ExerciseCount: Identifiable {
    var name: String
    var sets: Int
    var id: String { name }
}

/// Weekly / monthly summaries and streaks.
enum StatsCalculator {
    static var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // weeks start on Monday
        return cal
    }

    static func interval(for period: SummaryPeriod, containing date: Date) -> DateInterval {
        calendar.dateInterval(of: period.component, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    static func stats(for period: SummaryPeriod, containing date: Date, records: [WorkoutRecord]) -> PeriodStats {
        let range = interval(for: period, containing: date)
        let inRange = records.filter { range.contains($0.startedAt) }
        var stats = PeriodStats(interval: range)
        stats.workouts = inRange.count
        stats.duration = inRange.reduce(0.0) { $0 + $1.duration }
        stats.calories = inRange.reduce(0.0) { $0 + ($1.activeCalories ?? 0) }
        stats.activeDays = Set(inRange.map { calendar.startOfDay(for: $0.startedAt) }).count

        let logs = inRange.flatMap(\.exercises)
        stats.sets = logs.reduce(0) { $0 + $1.doneSets.count }
        stats.volume = logs.reduce(0.0) { $0 + $1.volume }
        stats.injuries = logs.filter(\.injured).count
        let efforts = logs.compactMap(\.effort)
        stats.averageEffort = efforts.isEmpty ? nil : Double(efforts.reduce(0, +)) / Double(efforts.count)
        stats.muscleLoads = MuscleAnalysis.loads(logged: logs)

        // Volume per day across the whole period, zero-filled.
        var days: [DayVolume] = []
        var day = range.start
        while day < range.end {
            let dayVolume = inRange.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0.0) { total, record in total + record.exercises.reduce(0.0) { $0 + $1.volume } }
            days.append(DayVolume(day: day, volume: dayVolume))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        stats.dailyVolume = days

        var setsByExercise: [String: Int] = [:]
        for log in logs where log.hasProgress { setsByExercise[log.name, default: 0] += log.doneSets.count }
        stats.topExercises = setsByExercise.sorted { $0.value > $1.value }.prefix(5).map { ExerciseCount(name: $0.key, sets: $0.value) }

        stats.personalRecords = inRange.flatMap { HistoryService.personalRecords(in: $0, allRecords: records) }
        return stats
    }

    /// Percentage change, or nil when there's nothing to compare with.
    static func change(_ current: Double, from previous: Double) -> Double? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }

    // MARK: Streaks

    static func workoutDays(_ records: [WorkoutRecord]) -> Set<Date> {
        Set(records.map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// Consecutive days with a workout, ending today (or yesterday, so the
    /// streak is still alive until you miss a full day).
    static func currentDayStreak(_ days: Set<Date>, today: Date = Date()) -> Int {
        var day = calendar.startOfDay(for: today)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func longestDayStreak(_ days: Set<Date>) -> Int {
        let sorted = days.sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in sorted {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// Consecutive weeks (Mon-Sun) reaching the weekly goal. The current week
    /// counts once it reaches the goal, and doesn't break the streak before then.
    static func weekStreak(_ records: [WorkoutRecord], goal: Int, today: Date = Date()) -> Int {
        var counts: [Date: Int] = [:]
        for record in records {
            if let week = calendar.dateInterval(of: .weekOfYear, for: record.startedAt)?.start {
                counts[week, default: 0] += 1
            }
        }
        guard var week = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return 0 }
        var streak = 0
        if (counts[week] ?? 0) >= goal { streak += 1 }
        while true {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
            guard (counts[week] ?? 0) >= goal else { break }
            streak += 1
        }
        return streak
    }
}
