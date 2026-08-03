import SwiftUI

// The full journal editor, used for BOTH a daily check-in and a post-run note —
// the workout link is simply passed in. Structured chips lead and free text
// follows: chips are one tap on a phone, they're what the coach can reason over
// reliably, and they make an entry possible in three seconds. A journal that
// demands prose gets abandoned in a week.
//
// Presented as a full-cover overlay rather than a sheet, matching Activity
// History and Weekly Review — `fullScreenCover` is unavailable on macOS, and
// launch-seeded overlays need to render complete on the very first frame so a
// capture is never caught mid-transition.
public struct JournalEditorSheet: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var feel: Int?
    @State private var energy: EnergyLevel?
    @State private var soreness: SorenessLevel?
    @State private var sleep: SleepQuality?
    @State private var note: String

    private let entryID: UUID
    private let date: String
    private let workoutDate: String?
    private let workoutType: String?
    private let isExisting: Bool

    var onSave: (JournalEntry) -> Void
    var onDelete: (UUID) -> Void
    var onClose: () -> Void

    /// Open the editor on an existing entry, or on a blank one for `date`.
    /// `workoutDate`/`workoutType` bind the entry to a workout, making it a
    /// post-run note instead of a standalone check-in.
    public init(entry: JournalEntry?,
                date: String,
                workoutDate: String? = nil,
                workoutType: String? = nil,
                onSave: @escaping (JournalEntry) -> Void = { _ in },
                onDelete: @escaping (UUID) -> Void = { _ in },
                onClose: @escaping () -> Void = {}) {
        self.entryID = entry?.id ?? UUID()
        self.date = entry?.date ?? date
        self.workoutDate = entry?.workoutDate ?? workoutDate
        self.workoutType = entry?.workoutType ?? workoutType
        self.isExisting = entry != nil
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
        _feel = State(initialValue: entry?.feel)
        _energy = State(initialValue: entry?.energy)
        _soreness = State(initialValue: entry?.soreness)
        _sleep = State(initialValue: entry?.sleep)
        _note = State(initialValue: entry?.note ?? "")
    }

    private var isPostRunNote: Bool { !(workoutDate ?? "").isEmpty }

    private var title: String {
        isPostRunNote ? "How'd that \(workoutType ?? "run") feel?" : "How'd today feel?"
    }

    private var draft: JournalEntry {
        JournalEntry(id: entryID, date: date, feel: feel, energy: energy,
                     soreness: soreness, sleep: sleep,
                     note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
                     workoutDate: workoutDate, workoutType: workoutType)
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                JournalEditorHeader(
                    date: date,
                    canSave: !draft.isEmpty,
                    onCancel: onClose,
                    onSave: { onSave(draft); onClose() }
                )
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.lg) {
                        Text(title)
                            .font(Typography.title3)
                            .foregroundColor(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        FeelSelector(selection: feel, onSelect: { feel = $0 })

                        JournalChipRow(title: "Energy", options: EnergyLevel.allCases,
                                       label: { $0.label }, tint: Palette.go,
                                       selection: energy, onSelect: { energy = $0 })
                        JournalChipRow(title: "Soreness", options: SorenessLevel.allCases,
                                       label: { $0.label }, tint: Palette.amber,
                                       selection: soreness, onSelect: { soreness = $0 })
                        JournalChipRow(title: "Sleep", options: SleepQuality.allCases,
                                       label: { $0.label }, tint: Palette.lilac,
                                       selection: sleep, onSelect: { sleep = $0 })

                        JournalNoteField(
                            text: $note,
                            subject: isPostRunNote ? "this workout" : "today"
                        )

                        if isExisting {
                            Button(action: { onDelete(entryID); onClose() }) {
                                Text("Delete this entry")
                                    .font(Typography.captionStrong)
                                    .foregroundColor(Palette.amber)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .screenScrollContent()
                }
            }
        }
    }

}
