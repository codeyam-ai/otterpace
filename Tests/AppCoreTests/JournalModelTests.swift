import XCTest
@testable import AppCore

/// The model-level journal mutators — the logic the Today card and the editor
/// drive. Covered here rather than through the views because a native stack has
/// no DOM to click, so this IS the interaction test.
@MainActor
final class JournalModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let today = "2026-06-22"

    override func setUp() {
        super.setUp()
        suiteName = "JournalModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func model(_ journal: [JournalEntry] = []) -> OtterpaceModel {
        OtterpaceModel(today: TodayState(healthKitConnected: true, date: today, journal: journal),
                       defaults: defaults)
    }

    // MARK: quickFeel

    func testQuickFeelCreatesTodaysCheckIn() {
        let m = model()
        m.quickFeel(4, on: today)

        XCTAssertEqual(m.today.journal.count, 1)
        XCTAssertEqual(m.today.journal.first?.feel, 4)
        XCTAssertEqual(m.today.journal.first?.date, today)
        XCTAssertFalse(m.today.journal.first?.isPostRunNote ?? true)
    }

    func testQuickFeelPersistsThroughTheStore() {
        let m = model()
        m.quickFeel(4, on: today)
        XCTAssertEqual(JournalStore.load(defaults).first?.feel, 4)
    }

    func testQuickFeelPreservesEverythingElseAlreadyLogged() {
        // The regression this method exists to prevent: re-tapping the feel row
        // must not wipe the chips and note the runner already recorded.
        let existing = JournalEntry(date: today, feel: 2, energy: .low, soreness: .sore,
                                    sleep: .poor, note: "calves tight")
        JournalStore.save([existing], defaults)
        let m = model([existing])

        m.quickFeel(5, on: today)

        XCTAssertEqual(m.today.journal.count, 1, "it updates the entry rather than adding one")
        let e = m.today.journal.first
        XCTAssertEqual(e?.id, existing.id)
        XCTAssertEqual(e?.feel, 5)
        XCTAssertEqual(e?.energy, .low)
        XCTAssertEqual(e?.soreness, .sore)
        XCTAssertEqual(e?.sleep, .poor)
        XCTAssertEqual(e?.note, "calves tight")
    }

    func testQuickFeelIgnoresAPostRunNoteOnTheSameDay() {
        // A note about this morning's run is not today's check-in; tapping the
        // Today card must start a check-in, not overwrite the run's note.
        let runNote = JournalEntry(date: today, feel: 3, note: "felt fine",
                                   workoutDate: today, workoutType: "run")
        JournalStore.save([runNote], defaults)
        let m = model([runNote])

        m.quickFeel(5, on: today)

        XCTAssertEqual(m.today.journal.count, 2)
        XCTAssertEqual(Journal.entry(forWorkoutOn: today, in: m.today.journal)?.note, "felt fine")
        XCTAssertEqual(Journal.checkIn(on: today, in: m.today.journal)?.feel, 5)
    }

    // MARK: saveJournalEntry / delete

    func testSavingABlankEntryIsDiscarded() {
        let m = model()
        m.saveJournalEntry(JournalEntry(date: today))
        XCTAssertTrue(m.today.journal.isEmpty, "an empty entry must not become a hollow row")
    }

    func testSaveThenDeleteRoundTrips() {
        let m = model()
        let entry = JournalEntry(date: today, feel: 3, note: "a line")
        m.saveJournalEntry(entry)
        XCTAssertEqual(m.today.journal.count, 1)

        m.deleteJournalEntry(id: entry.id)
        XCTAssertTrue(m.today.journal.isEmpty)
        XCTAssertTrue(JournalStore.load(defaults).isEmpty)
    }

    func testDeleteAllClearsBothTheModelAndTheStore() {
        let m = model()
        m.saveJournalEntry(JournalEntry(date: today, feel: 3))
        m.saveJournalEntry(JournalEntry(date: "2026-06-21", feel: 4))
        XCTAssertEqual(m.today.journal.count, 2)

        m.deleteAllJournalEntries()
        XCTAssertTrue(m.today.journal.isEmpty)
        XCTAssertTrue(JournalStore.load(defaults).isEmpty)
    }

    // MARK: Seed path

    func testReadStateDecodesTheSeededJournal() {
        defaults.set("2026-06-22", forKey: "rbDate")
        defaults.set(#"[{"date":"2026-06-22","feel":4,"note":"seeded"}]"#, forKey: "rbJournalJSON")

        let state = OtterpaceModel.readState(defaults: defaults)
        XCTAssertEqual(state.journal.count, 1)
        XCTAssertEqual(state.journal.first?.note, "seeded")
    }

    func testReadStateWithNoSeededJournalIsEmpty() {
        defaults.set("2026-06-22", forKey: "rbDate")
        XCTAssertTrue(OtterpaceModel.readState(defaults: defaults).journal.isEmpty)
    }

    func testReadStateSurvivesACorruptSeededJournal() {
        defaults.set("2026-06-22", forKey: "rbDate")
        defaults.set("{ not json", forKey: "rbJournalJSON")
        XCTAssertTrue(OtterpaceModel.readState(defaults: defaults).journal.isEmpty,
                      "a bad seed yields no entries rather than crashing the capture")
    }
}
