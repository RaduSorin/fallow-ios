import Foundation

/// The countdown of a guided exercise. Works from dates, not ticks, so it stays right
/// while the phone is locked or the app is in the background.
struct ExerciseClock: Equatable, Sendable {
    let duration: TimeInterval
    /// When the time runs out, while running.
    private(set) var endsAt: Date?
    /// Seconds left, while paused.
    private(set) var pausedRemaining: TimeInterval?

    init(duration: TimeInterval, start: Date) {
        self.duration = max(0, duration)
        endsAt = start.addingTimeInterval(self.duration)
    }

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    func isOver(at now: Date) -> Bool { remaining(at: now) <= 0 }

    /// How much of the time has passed, 0 to 1.
    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    mutating func pause(at now: Date) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    mutating func resume(at now: Date) {
        guard let left = pausedRemaining else { return }
        endsAt = now.addingTimeInterval(left)
        pausedRemaining = nil
    }

    /// What the Live Activity shows for this clock.
    func activityState(finished: Bool, at now: Date) -> ExerciseActivityAttributes.ContentState {
        .init(
            endsAt: finished || isPaused ? nil : endsAt,
            remaining: finished ? 0 : remaining(at: now),
            finished: finished
        )
    }
}

extension Exercise {
    /// The steps as written: one paragraph per step (paragraphs are separated by an empty line).
    var stepList: [String] {
        steps.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
