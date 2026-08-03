import XCTest
@testable import AppCore

/// Pure-logic coverage for the journal: lookups, week grouping, tolerant decode,
/// and — most importantly — the explicit assertions that `coachSlice` bounds BOTH
/// the day window and the per-note length. That bound is the thing standing
/// between a long-running journal and a coach context that silently drops
/// `loadHistory`, so it gets tested rather than hoped for.
final class JournalTests: XCTestCase {

    private let today = "2026-06-22"

    private func entry(_ date: String, feel: Int? = nil, soreness: SorenessLevel? = nil,
                       sleep: SleepQuality? = nil, note: String? = nil,
                       workoutDate: String? = nil, workoutType: String? = nil) -> JournalEntry {
        JournalEntry(date: date, feel: feel, soreness: soreness, sleep: sleep,
                     note: note, workoutDate: workoutDate, workoutType: workoutType)
    }

    // MARK: Lookups

    func testEntryForWorkoutFindsOnlyThePostRunNote() {
        let note = entry("2026-06-22", feel: 4, note: "clicked after mile one",
                         workoutDate: "2026-06-22", workoutType: "run")
        let checkIn = entry("2026-06-22", feel: 2)
        let found = Journal.entry(forWorkoutOn: "2026-06-22", in: [checkIn, note])
        XCTAssertEqual(found?.id, note.id)
    }

    func testCheckInExcludesPostRunNotes() {
        // A day with ONLY a post-run note has no standalone check-in — the Today
        // card must show its prompt rather than borrowing the run's note.
        let note = entry("2026-06-22", feel: 4, workoutDate: "2026-06-22", workoutType: "run")
        XCTAssertNil(Journal.checkIn(on: "2026-06-22", in: [note]))

        let checkIn = entry("2026-06-22", feel: 3)
        XCTAssertEqual(Journal.checkIn(on: "2026-06-22", in: [note, checkIn])?.id, checkIn.id)
    }

    func testLookupsOnEmptyDateReturnNothing() {
        let e = entry("2026-06-22", feel: 3)
        XCTAssertNil(Journal.entry(forWorkoutOn: "", in: [e]))
        XCTAssertNil(Journal.checkIn(on: "", in: [e]))
    }

    // MARK: Recency window

    func testRecentIsInclusiveOfBothEnds() {
        let entries = [entry("2026-06-22"), entry("2026-06-16"), entry("2026-06-15")]
        let window = Journal.recent(entries, asOf: today, days: 7)
        XCTAssertEqual(window.map(\.date), ["2026-06-22", "2026-06-16"],
                       "a 7-day window ending 06-22 covers 06-16 through 06-22")
    }

    func testRecentDropsUnparseableDates() {
        let entries = [entry("2026-06-22"), entry("not-a-date")]
        XCTAssertEqual(Journal.recent(entries, asOf: today, days: 14).count, 1)
    }

    func testRecentReturnsNewestFirst() {
        let entries = [entry("2026-06-18"), entry("2026-06-22"), entry("2026-06-20")]
        XCTAssertEqual(Journal.recent(entries, asOf: today, days: 14).map(\.date),
                       ["2026-06-22", "2026-06-20", "2026-06-18"])
    }

    // MARK: Week grouping

    func testByWeekUsesTheSameMondayStartWeeksAsActivityHistory() {
        // 2026-06-22 is a Monday; 2026-06-21 is the Sunday closing the prior week.
        let grouped = Journal.byWeek([entry("2026-06-22"), entry("2026-06-21")],
                                     asOf: ActivityHistory.referenceDate(fromISO: today))
        XCTAssertEqual(grouped["2026-06-22"]?.count, 1)
        XCTAssertEqual(grouped["2026-06-15"]?.count, 1)
    }

    func testByWeekDropsUnparseableDates() {
        let grouped = Journal.byWeek([entry("nope")], asOf: ActivityHistory.referenceDate(fromISO: today))
        XCTAssertTrue(grouped.isEmpty)
    }

    // MARK: Coach slice — the bound that protects the context budget

    func testCoachSliceTruncatesTheDayWindow() {
        let inside = entry("2026-06-09")   // exactly 14 days back, inclusive
        let outside = entry("2026-06-08")  // one day too far
        let slice = Journal.coachSlice([inside, outside], asOf: today)
        XCTAssertEqual(slice.map(\.date), ["2026-06-09"])
    }

    func testCoachSliceTruncatesEachNoteToTheCharacterCap() {
        let long = String(repeating: "a", count: Journal.coachNoteLimit + 50)
        let slice = Journal.coachSlice([entry("2026-06-22", note: long)], asOf: today)
        let note = try? XCTUnwrap(slice.first?.note)
        XCTAssertEqual(note?.count, Journal.coachNoteLimit + 1, "capped text plus the ellipsis")
        XCTAssertTrue(note?.hasSuffix("…") == true, "truncation is visible, not silent")
    }

    func testCoachSliceLeavesShortNotesIntact() {
        let slice = Journal.coachSlice([entry("2026-06-22", note: "short and honest")], asOf: today)
        XCTAssertEqual(slice.first?.note, "short and honest")
    }

    func testCoachSliceDropsWhitespaceOnlyNotes() {
        let slice = Journal.coachSlice([entry("2026-06-22", feel: 3, note: "   \n ")], asOf: today)
        XCTAssertNil(slice.first?.note)
    }

    // MARK: Summary

    func testSummaryCountsFeelSorenessAndSleep() {
        let entries = [
            entry("2026-06-22", feel: 2, soreness: .sore, sleep: .poor),
            entry("2026-06-21", feel: 5, soreness: .none, sleep: .good),
            entry("2026-06-20", feel: 1, soreness: .painful, sleep: .poor),
        ]
        let s = Journal.summary(entries, asOf: today, days: 7)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.averageFeel, 2.7)
        XCTAssertEqual(s.lowFeelDays, 2)
        XCTAssertEqual(s.strongFeelDays, 1)
        XCTAssertEqual(s.soreDays, 2)
        XCTAssertEqual(s.poorSleepDays, 2)
        XCTAssertEqual(s.roughDays, 2, "06-22 and 06-20; the strong 06-21 is not rough")
    }

    func testRoughDaysCountsDaysNotSignals() {
        // One entry that is BOTH low-feel and sore is still one hard day.
        // Counting it as two would let a single bad afternoon soften coaching.
        let s = Journal.summary([entry("2026-06-22", feel: 2, soreness: .sore)], asOf: today)
        XCTAssertEqual(s.lowFeelDays, 1)
        XCTAssertEqual(s.soreDays, 1)
        XCTAssertEqual(s.roughDays, 1)
    }

    func testRoughDaysDeduplicatesTwoEntriesOnTheSameDate() {
        // A check-in and a post-run note on the same rough day are one day.
        let s = Journal.summary([
            entry("2026-06-22", feel: 2),
            entry("2026-06-22", feel: 1, workoutDate: "2026-06-22", workoutType: "run"),
        ], asOf: today)
        XCTAssertEqual(s.roughDays, 1)
    }

    func testSummaryOfAnEmptyJournalIsAllZero() {
        XCTAssertEqual(Journal.summary([], asOf: today), Journal.Summary())
    }

    func testSummaryAverageIsNilWhenNothingWasRated() {
        let s = Journal.summary([entry("2026-06-22", soreness: .mild)], asOf: today)
        XCTAssertEqual(s.count, 1)
        XCTAssertNil(s.averageFeel, "no rating is not a zero rating")
    }

    // MARK: Tolerant decode

    func testDecodesPayloadMissingTheNewerFields() throws {
        // The shape an entry might have been persisted with before the chip
        // fields existed: date and note only.
        let json = #"[{"id":"3F2A1C40-1111-4A01-9F01-0000000000A1","date":"2026-06-22","note":"just a line"}]"#
        let decoded = try JSONDecoder().decode([JournalEntry].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].note, "just a line")
        XCTAssertNil(decoded[0].feel)
        XCTAssertNil(decoded[0].energy)
        XCTAssertNil(decoded[0].soreness)
        XCTAssertNil(decoded[0].sleep)
        XCTAssertFalse(decoded[0].isPostRunNote)
    }

    func testDecodeClampsAnOutOfRangeFeel() throws {
        let json = #"[{"date":"2026-06-22","feel":9}]"#
        let decoded = try JSONDecoder().decode([JournalEntry].self, from: Data(json.utf8))
        XCTAssertEqual(decoded[0].feel, 5)
    }

    func testRoundTripsThroughCodable() throws {
        let original = entry("2026-06-22", feel: 4, soreness: .mild, sleep: .okay,
                             note: "clicked after mile one",
                             workoutDate: "2026-06-22", workoutType: "run")
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([JournalEntry].self, from: data)
        XCTAssertEqual(decoded, [original])
    }

    // MARK: Entry semantics

    func testIsEmptyOnlyWhenNothingWasRecorded() {
        XCTAssertTrue(entry("2026-06-22").isEmpty)
        XCTAssertTrue(entry("2026-06-22", note: "   ").isEmpty, "whitespace is not content")
        XCTAssertFalse(entry("2026-06-22", feel: 3).isEmpty)
        XCTAssertFalse(entry("2026-06-22", note: "a line").isEmpty)
    }

    func testIsPostRunNoteRequiresANonEmptyWorkoutDate() {
        XCTAssertFalse(entry("2026-06-22", workoutDate: "").isPostRunNote)
        XCTAssertTrue(entry("2026-06-22", workoutDate: "2026-06-22").isPostRunNote)
    }
}
