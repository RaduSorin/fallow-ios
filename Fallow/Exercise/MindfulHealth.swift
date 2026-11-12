import Foundation
import HealthKit

/// Saves the length of a guided exercise to Apple Health as mindful minutes, when the person
/// turned it on. Only the start and end go to Health, never what the exercise or the note says.
enum MindfulHealth {
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var mindful: HKCategoryType { HKCategoryType(.mindfulSession) }

    /// Shows Apple's permission sheet the first time. Returns whether saving is allowed.
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        let store = HKHealthStore()
        do {
            try await store.requestAuthorization(toShare: [mindful], read: [])
        } catch {
            return false
        }
        return store.authorizationStatus(for: mindful) == .sharingAuthorized
    }

    /// The time actually spent in the exercise (pauses left out), ending when the time ran out
    /// or now. Nil under a minute.
    static func interval(for clock: ExerciseClock, finishedAt now: Date) -> DateInterval? {
        let active = clock.duration - clock.remaining(at: now)
        guard active >= 60 else { return nil }
        let end = min(now, clock.endsAt ?? now)
        return DateInterval(start: end.addingTimeInterval(-active), end: end)
    }

    static func save(_ interval: DateInterval) async {
        guard isAvailable else { return }
        let store = HKHealthStore()
        guard store.authorizationStatus(for: mindful) == .sharingAuthorized else { return }
        let sample = HKCategorySample(
            type: mindful,
            value: HKCategoryValue.notApplicable.rawValue,
            start: interval.start,
            end: interval.end
        )
        try? await store.save(sample)
    }
}
