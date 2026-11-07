import Foundation
import Observation
import SwiftData
import OrbitData
import OrbitEngine

/// App-wide state of the running workout: which session, whether its screen is up, the rest timer,
/// and the summary shown after finishing. Lives in the environment so the tab mini-bar can see it.
@Observable
final class SessionCoordinator {
    private(set) var session: WorkoutSession?
    var isPresented = false
    /// Set after `finish`; the session screen shows the summary until it's closed.
    private(set) var summary: FinishedSession?

    private(set) var restEnd: Date?
    private(set) var restDuration: TimeInterval = 0
    /// Bumped when a rest ends on its own (haptic trigger).
    private(set) var restFinished = 0
    /// Bumped after every data change, so views redraw (relationship edits aren't reliably observed).
    private(set) var version = 0
    private var restTask: Task<Void, Never>?

    struct FinishedSession {
        let title: String?
        let summary: SessionSummary
        let records: [SessionRecord]
    }

    /// Picks up a session left running (app was closed mid-workout).
    func restore(from context: ModelContext) {
        session = SessionRepository.activeSession(in: context)
    }

    /// Starts a session (or reopens the one already running).
    func start(template: RoutineTemplate?, increment: Double, context: ModelContext) {
        if session == nil {
            session = SessionRepository.start(template: template, history: history(context), increment: increment, in: context)
        }
        summary = nil
        isPresented = true
        touch()
    }

    func finish(context: ModelContext) {
        guard let session else { return }
        // Read everything before finishing: with nothing ticked the session gets deleted.
        let title = session.template?.name
        let start = session.startedAt
        let done = session.sets.filter(\.isCompleted).map(\.record)
        let finished = !done.isEmpty
        let end = Date.now
        let records = SessionRepository.finish(session, history: history(context), in: context, now: end)
        summary = finished
            ? FinishedSession(title: title, summary: SessionSummary(start: start, end: end, sets: done), records: records)
            : nil
        self.session = nil
        skipRest()
        if !finished { isPresented = false }
        touch()
    }

    func discard(context: ModelContext) {
        guard let session else { return }
        SessionRepository.discard(session, in: context)
        self.session = nil
        skipRest()
        isPresented = false
        touch()
    }

    func closeSummary() {
        summary = nil
        isPresented = false
    }

    func history(_ context: ModelContext) -> [WorkoutSession] {
        (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil }))) ?? []
    }

    func touch() { version += 1 }

    // MARK: Rest timer (WRK-06)

    func startRest(seconds: Int, exerciseName: String) {
        guard seconds > 0 else { return }
        restDuration = TimeInterval(seconds)
        setRestEnd(.now.addingTimeInterval(restDuration), exerciseName: exerciseName)
    }

    /// −15 / +15 s.
    func adjustRest(by seconds: Int, exerciseName: String) {
        guard let end = restEnd else { return }
        let newEnd = max(Date.now.addingTimeInterval(1), end.addingTimeInterval(TimeInterval(seconds)))
        restDuration = max(1, restDuration + TimeInterval(seconds))
        setRestEnd(newEnd, exerciseName: exerciseName)
    }

    func skipRest() {
        restTask?.cancel()
        restEnd = nil
        NotificationScheduler.cancelRestEnd()
    }

    private func setRestEnd(_ end: Date, exerciseName: String) {
        restEnd = end
        restTask?.cancel()
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled, let self else { return }
            self.restEnd = nil
            self.restFinished += 1
        }
        Task { await NotificationScheduler.scheduleRestEnd(at: end, exerciseName: exerciseName) }
    }
}
