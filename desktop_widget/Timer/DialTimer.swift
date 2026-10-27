// DialTimer — the dial timer's state: up to an hour, running, paused, or finished and
// waiting to be dismissed. The end time is saved, so a running timer carries on across
// a quit or restart; one that ran out while the app was closed shows as finished
// without ringing late.

import AppKit

@MainActor
final class DialTimer: ObservableObject {
    static let shared = DialTimer()
    static let maxMinutes = 60

    enum State: Equatable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    @Published private(set) var state = State.idle
    @Published var sound = UserDefaults.standard.object(forKey: "sound") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sound, forKey: "sound") }
    }

    private var alarm: Timer?
    private var chimes: Timer?

    private init() {
        let defaults = UserDefaults.standard
        if let end = defaults.object(forKey: "end") as? Date {
            if end > .now {
                start(until: end)
            } else {
                state = .finished
            }
        } else if let remaining = defaults.object(forKey: "paused") as? Double, remaining > 0 {
            state = .paused(remaining: remaining)
        }
    }

    func remaining(at now: Date = .now) -> TimeInterval {
        switch state {
        case .running(let end): max(0, end.timeIntervalSince(now))
        case .paused(let remaining): remaining
        case .idle, .finished: 0
        }
    }

    func start(minutes: Int) {
        start(seconds: TimeInterval(min(minutes, Self.maxMinutes) * 60))
    }

    func start(seconds: TimeInterval) {
        guard seconds > 0 else { reset(); return }
        start(until: .now + seconds)
    }

    private func start(until end: Date) {
        stopChimes()
        state = .running(end: end)
        alarm?.invalidate()
        alarm = Timer.scheduledTimer(withTimeInterval: end.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        save()
    }

    /// The centre tap: pause, resume, or dismiss a finished timer.
    func toggle() {
        switch state {
        case .running: pause()
        case .paused(let remaining): start(until: .now + remaining)
        case .finished: reset()
        case .idle: break
        }
    }

    func pause() {
        guard case .running = state else { return }
        alarm?.invalidate()
        state = .paused(remaining: remaining())
        save()
    }

    func reset() {
        alarm?.invalidate()
        stopChimes()
        state = .idle
        save()
    }

    private func finish() {
        state = .finished
        save()
        guard sound else { return }
        // Ring every two seconds until dismissed, for up to a minute.
        var rings = 1
        Chime.ring()
        chimes = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            rings += 1
            Chime.ring()
            if rings >= 30 { timer.invalidate(); MainActor.assumeIsolated { self?.chimes = nil } }
        }
    }

    private func stopChimes() {
        chimes?.invalidate()
        chimes = nil
        Chime.sound?.stop()
    }

    private func save() {
        let defaults = UserDefaults.standard
        switch state {
        case .running(let end):
            defaults.set(end, forKey: "end")
            defaults.removeObject(forKey: "paused")
        case .paused(let remaining):
            defaults.removeObject(forKey: "end")
            defaults.set(remaining, forKey: "paused")
        case .idle, .finished:
            defaults.removeObject(forKey: "end")
            defaults.removeObject(forKey: "paused")
        }
    }
}
