import SwiftUI

// Lightweight add/edit editor for a single race, presented as a sheet from the
// Settings Races card. Distance uses the same preset-capsules + custom-stepper
// pattern as the daily step goal. Reuses the app theme so it feels native.
struct RaceEditorView: View {
    let existing: RaceGoal?
    var onSave: (RaceGoal) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var distance: RaceDistance
    @State private var customValue: String
    @State private var customUnit: DistanceUnit
    @State private var date: Date
    @State private var location: String
    @State private var notes: String

    init(existing: RaceGoal?, onSave: @escaping (RaceGoal) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        let miles = existing?.distanceMiles ?? RaceDistance.half.miles
        let preset = RaceDistance.preset(forMiles: miles)
        _name = State(initialValue: existing?.name ?? "")
        // Clamp the initial date to today's floor so the bounded picker (which
        // rejects past dates) always opens on a valid selection — editing a
        // now-past race nudges it forward rather than crashing the range.
        _date = State(initialValue: max(Self.parseISO(existing?.date) ?? Date(), Self.startOfToday))
        _location = State(initialValue: existing?.location ?? "")
        _notes = State(initialValue: existing?.notes ?? "")

        // Scenario hook: when adding, a scenario can seed `rbRaceEditorCustomValue`
        // (+ optional `rbRaceEditorCustomUnit` = "km"/"mi") to open the editor
        // directly on the Custom option, so the typed-distance UI is capturable in
        // the live preview. Normal use falls through to the preset selection.
        let defs = UserDefaults.standard
        if existing == nil, let seeded = defs.string(forKey: "rbRaceEditorCustomValue"), !seeded.isEmpty {
            let unitStr = defs.string(forKey: "rbRaceEditorCustomUnit") ?? "mi"
            _distance = State(initialValue: .custom)
            _customValue = State(initialValue: seeded)
            _customUnit = State(initialValue: (unitStr == "km" || unitStr == "kilometers") ? .kilometers : .miles)
        } else if let existing, existing.unit == .kilometers {
            // Editing a km-entered race: reopen on Custom in km so the entered value is honored.
            let km = RaceGoal.oneDecimal(existing.distanceMiles * RaceDistance.kmPerMile)
            _distance = State(initialValue: .custom)
            _customValue = State(initialValue: RaceGoal.number(km))
            _customUnit = State(initialValue: .kilometers)
        } else {
            _distance = State(initialValue: preset)
            _customValue = State(initialValue: Self.formatMiles(RaceDistance.clampMiles(miles)))
            _customUnit = State(initialValue: .miles)
        }
    }

    /// The typed custom distance resolved to clamped miles, or nil when the field
    /// is empty or not a positive number.
    private var parsedCustomMiles: Double? {
        guard let v = Double(customValue.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return RaceDistance.miles(from: v, unit: customUnit)
    }
    private var resolvedMiles: Double {
        distance == .custom ? (parsedCustomMiles ?? RaceDistance.minMiles) : distance.miles
    }
    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if distance == .custom { return parsedCustomMiles != nil }
        return true
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        field("Race name") {
                            TextField("e.g. October Trail Half", text: $name).textFieldStyle(.roundedBorder)
                        }
                        field("Distance") {
                            distanceCapsules
                            if distance == .custom {
                                HStack(spacing: 10) {
                                    TextField("Distance", text: $customValue)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                        .accessibilityLabel("Custom race distance")
                                    Picker("Unit", selection: $customUnit) {
                                        ForEach(DistanceUnit.allCases, id: \.self) { u in
                                            Text(u.label).tag(u)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 108)
                                    .accessibilityLabel("Distance unit")
                                }
                                if customUnit == .kilometers, let mi = parsedCustomMiles {
                                    Text(String(format: "≈ %.1f mi", mi))
                                        .font(Typography.caption2).foregroundColor(Palette.subtle)
                                }
                            }
                        }
                        field("Date") {
                            // Floor the picker at today: a race is an *upcoming* goal,
                            // so a past date can't be entered (which would strand the
                            // Today banner and race coaching in a dead state).
                            DatePicker("", selection: $date, in: Self.startOfToday..., displayedComponents: .date)
                                .labelsHidden()
                        }
                        field("Location") {
                            TextField("City or venue", text: $location).textFieldStyle(.roundedBorder)
                        }
                        field("Notes (optional)") {
                            TextField("Corral, goal time, start area…", text: $notes).textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(Typography.headline).foregroundColor(Palette.subtle)
            Spacer()
            Text(existing == nil ? "Add race" : "Edit race")
                .font(Typography.title3).foregroundColor(Palette.ink)
            Spacer()
            Button("Save") {
                onSave(RaceGoal(
                    id: existing?.id ?? UUID(),
                    name: name.trimmingCharacters(in: .whitespaces),
                    distanceMiles: resolvedMiles,
                    date: Self.isoString(date),
                    location: location.trimmingCharacters(in: .whitespaces),
                    notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
                    unit: distance == .custom ? customUnit : .miles
                ))
            }
            .font(Typography.headline)
            .foregroundColor(canSave ? Palette.brandDeep : Palette.subtle)
            .disabled(!canSave)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var distanceCapsules: some View {
        HStack(spacing: 8) {
            ForEach(RaceDistance.allCases, id: \.self) { d in
                Button { distance = d } label: {
                    Text(d.label)
                        .font(Typography.captionStrong)
                        .foregroundColor(distance == d ? .white : Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(distance == d ? Palette.brand : Palette.ink.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.label)
                .accessibilityAddTraits(distance == d ? [.isSelected] : [])
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(Typography.caption2).foregroundColor(Palette.subtle)
            content()
        }
    }

    // Start of the current day in the local calendar — the minimum selectable
    // race date, matching the day-granularity the picker displays.
    private static var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }

    // Compact miles string for prefill (8.0 -> "8", 13.1 -> "13.1").
    private static func formatMiles(_ m: Double) -> String { String(format: "%g", m) }

    // ISO yyyy-MM-dd <-> Date, UTC, matching RaceGoal.date / LatestWorkout.date.
    private static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFormatter.date(from: s)
    }
    private static func isoString(_ d: Date) -> String { isoFormatter.string(from: d) }
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
