import SwiftUI
import SwiftData
import Charts

/// Streak calendar plus weekly / monthly progress summaries.
struct ProgressTabView: View {
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var records: [WorkoutRecord]
    @AppStorage(SettingsKey.weeklyGoal) private var weeklyGoal = 3
    @State private var period: SummaryPeriod = .week
    @State private var anchor = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StreakHeader(records: records)
                    StreakCalendarView(records: records)
                    Picker("Period", selection: $period) {
                        ForEach(SummaryPeriod.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    PeriodSummaryView(period: period, anchor: $anchor, records: records)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Progress")
            .onChange(of: period) { anchor = Date() }
        }
    }
}

/// Day streak, best streak and weekly-goal streak.
struct StreakHeader: View {
    var records: [WorkoutRecord]
    @AppStorage(SettingsKey.weeklyGoal) private var weeklyGoal = 3

    var body: some View {
        let days = StatsCalculator.workoutDays(records)
        let thisWeek = records.filter { StatsCalculator.interval(for: .week, containing: Date()).contains($0.startedAt) }.count
        HStack(spacing: 10) {
            StatTile(title: "Day streak", value: "\(StatsCalculator.currentDayStreak(days))",
                     detail: "Best \(StatsCalculator.longestDayStreak(days))", symbol: "flame.fill", tint: .orange)
            StatTile(title: "Week streak", value: "\(StatsCalculator.weekStreak(records, goal: weeklyGoal))",
                     detail: "Goal \(weeklyGoal)/week", symbol: "calendar", tint: .blue)
            StatTile(title: "This week", value: "\(thisWeek)/\(weeklyGoal)",
                     detail: thisWeek >= weeklyGoal ? "Goal hit ✓" : "\(weeklyGoal - thisWeek) to go", symbol: "target", tint: .green)
        }
    }
}

/// Month calendar; days with a workout are filled. Tap a day to see its workouts.
struct StreakCalendarView: View {
    var records: [WorkoutRecord]
    @State private var month = Date()
    @State private var selectedDay: Date?

    private var calendar: Calendar { StatsCalculator.calendar }

    var body: some View {
        let days = StatsCalculator.workoutDays(records)
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            let symbols = weekdaySymbols
            HStack {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(symbols[i]).font(.caption2.bold()).foregroundStyle(Theme.subtext).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, trained: days.contains(day), streak: inStreak(day, days: days))
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
            if let selectedDay {
                let dayRecords = records.filter { calendar.isDate($0.startedAt, inSameDayAs: selectedDay) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDay.formatted(date: .complete, time: .omitted)).font(.subheadline.bold())
                    if dayRecords.isEmpty {
                        Text("Rest day").font(.caption).foregroundStyle(Theme.subtext)
                    }
                    ForEach(dayRecords) { record in
                        NavigationLink {
                            WorkoutSummaryView(record: record)
                        } label: {
                            HistoryRow(record: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dayCell(_ day: Date, trained: Bool, streak: Bool) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(trained ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(trained ? Color.white : Color.primary)
                .background {
                    if trained {
                        RoundedRectangle(cornerRadius: 8).fill(streak ? Color.orange : Color.accentColor)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.primary : (isToday ? Color.accentColor : .clear), lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
    }

    /// Part of a run of 2+ consecutive training days.
    private func inStreak(_ day: Date, days: Set<Date>) -> Bool {
        guard days.contains(day) else { return false }
        let before = calendar.date(byAdding: .day, value: -1, to: day).map { days.contains($0) } ?? false
        let after = calendar.date(byAdding: .day, value: 1, to: day).map { days.contains($0) } ?? false
        return before || after
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Days of the month with leading blanks so the 1st lands on its weekday.
    private var gridDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        var day = interval.start
        while day < interval.end {
            days.append(calendar.startOfDay(for: day))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private func shift(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        selectedDay = nil
    }
}

/// Weekly or monthly summary with comparison to the previous period.
struct PeriodSummaryView: View {
    var period: SummaryPeriod
    @Binding var anchor: Date
    var records: [WorkoutRecord]

    var body: some View {
        let stats = StatsCalculator.stats(for: period, containing: anchor, records: records)
        let previousAnchor = StatsCalculator.calendar.date(byAdding: period.component, value: -1, to: anchor) ?? anchor
        let previous = StatsCalculator.stats(for: period, containing: previousAnchor, records: records)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(title(stats.interval)).font(.headline)
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(stats.interval.end > Date())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "Workouts", value: "\(stats.workouts)",
                         detail: changeText(Double(stats.workouts), Double(previous.workouts)), symbol: "dumbbell.fill")
                StatTile(title: "Time", value: Format.shortDuration(stats.duration),
                         detail: changeText(stats.duration, previous.duration), symbol: "timer")
                StatTile(title: "Volume", value: Format.volume(stats.volume),
                         detail: changeText(stats.volume, previous.volume), symbol: "scalemass", tint: .purple)
                StatTile(title: "Calories", value: "\(Int(stats.calories)) kcal",
                         detail: changeText(stats.calories, previous.calories), symbol: "flame.fill", tint: .orange)
                StatTile(title: "Sets", value: "\(stats.sets)",
                         detail: changeText(Double(stats.sets), Double(previous.sets)), symbol: "square.stack.3d.up")
                StatTile(title: "Avg effort", value: stats.averageEffort.map { String(format: "%.1f", $0) } ?? "–",
                         detail: stats.injuries > 0 ? "\(stats.injuries) injury flag(s)" : "No injuries",
                         symbol: "gauge.with.dots.needle.50percent", tint: stats.injuries > 0 ? .red : .green)
            }

            if stats.volume > 0 {
                VStack(alignment: .leading) {
                    Text("Volume per day").font(.subheadline.bold())
                    Chart(stats.dailyVolume) { entry in
                        BarMark(x: .value("Day", entry.day, unit: .day), y: .value("kg", entry.volume))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 160)
                }
            }

            if !stats.muscleLoads.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Muscles trained").font(.subheadline.bold())
                    MuscleOverview(loads: stats.muscleLoads)
                }
            }

            if !stats.topExercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Most trained").font(.subheadline.bold())
                    ForEach(stats.topExercises) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(item.sets) sets").foregroundStyle(Theme.subtext)
                        }
                        .font(.subheadline)
                    }
                }
            }

            if !stats.personalRecords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Personal records").font(.subheadline.bold())
                    ForEach(Array(stats.personalRecords.enumerated()), id: \.offset) { _, pr in
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            Text(pr.exerciseName)
                            Spacer()
                            Text("\(Format.weight(pr.weight)) × \(pr.reps)").bold()
                        }
                        .font(.subheadline)
                    }
                }
            }

            if stats.workouts == 0 {
                Text("No workouts in this \(period.rawValue).").foregroundStyle(Theme.subtext)
            }
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func move(_ value: Int) {
        anchor = StatsCalculator.calendar.date(byAdding: period.component, value: value, to: anchor) ?? anchor
    }

    private func title(_ interval: DateInterval) -> String {
        switch period {
        case .week:
            let end = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        }
    }

    private func changeText(_ current: Double, _ previous: Double) -> String {
        guard let change = StatsCalculator.change(current, from: previous) else {
            return previous == 0 && current > 0 ? "New this \(period.rawValue)" : "vs last \(period.rawValue): –"
        }
        let arrow = change >= 0 ? "▲" : "▼"
        return "\(arrow) \(Int(abs(change).rounded()))% vs last \(period.rawValue)"
    }
}
