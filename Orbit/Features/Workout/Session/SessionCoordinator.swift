import ActivityKit
import Foundation
import Observation
import SwiftData
import OrbitData
import OrbitEngine

/// App-wide state of the running workout: which session, whether its screen is up, the rest timer,
/// the Live Activity, and the summary shown after finishing. One shared instance, so Live Activity
/// buttons (which run in the app process) reach the same session the screen shows.
@Observable
final class SessionCoordinator {
    static let shared = SessionCoordinator()

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

    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var activity: Activity<WorkoutActivityAttributes>?

    struct FinishedSession {
        let title: String?
        let summary: SessionSummary
        let records: [SessionRecord]
    }

    /// Called once at launch: picks up a session left running and wires the Live Activity buttons.
    func attach(_ container: ModelContainer) {
        context = container.mainContext
        session = SessionRepository.activeSession(in: container.mainContext)
        activity = Activity<WorkoutActivityAttributes>.activities.first
        if session == nil { endActivity() } else { syncActivity() }
        SessionActions.handler = { [weak self] action in await self?.handle(action) }
    }

    /// Starts a session (or reopens the one already running).
    func start(template: RoutineTemplate?, increment: Double, context: ModelContext) {
        if session == nil {
            session = SessionRepository.start(template: template, history: history(context), increment: increment, in: context)
            startActivity()
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
        endActivity()
        if !finished { isPresented = false }
        touch()
    }

    func discard(context: ModelContext) {
        guard let session else { return }
        SessionRepository.discard(session, in: context)
        self.session = nil
        skipRest()
        endActivity()
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

    /// Redraw the session screen and refresh the Live Activity after any change.
    func touch() {
        version += 1
        syncActivity()
    }

    // MARK: Rest timer (WRK-06)

    func startRest(seconds: Int, exerciseName: String) {
        guard seconds > 0 else { return }
        restDuration = TimeInterval(seconds)
        setRestEnd(.now.addingTimeInterval(restDuration), exerciseName: exerciseName)
    }

    /// −15 / +15 / +30 s. With no rest running, a positive amount starts one.
    func adjustRest(by seconds: Int, exerciseName: String) {
        guard let end = restEnd else {
            if seconds > 0 { startRest(seconds: seconds, exerciseName: exerciseName) }
            return
        }
        let newEnd = max(Date.now.addingTimeInterval(1), end.addingTimeInterval(TimeInterval(seconds)))
        restDuration = max(1, restDuration + TimeInterval(seconds))
        setRestEnd(newEnd, exerciseName: exerciseName)
    }

    func skipRest() {
        restTask?.cancel()
        restEnd = nil
        NotificationScheduler.cancelRestEnd()
        syncActivity()
    }

    private func setRestEnd(_ end: Date, exerciseName: String) {
        restEnd = end
        restTask?.cancel()
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled, let self else { return }
            self.restEnd = nil
            self.restFinished += 1
            self.syncActivity()
        }
        Task { await NotificationScheduler.scheduleRestEnd(at: end, exerciseName: exerciseName) }
        syncActivity()
    }

    // MARK: Live Activity buttons

    private func handle(_ action: SessionAction) async {
        guard let session, let context else { return }
        let language = SettingsSnapshot(from: .orbit).language
        switch action {
        case .completeSet:
            guard let next = SessionRepository.nextOpenSet(in: session) else { return }
            SessionRepository.setCompleted(next.set, true, in: context)
            if next.exercise.exercise.type != .cardio {
                startRest(seconds: next.set.isWarmup ? min(next.exercise.restSec, 60) : next.exercise.restSec,
                          exerciseName: next.exercise.exercise.displayName(language: language))
            }
        case .extendRest(let seconds):
            let name = SessionRepository.nextOpenSet(in: session)?.exercise.exercise.displayName(language: language) ?? ""
            adjustRest(by: seconds, exerciseName: name)
        }
        version += 1
        if let activity {
            await Self.push(ActivityContent(state: state(for: session), staleDate: nil), to: activity.id)
        }
    }

    // MARK: Live Activity (WRK-07)

    private func startActivity() {
        guard let session, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endActivity()
        let name = session.template?.name ?? L10n.string("workout.emptySession")
        let attributes = WorkoutActivityAttributes(routineName: name, startedAt: session.startedAt)
        activity = try? Activity.request(attributes: attributes, content: .init(state: state(for: session), staleDate: nil))
    }

    private func syncActivity() {
        guard let session else { return }
        guard let activity else {
            startActivity()
            return
        }
        let content = ActivityContent(state: state(for: session), staleDate: nil)
        let id = activity.id
        Task { await Self.push(content, to: id) }
    }

    /// Activity isn't Sendable, so it's looked up again off the main actor instead of being passed across.
    private nonisolated static func push(_ content: ActivityContent<WorkoutActivityAttributes.ContentState>, to id: String) async {
        for running in Activity<WorkoutActivityAttributes>.activities where running.id == id {
            await running.update(content)
        }
    }

    private func endActivity() {
        activity = nil
        Task.detached {
            for running in Activity<WorkoutActivityAttributes>.activities {
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func state(for session: WorkoutSession) -> WorkoutActivityAttributes.ContentState {
        let language = SettingsSnapshot(from: .orbit).language
        let entries = SessionRepository.exercises(in: session)
        let all = entries.flatMap(\.sets)
        let next = SessionRepository.nextOpenSet(in: session)
        let current = next?.exercise ?? entries.last
        return .init(exerciseName: current?.exercise.displayName(language: language) ?? "",
                     setNumber: next.map { $0.index + 1 } ?? 0,
                     setCount: current?.sets.count ?? 0,
                     setsDone: all.count(where: \.isCompleted),
                     setsTotal: all.count,
                     restEnd: restEnd)
    }
}
