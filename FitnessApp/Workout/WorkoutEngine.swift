import Foundation
import SwiftData
import UIKit

/// The workout in progress. Saved to disk on every change so it survives the
/// app being closed, and so Watch commands can be applied in the background.
struct ActiveWorkout: Codable {
    var id: UUID = UUID()
    var name: String
    var templateID: UUID?
    var startedAt: Date
    var exercises: [LoggedExercise]
    var currentIndex: Int = 0
    var restEndsAt: Date?
    var restTotal: Int = 0
    var restBetweenExercises: Bool = false
    /// Exercise whose sets are all done and that is waiting for an effort rating.
    var effortPendingIndex: Int?

    var isResting: Bool { (restEndsAt ?? .distantPast) > Date() }
    var allDone: Bool { exercises.allSatisfy(\.isFinished) }
    var finishedCount: Int { exercises.filter(\.isFinished).count }

    /// First exercise whose sets are all done but has no effort rating yet.
    var unratedIndex: Int? {
        exercises.indices.first { exercises[$0].status == .pending && exercises[$0].allSetsDone }
    }
}

/// Owns the live workout: set completion, rest timers, effort, finishing and
/// saving. The phone UI and the Watch both drive it.
@MainActor
final class WorkoutEngine: ObservableObject {
    static let shared = WorkoutEngine()

    @Published private(set) var workout: ActiveWorkout? {
        didSet {
            persist()
            pushToWatch()
        }
    }
    @Published var isMinimized = false
    /// Set after finishing so the summary can be shown.
    @Published var finishedRecordID: UUID?
    /// The user tapped Finish while an exercise still needed its effort rating:
    /// finish right after that rating is saved.
    private var finishAfterRating = false
    /// The last workout ended with Discard (tells the Watch not to save it).
    private var lastEndWasDiscard = false

    private var restTimer: Timer?
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("active-workout.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(ActiveWorkout.self, from: data) {
            workout = saved
        }
        scheduleRestTimer()
    }

    var isActive: Bool { workout != nil }

    var currentExercise: LoggedExercise? {
        guard let w = workout, w.exercises.indices.contains(w.currentIndex) else { return nil }
        return w.exercises[w.currentIndex]
    }

    // MARK: Start / finish

    func start(name: String, templateID: UUID?, items: [PlannedExercise]) {
        guard !items.isEmpty else { return }
        restTimer?.invalidate()
        NotificationManager.shared.cancelRest()
        finishAfterRating = false
        lastEndWasDiscard = false
        let plans = withNewerRecords(items, templateID: templateID)
        workout = ActiveWorkout(name: name, templateID: templateID, startedAt: Date(),
                                exercises: plans.map(LoggedExercise.init(planned:)))
        isMinimized = false
        if AppSettings.launchWatchWorkout { HealthKitManager.shared.startWatchWorkout() }
        Task { _ = await NotificationManager.shared.requestAuthorization() }
    }

    /// If an exercise was done more recently (e.g. in another session) than
    /// this session was last saved, start from that newer record.
    private func withNewerRecords(_ items: [PlannedExercise], templateID: UUID?) -> [PlannedExercise] {
        let context = AppModel.container.mainContext
        var savedAt = Date.distantPast
        if let templateID {
            let descriptor = FetchDescriptor<SessionTemplate>(predicate: #Predicate { $0.id == templateID })
            savedAt = (try? context.fetch(descriptor).first?.updatedAt) ?? .distantPast
        }
        var records = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        if !AppSettings.updateTemplateAfterWorkout, let templateID {
            // "Save last weights into the session" is off: keep this session's
            // own numbers and only pull in records from other sessions.
            records = records.filter { $0.templateID != templateID }
        }
        return items.map { item in
            guard let newest = HistoryService.lastLogWithDate(for: item.exerciseId, in: records),
                  newest.date > savedAt else { return item }
            var plan = item
            plan.sets = newest.log.asPlanned().sets
            return plan
        }
    }

    /// Finish button: asks for any missing effort rating first, then saves.
    func requestFinish() {
        guard let w = workout else { return }
        if let index = w.unratedIndex {
            finishAfterRating = true
            mutate { $0.effortPendingIndex = index }
        } else {
            finish()
        }
    }

    /// Saves the workout (complete or finished early) and returns the record id.
    @discardableResult
    func finish() -> UUID? {
        finishAfterRating = false
        guard var w = workout else { return nil }
        // An exercise with every set ticked counts as completed even if its
        // effort sheet was dismissed.
        for i in w.exercises.indices where w.exercises[i].status == .pending && w.exercises[i].allSetsDone {
            w.exercises[i].status = .completed
            w.exercises[i].completedAt = w.exercises[i].sets.compactMap(\.completedAt).max()
        }
        let end = Date()
        let context = AppModel.container.mainContext
        let record = WorkoutRecord(name: w.name, templateID: w.templateID, startedAt: w.startedAt,
                                   endedAt: end, finishedEarly: !w.allDone, exercises: w.exercises)
        context.insert(record)
        if AppSettings.updateTemplateAfterWorkout, let templateID = w.templateID {
            updateTemplate(id: templateID, with: w.exercises, context: context)
        }
        try? context.save()

        restTimer?.invalidate()
        NotificationManager.shared.cancelRest()
        workout = nil
        isMinimized = false
        // Show the summary once the workout screen has finished closing.
        let finishedID = record.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.finishedRecordID = finishedID
        }

        let recordID = record.id
        let start = w.startedAt
        Task {
            // Give the Watch a moment to save its workout to Health first.
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await self.refreshCalories(recordID: recordID, start: start, end: end)
        }
        return record.id
    }

    func discard() {
        lastEndWasDiscard = true
        restTimer?.invalidate()
        NotificationManager.shared.cancelRest()
        workout = nil
        isMinimized = false
    }

    func refreshCalories(recordID: UUID, start: Date, end: Date) async {
        let estimate = await HealthKitManager.shared.estimateCalories(from: start, to: end)
        let context = AppModel.container.mainContext
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.id == recordID })
        guard let record = try? context.fetch(descriptor).first else { return }
        record.activeCalories = estimate.kilocalories
        record.calorieSourceRaw = estimate.source.rawValue
        record.averageHeartRate = estimate.averageHeartRate
        record.maxHeartRate = estimate.maxHeartRate
        try? context.save()
    }

    /// Writes what was actually lifted back into the saved session, so next
    /// time it starts from the previous record.
    private func updateTemplate(id: UUID, with logs: [LoggedExercise], context: ModelContext) {
        let descriptor = FetchDescriptor<SessionTemplate>(predicate: #Predicate { $0.id == id })
        guard let template = try? context.fetch(descriptor).first else { return }
        var items = template.items
        for index in items.indices {
            guard let log = logs.first(where: { $0.exerciseId == items[index].exerciseId && $0.hasProgress }) else { continue }
            items[index].sets = log.asPlanned().sets
        }
        template.items = items
        template.lastPerformedAt = Date()
    }

    // MARK: Sets

    func nextSetIndex(in exercise: LoggedExercise) -> Int? {
        exercise.sets.firstIndex { !$0.isDone }
    }

    func toggleSet(exercise ex: Int, set s: Int) {
        guard let w = workout, w.exercises.indices.contains(ex), w.exercises[ex].sets.indices.contains(s) else { return }
        let markingDone = !w.exercises[ex].sets[s].isDone
        mutate { w in
            w.currentIndex = ex
            w.exercises[ex].sets[s].isDone = markingDone
            w.exercises[ex].sets[s].completedAt = markingDone ? Date() : nil
            if !markingDone {
                w.exercises[ex].status = .pending
                if w.effortPendingIndex == ex { w.effortPendingIndex = nil }
            }
        }
        if markingDone {
            afterSetCompleted(exercise: ex)
        } else if workout?.isResting == true {
            // Un-ticking a set cancels the rest it started.
            skipRest()
        }
    }

    private func afterSetCompleted(exercise ex: Int) {
        guard let w = workout else { return }
        let exercise = w.exercises[ex]
        if nextSetIndex(in: exercise) != nil {
            startRest(seconds: exercise.restBetweenSets, betweenExercises: false)
        } else {
            mutate { $0.effortPendingIndex = ex }
            if hasPendingExercise(after: ex) {
                startRest(seconds: exercise.restAfterExercise, betweenExercises: true)
            } else {
                skipRest()
            }
        }
    }

    func updateSet(exercise ex: Int, set s: Int, reps: Int? = nil, weight: Double? = nil, kind: SetKind? = nil) {
        mutate { w in
            guard w.exercises.indices.contains(ex), w.exercises[ex].sets.indices.contains(s) else { return }
            if let reps { w.exercises[ex].sets[s].reps = max(0, reps) }
            if let weight { w.exercises[ex].sets[s].weight = max(0, weight) }
            if let kind { w.exercises[ex].sets[s].kind = kind }
        }
    }

    func addSet(exercise ex: Int, kind: SetKind) {
        mutate { w in
            guard w.exercises.indices.contains(ex) else { return }
            var sets = w.exercises[ex].sets
            let template = sets.last(where: { $0.kind == kind }) ?? sets.last(where: { $0.kind == .normal }) ?? sets.last
            var planned = PlannedSet(kind: kind, reps: template?.reps ?? 10, weight: template?.weight ?? 0)
            if kind == .drop, template?.kind != .drop, let weight = template?.weight {
                planned.weight = ProgressionEngine.round(weight * 0.8, to: ProgressionEngine.increment(for: w.exercises[ex].equipments))
            }
            let newSet = LoggedSet(planned: planned)
            switch kind {
            case .warmup:
                let firstWorking = sets.firstIndex { $0.kind != .warmup } ?? sets.count
                sets.insert(newSet, at: firstWorking)
            case .normal:
                let lastNormal = sets.lastIndex { $0.kind == .normal }.map { $0 + 1 } ?? sets.count
                sets.insert(newSet, at: lastNormal)
            case .drop:
                sets.append(newSet)
            }
            w.exercises[ex].sets = sets
            w.exercises[ex].status = .pending
            if w.effortPendingIndex == ex { w.effortPendingIndex = nil }
        }
    }

    func removeSet(exercise ex: Int, set s: Int) {
        mutate { w in
            guard w.exercises.indices.contains(ex), w.exercises[ex].sets.indices.contains(s),
                  w.exercises[ex].sets.count > 1 else { return }
            w.exercises[ex].sets.remove(at: s)
        }
    }

    /// Applies an overload suggestion to the sets not done yet.
    func apply(_ suggestion: OverloadSuggestion, toExercise ex: Int) {
        mutate { w in
            guard w.exercises.indices.contains(ex) else { return }
            var logged = w.exercises[ex]
            var plan = PlannedExercise(exerciseId: logged.exerciseId, name: logged.name)
            plan.equipments = logged.equipments
            plan.sets = logged.sets.map { PlannedSet(kind: $0.kind, reps: $0.targetReps, weight: $0.targetWeight) }
            let applied = ProgressionEngine.apply(suggestion, to: plan)
            for i in logged.sets.indices where !logged.sets[i].isDone {
                logged.sets[i].targetReps = applied.sets[i].reps
                logged.sets[i].targetWeight = applied.sets[i].weight
                logged.sets[i].reps = applied.sets[i].reps
                logged.sets[i].weight = applied.sets[i].weight
            }
            w.exercises[ex] = logged
        }
    }

    // MARK: Exercises

    func focus(exercise ex: Int) {
        mutate { w in
            guard w.exercises.indices.contains(ex) else { return }
            w.currentIndex = ex
        }
    }

    /// Marks the exercise as finished and asks for effort, even if some sets
    /// were not done.
    func requestFinishExercise(_ ex: Int) {
        mutate { $0.effortPendingIndex = ex }
        if let w = workout, !w.isResting, hasPendingExercise(after: ex) {
            startRest(seconds: w.exercises[ex].restAfterExercise, betweenExercises: true)
        }
    }

    func submitEffort(exercise ex: Int, effort: Int?, injured: Bool, note: String) {
        mutate { w in
            guard w.exercises.indices.contains(ex) else { return }
            w.exercises[ex].effort = effort
            w.exercises[ex].injured = injured
            w.exercises[ex].injuryNote = injured ? note : ""
            w.exercises[ex].status = .completed
            w.exercises[ex].completedAt = Date()
            w.effortPendingIndex = nil
            if let next = Self.nextPendingIndex(in: w, after: ex) { w.currentIndex = next }
        }
        if finishAfterRating, let w = workout {
            if let next = w.unratedIndex {
                mutate { $0.effortPendingIndex = next }
            } else {
                finish()
            }
        }
    }

    func cancelEffort() {
        finishAfterRating = false
        guard workout?.effortPendingIndex != nil else { return }
        mutate { $0.effortPendingIndex = nil }
    }

    func skipExercise(_ ex: Int) {
        mutate { w in
            guard w.exercises.indices.contains(ex) else { return }
            w.exercises[ex].status = .skipped
            if w.effortPendingIndex == ex { w.effortPendingIndex = nil }
            if let next = Self.nextPendingIndex(in: w, after: ex) { w.currentIndex = next }
        }
    }

    func addExercise(_ planned: PlannedExercise) {
        mutate { w in
            w.exercises.append(LoggedExercise(planned: planned))
            if w.exercises[w.currentIndex].status != .pending { w.currentIndex = w.exercises.count - 1 }
        }
    }

    private func hasPendingExercise(after ex: Int) -> Bool {
        guard let w = workout else { return false }
        return Self.nextPendingIndex(in: w, after: ex) != nil
    }

    private static func nextPendingIndex(in w: ActiveWorkout, after ex: Int) -> Int? {
        let order = Array(w.exercises.indices.dropFirst(ex + 1)) + Array(w.exercises.indices.prefix(ex))
        return order.first { w.exercises[$0].status == .pending }
    }

    // MARK: Rest timer

    func startRest(seconds: Int, betweenExercises: Bool) {
        guard seconds > 0 else { skipRest(); return }
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        mutate { w in
            w.restEndsAt = end
            w.restTotal = seconds
            w.restBetweenExercises = betweenExercises
        }
        NotificationManager.shared.scheduleRestEnd(at: end, betweenExercises: betweenExercises, nextUp: nextUpDescription())
        scheduleRestTimer()
    }

    func addRest(seconds: Int) {
        guard let w = workout else { return }
        let base = w.isResting ? (w.restEndsAt ?? Date()) : Date()
        let end = base.addingTimeInterval(TimeInterval(seconds))
        mutate { w in
            w.restTotal = w.isResting ? w.restTotal + seconds : seconds
            w.restEndsAt = end
        }
        NotificationManager.shared.scheduleRestEnd(at: end, betweenExercises: w.restBetweenExercises, nextUp: nextUpDescription())
        scheduleRestTimer()
    }

    func skipRest() {
        restTimer?.invalidate()
        NotificationManager.shared.cancelRest()
        guard workout?.restEndsAt != nil else { return }
        mutate { $0.restEndsAt = nil }
    }

    private func scheduleRestTimer() {
        restTimer?.invalidate()
        guard let end = workout?.restEndsAt else { return }
        let interval = end.timeIntervalSinceNow
        guard interval > 0 else {
            mutate { $0.restEndsAt = nil }
            return
        }
        restTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.restFinished() }
        }
    }

    private func restFinished() {
        guard workout?.restEndsAt != nil else { return }
        mutate { $0.restEndsAt = nil }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Watch

    /// Applies a Watch command and returns the new state for the Watch.
    func handle(_ command: WatchCommand, rating: (effort: Int, injured: Bool)? = nil) -> WatchSnapshot {
        guard let w = workout else { return .idle }
        let ex = w.currentIndex
        switch command {
        case .completeSet:
            if let exercise = currentExercise, let s = nextSetIndex(in: exercise) {
                toggleSet(exercise: ex, set: s)
            }
        case .rateExercise:
            let effort = min(max(rating?.effort ?? 7, 1), 10)
            let injured = rating?.injured ?? false
            submitEffort(exercise: ex, effort: effort, injured: injured, note: injured ? "Flagged on Apple Watch" : "")
        case .skipRest:
            skipRest()
        case .addRest30:
            addRest(seconds: 30)
        }
        return snapshot()
    }

    func snapshot() -> WatchSnapshot {
        guard let w = workout, w.exercises.indices.contains(w.currentIndex) else {
            var idle = WatchSnapshot.idle
            idle.discarded = lastEndWasDiscard
            idle.updatedAt = Date()
            return idle
        }
        let exercise = w.exercises[w.currentIndex]
        let next = nextSetIndex(in: exercise)
        let set = next.map { exercise.sets[$0] } ?? exercise.sets.last

        var s = WatchSnapshot(isActive: true)
        s.sessionName = w.name
        s.startedAt = w.startedAt
        s.exerciseName = exercise.name
        s.exerciseIndex = w.currentIndex
        s.exerciseCount = w.exercises.count
        s.setIndex = next ?? exercise.sets.count
        s.setCount = exercise.sets.count
        s.setKind = set?.kind ?? .normal
        s.targetReps = set?.reps ?? 0
        s.targetWeight = set?.weight ?? 0
        s.exerciseFinished = next == nil
        s.needsRating = (next == nil && exercise.status == .pending) || w.effortPendingIndex == w.currentIndex
        s.allExercisesDone = w.allDone
        s.restEndsAt = w.isResting ? w.restEndsAt : nil
        s.restTotal = w.restTotal
        s.restIsBetweenExercises = w.restBetweenExercises
        s.nextUp = nextUpDescription()
        s.updatedAt = Date()
        return s
    }

    func pushToWatch() {
        PhoneConnectivity.shared.push(snapshot())
    }

    func nextUpDescription() -> String? {
        guard let w = workout, w.exercises.indices.contains(w.currentIndex) else { return nil }
        let exercise = w.exercises[w.currentIndex]
        if let s = nextSetIndex(in: exercise) {
            let set = exercise.sets[s]
            let kind = set.kind == .normal ? "Set \(s + 1)" : set.kind.label
            return "\(exercise.name) · \(kind): \(set.reps) × \(Format.weight(set.weight))"
        }
        if let next = Self.nextPendingIndex(in: w, after: w.currentIndex) {
            let upcoming = w.exercises[next]
            if let first = upcoming.sets.first {
                return "Next: \(upcoming.name) · \(first.reps) × \(Format.weight(first.weight))"
            }
            return "Next: \(upcoming.name)"
        }
        return "Last exercise done. Finish when you're ready."
    }

    // MARK: Persistence

    private func mutate(_ change: (inout ActiveWorkout) -> Void) {
        guard var w = workout else { return }
        change(&w)
        workout = w
    }

    private func persist() {
        if let workout, let data = try? JSONEncoder().encode(workout) {
            try? data.write(to: fileURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
