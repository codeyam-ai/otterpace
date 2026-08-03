import XCTest
@testable import AppCore

/// Persistence coverage for the journal, mirroring `RaceImportPersistenceTests`:
/// round-trip, upsert-replaces-by-id, delete, delete-all, and — the one that
/// matters most — an empty or corrupt stored value decoding to `[]` rather than
/// throwing. A decode failure must never cost a user the rest of their app.
final class JournalStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "JournalStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLoadOnAnUntouchedStoreIsEmpty() {
        XCTAssertEqual(JournalStore.load(defaults), [])
    }

    func testSaveThenLoadRoundTrips() {
        let entry = JournalEntry(date: "2026-06-22", feel: 4, energy: .good,
                                 soreness: .mild, sleep: .okay,
                                 note: "Legs were heavy the first mile.",
                                 workoutDate: "2026-06-22", workoutType: "run")
        JournalStore.save([entry], defaults)
        XCTAssertEqual(JournalStore.load(defaults), [entry])
    }

    func testLoadReturnsNewestFirst() {
        JournalStore.save([JournalEntry(date: "2026-06-18"),
                           JournalEntry(date: "2026-06-22"),
                           JournalEntry(date: "2026-06-20")], defaults)
        XCTAssertEqual(JournalStore.load(defaults).map(\.date),
                       ["2026-06-22", "2026-06-20", "2026-06-18"])
    }

    func testUpsertReplacesById() {
        var entry = JournalEntry(date: "2026-06-22", feel: 2)
        JournalStore.upsert(entry, defaults)
        entry.feel = 5
        entry.note = "turned it around"
        let result = JournalStore.upsert(entry, defaults)

        XCTAssertEqual(result.count, 1, "editing an entry must not stack a duplicate")
        XCTAssertEqual(result.first?.feel, 5)
        XCTAssertEqual(JournalStore.load(defaults).first?.note, "turned it around")
    }

    func testUpsertAppendsADistinctEntry() {
        JournalStore.upsert(JournalEntry(date: "2026-06-22", feel: 3), defaults)
        let result = JournalStore.upsert(JournalEntry(date: "2026-06-21", feel: 4), defaults)
        XCTAssertEqual(result.count, 2)
    }

    func testDeleteRemovesOnlyTheNamedEntry() {
        let keep = JournalEntry(date: "2026-06-22", feel: 3)
        let drop = JournalEntry(date: "2026-06-21", feel: 4)
        JournalStore.save([keep, drop], defaults)

        let result = JournalStore.delete(id: drop.id, defaults)
        XCTAssertEqual(result, [keep])
        XCTAssertEqual(JournalStore.load(defaults), [keep])
    }

    func testDeleteOfAnUnknownIdIsANoOp() {
        let entry = JournalEntry(date: "2026-06-22", feel: 3)
        JournalStore.save([entry], defaults)
        XCTAssertEqual(JournalStore.delete(id: UUID(), defaults), [entry])
    }

    func testClearEmptiesTheStoreAndLoadStillReturnsEmpty() {
        JournalStore.save([JournalEntry(date: "2026-06-22", feel: 3),
                           JournalEntry(date: "2026-06-21", feel: 4)], defaults)
        JournalStore.clear(defaults)
        XCTAssertEqual(JournalStore.load(defaults), [],
                       "a subsequent load returns empty rather than throwing")
    }

    func testEmptyStringDecodesToEmptyRatherThanThrowing() {
        defaults.set("", forKey: JournalStore.key)
        XCTAssertEqual(JournalStore.load(defaults), [])
    }

    func testCorruptValueDecodesToEmptyRatherThanThrowing() {
        defaults.set("{ not json at all", forKey: JournalStore.key)
        XCTAssertEqual(JournalStore.load(defaults), [])
    }

    func testWrongShapeDecodesToEmptyRatherThanThrowing() {
        // A JSON object where an array is expected — the shape a bad migration
        // or a hand-edited value might leave behind.
        defaults.set(#"{"date":"2026-06-22"}"#, forKey: JournalStore.key)
        XCTAssertEqual(JournalStore.load(defaults), [])
    }
}
