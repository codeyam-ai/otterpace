import Foundation

// MARK: - On-device journal store (JSON array under one key)
//
// The same shape as `RaceStore`: one UserDefaults key holding a JSON array, an
// injectable `defaults` so tests use an isolated suite, and a `load` that returns
// `[]` rather than throwing on empty or corrupt data — a decode failure should
// never crash the app or lose the surrounding UI, and a user who somehow ends up
// with a bad blob gets an empty journal they can write into again.

public enum JournalStore {
    static let key = "otterpaceJournalEntries"

    public static func load(_ d: UserDefaults = .standard) -> [JournalEntry] {
        guard let json = d.string(forKey: key), !json.isEmpty,
              let data = json.data(using: .utf8),
              let entries = try? JSONDecoder().decode([JournalEntry].self, from: data)
        else { return [] }
        return Journal.sorted(entries)
    }

    public static func save(_ entries: [JournalEntry], _ d: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Journal.sorted(entries)),
              let json = String(data: data, encoding: .utf8) else { return }
        d.set(json, forKey: key)
    }

    /// Insert or replace by id, returning the updated list. Replacing by id is
    /// what lets the editor reopen an entry, change it, and save without
    /// stacking duplicates on the timeline.
    @discardableResult
    public static func upsert(_ entry: JournalEntry, _ d: UserDefaults = .standard) -> [JournalEntry] {
        var entries = load(d)
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }
        save(entries, d)
        return Journal.sorted(entries)
    }

    @discardableResult
    public static func delete(id: UUID, _ d: UserDefaults = .standard) -> [JournalEntry] {
        let entries = load(d).filter { $0.id != id }
        save(entries, d)
        return entries
    }

    /// Remove every entry. Because the journal is on-device with no sync, there
    /// is no server-side delete to lean on — without this the only way to clear
    /// it would be to delete the app. A feature that invites people to write down
    /// how they really felt owes them an eraser.
    public static func clear(_ d: UserDefaults = .standard) {
        d.removeObject(forKey: key)
    }
}
