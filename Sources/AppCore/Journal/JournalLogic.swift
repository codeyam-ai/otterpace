import Foundation

// MARK: - Journal pure logic
//
// Lookups, windowing, week grouping, and the bounded coach projection — all
// pure functions over a `[JournalEntry]` with no SwiftUI and no I/O, so every
// rule the coaching engines depend on is directly unit-testable. Split out of
// `JournalEntry.swift` so the data shape and the reasoning over it stay
// separately readable.

public enum Journal {
    /// How many trailing days of entries ride in the coach context.
    public static let coachWindowDays = 14
    /// How much of each note's free text rides in the coach context.
    public static let coachNoteLimit = 200

    /// Entries sorted newest-first. ISO dates sort lexicographically, so plain
    /// string comparison is correct here — dependency-free and testable.
    public static func sorted(_ entries: [JournalEntry]) -> [JournalEntry] {
        entries.sorted { $0.date > $1.date }
    }

    /// The post-run note attached to the workout on `date`, if the runner wrote one.
    public static func entry(forWorkoutOn date: String, in entries: [JournalEntry]) -> JournalEntry? {
        guard !date.isEmpty else { return nil }
        return sorted(entries).first { $0.workoutDate == date }
    }

    /// The standalone daily check-in for `date` — deliberately NOT a post-run
    /// note, so the Today card shows the check-in and the workout card shows its
    /// own note instead of the two surfaces fighting over one entry.
    public static func checkIn(on date: String, in entries: [JournalEntry]) -> JournalEntry? {
        guard !date.isEmpty else { return nil }
        return sorted(entries).first { $0.date == date && !$0.isPostRunNote }
    }

    /// Any entry logged for `date`, check-in or post-run note, newest-first.
    public static func entries(on date: String, in entries: [JournalEntry]) -> [JournalEntry] {
        guard !date.isEmpty else { return [] }
        return sorted(entries).filter { $0.date == date }
    }

    /// The trailing `days`-day slice ending at `today` (inclusive), newest-first.
    /// Entries with an unparseable date are dropped — they can't be placed in a
    /// window — matching how `ActivityHistory.groupByWeek` drops them.
    public static func recent(_ entries: [JournalEntry], asOf today: String, days: Int = coachWindowDays) -> [JournalEntry] {
        guard let end = ActivityHistory.parser.date(from: today) else { return [] }
        let cal = ActivityHistory.calendar
        guard let start = cal.date(byAdding: .day, value: -(max(1, days) - 1), to: end) else { return [] }
        return sorted(entries).filter { e in
            guard let d = ActivityHistory.parser.date(from: e.date) else { return false }
            return d >= start && d <= end
        }
    }

    /// Group entries into Monday-start weeks, newest week first, reusing the exact
    /// UTC/POSIX convention `ActivityHistory.groupByWeek` uses — so journal rows
    /// land in the same weeks the history screen already renders. Keyed by the ISO
    /// Monday that starts the week.
    public static func byWeek(_ entries: [JournalEntry], asOf now: Date = Date()) -> [String: [JournalEntry]] {
        let cal = ActivityHistory.calendar
        let fmt = ActivityHistory.parser
        var buckets: [String: [JournalEntry]] = [:]
        for e in sorted(entries) {
            guard let d = fmt.date(from: e.date),
                  let weekStart = cal.dateInterval(of: .weekOfYear, for: d)?.start else { continue }
            buckets[fmt.string(from: weekStart), default: []].append(e)
        }
        return buckets
    }

    /// The bounded projection that goes in the coach context: the trailing
    /// `coachWindowDays` only, each note truncated to `coachNoteLimit`
    /// characters. `TodayState` already flows through a 16 KB `MAX_CONTEXT_BYTES`
    /// cap in `api/coach.ts`; an unbounded journal would silently push out
    /// `loadHistory` and degrade the very coaching this feature exists to improve.
    public static func coachSlice(_ entries: [JournalEntry], asOf today: String) -> [JournalEntry] {
        recent(entries, asOf: today, days: coachWindowDays).map { e in
            var copy = e
            copy.note = truncate(e.trimmedNote, to: coachNoteLimit)
            return copy
        }
    }

    /// Truncate on a character budget, appending an ellipsis so the coach can see
    /// the text was cut rather than reading a sentence that stops mid-thought.
    static func truncate(_ text: String?, to limit: Int) -> String? {
        guard let text = text, !text.isEmpty else { return nil }
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// Counts + average feel + a dominant-soreness read over the trailing window,
    /// consumed by both `CoachEngine` and `WeeklyReviewEngine`.
    public struct Summary: Equatable {
        public var count: Int
        public var averageFeel: Double?      // nil when nothing was rated
        public var lowFeelDays: Int          // entries rated 2 or below
        public var strongFeelDays: Int       // entries rated 4 or above
        public var soreDays: Int             // entries with sore/painful soreness
        public var poorSleepDays: Int
        /// Distinct DATES carrying a rough signal — a low feel or real soreness.
        /// Counted by day rather than by signal, because one entry that is both
        /// low-feel and sore is still one hard day, and coaching that treats it
        /// as two would soften off a single bad afternoon.
        public var roughDays: Int

        public init(count: Int = 0, averageFeel: Double? = nil, lowFeelDays: Int = 0,
                    strongFeelDays: Int = 0, soreDays: Int = 0, poorSleepDays: Int = 0,
                    roughDays: Int = 0) {
            self.count = count
            self.averageFeel = averageFeel
            self.lowFeelDays = lowFeelDays
            self.strongFeelDays = strongFeelDays
            self.soreDays = soreDays
            self.poorSleepDays = poorSleepDays
            self.roughDays = roughDays
        }
    }

    public static func summary(_ entries: [JournalEntry], asOf today: String, days: Int = 7) -> Summary {
        let window = recent(entries, asOf: today, days: days)
        guard !window.isEmpty else { return Summary() }
        let feels = window.compactMap { $0.feel }
        let avg = feels.isEmpty ? nil : (Double(feels.reduce(0, +)) / Double(feels.count) * 10).rounded() / 10
        return Summary(
            count: window.count,
            averageFeel: avg,
            lowFeelDays: window.filter { ($0.feel ?? 3) <= 2 && $0.feel != nil }.count,
            strongFeelDays: window.filter { ($0.feel ?? 0) >= 4 }.count,
            soreDays: window.filter { $0.soreness?.isElevated == true }.count,
            poorSleepDays: window.filter { $0.sleep == .poor }.count,
            roughDays: Set(window.filter { e in
                (e.feel.map { $0 <= 2 } ?? false) || e.soreness?.isElevated == true
            }.map(\.date)).count
        )
    }
}
