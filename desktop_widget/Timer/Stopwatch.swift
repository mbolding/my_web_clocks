// Stopwatch — the dial timer's other mode: counts up from zero, and can be paused and
// reset. Its start time is saved, so a running stopwatch carries on across a quit or
// restart, like the timer.

import Foundation

@MainActor
final class Stopwatch: ObservableObject {
    static let shared = Stopwatch()

    enum State: Equatable {
        case idle
        case running(start: Date) // when it would have started had it never paused
        case paused(elapsed: TimeInterval)
    }

    @Published private(set) var state = State.idle

    private init() {
        let defaults = UserDefaults.standard
        if let start = defaults.object(forKey: "stopwatchStart") as? Date {
            state = .running(start: start)
        } else if let elapsed = defaults.object(forKey: "stopwatchPaused") as? Double, elapsed > 0 {
            state = .paused(elapsed: elapsed)
        }
    }

    func elapsed(at now: Date = .now) -> TimeInterval {
        switch state {
        case .idle: 0
        case .running(let start): max(0, now.timeIntervalSince(start))
        case .paused(let elapsed): elapsed
        }
    }

    /// The centre tap: start, pause, or resume.
    func toggle() {
        switch state {
        case .idle: state = .running(start: .now)
        case .running: state = .paused(elapsed: elapsed())
        case .paused(let elapsed): state = .running(start: .now - elapsed)
        }
        save()
    }

    func reset() {
        state = .idle
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        switch state {
        case .running(let start):
            defaults.set(start, forKey: "stopwatchStart")
            defaults.removeObject(forKey: "stopwatchPaused")
        case .paused(let elapsed):
            defaults.removeObject(forKey: "stopwatchStart")
            defaults.set(elapsed, forKey: "stopwatchPaused")
        case .idle:
            defaults.removeObject(forKey: "stopwatchStart")
            defaults.removeObject(forKey: "stopwatchPaused")
        }
    }
}
