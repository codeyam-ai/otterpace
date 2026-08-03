import SwiftUI

/// Shared copy helpers so the check-in card, the history row, and every
/// accessibility label describe an entry the same way — one place to change how
/// a journal entry reads aloud, instead of three drifting variants.
///
/// Pure (no view state), so the phrasing rules are unit-testable: in particular
/// that an entry only ever mentions what the runner ACTUALLY recorded, and never
/// implies a value they withheld.
enum JournalSpoken {
    struct Chip: Equatable { let text: String; let tint: Color }

    /// The chips an entry actually recorded. Omits anything the runner didn't
    /// say rather than rendering empty slots.
    static func chips(_ entry: JournalEntry) -> [Chip] {
        var out: [Chip] = []
        if let e = entry.energy { out.append(Chip(text: "energy \(e.label)", tint: Palette.go)) }
        if let s = entry.soreness { out.append(Chip(text: s.label, tint: s.isElevated ? Palette.amber : Palette.sky)) }
        if let sl = entry.sleep { out.append(Chip(text: "slept \(sl.label)", tint: Palette.lilac)) }
        return out
    }

    /// A single spoken sentence for VoiceOver, listing only what was recorded.
    static func describe(_ entry: JournalEntry) -> String {
        var parts: [String] = []
        if let feel = entry.feel { parts.append("felt \(FeelSelector.word(for: feel).lowercased()), \(feel) out of 5") }
        if let e = entry.energy { parts.append("energy \(e.label)") }
        if let s = entry.soreness { parts.append(s.label) }
        if let sl = entry.sleep { parts.append("slept \(sl.label)") }
        if let note = entry.trimmedNote { parts.append("note: \(note)") }
        return parts.isEmpty ? "nothing recorded" : parts.joined(separator: ", ")
    }
}
