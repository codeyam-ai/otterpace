import SwiftUI

// MARK: - Import a race from the web
//
// Two sheets presented from the Settings Races card that create a race without
// hand-typing every field:
//
//   RaceImportSheet — paste a race's URL; the backend extracts a structured race.
//   RaceSearchSheet — type a race name; pick from candidate results.
//
// Both funnel into `RaceEditorView` pre-filled (via `onPrefill`), so the user
// always confirms and edits before saving — we never auto-save a machine-extracted
// race. Both reuse the BYO Anthropic key (`CoachKeyStore`) and degrade like
// `AskCoachView`: with no key or on any failure, the sheet offers manual entry.

/// Paste-a-URL import. On success it hands a prefilled `RaceGoal` seed plus the
/// list of fields the extractor was unsure about back to the caller.
struct RaceImportSheet: View {
    var onPrefill: (RaceGoal, [String]) -> Void
    var onManual: () -> Void
    var onCancel: () -> Void

    private let keyStore = CoachKeyStore()
    private let client = RaceImportClient()

    @State private var url: String = ""
    @State private var working = false
    @State private var errText: String?

    private var canImport: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working
    }

    /// The input form is shown when the user has connected a key, or when a
    /// scenario opts in via `rbCoachConnected` (so the populated form is
    /// capturable offline without a real key — mirrors `AskCoachView.chatUnlocked`).
    /// `runImport` still requires a real key and falls back to manual entry without one.
    private var unlocked: Bool {
        keyStore.key != nil || UserDefaults.standard.bool(forKey: "rbCoachConnected")
    }

    var body: some View {
        RaceImportScaffold(title: "Import from URL", onCancel: onCancel) {
            if !unlocked {
                RaceImportNoKey(action: "Importing", onManual: onManual)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Paste a race's web page and Buddy will pull in the name, date, distance and location for you to confirm.")
                        .font(Typography.callout).foregroundColor(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("https://…", text: $url)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                    Button(action: runImport) {
                        HStack(spacing: 8) {
                            if working { ProgressView() }
                            Text(working ? "Importing…" : "Import race")
                                .font(Typography.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(canImport ? Palette.brand : Palette.ink.opacity(0.12)))
                        .foregroundColor(canImport ? .white : Palette.subtle)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canImport)

                    if let errText {
                        Text(errText).font(Typography.caption).foregroundColor(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Add manually instead", action: onManual)
                            .font(Typography.headline).foregroundColor(Palette.brandDeep)
                    }
                }
            }
        }
    }

    private func runImport() {
        guard let apiKey = keyStore.key else { onManual(); return }
        let link = url.trimmingCharacters(in: .whitespacesAndNewlines)
        errText = nil
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                let result = try await client.importRace(from: link, apiKey: apiKey)
                // Fields the extractor couldn't find, plus a low overall confidence,
                // are what the editor flags for the user to double-check.
                var flagged = result.missingFields
                if result.confidence < 0.6 {
                    for f in ["name", "date", "distanceMiles", "location"] where !flagged.contains(f) {
                        flagged.append(f)
                    }
                }
                onPrefill(result.race.asRaceGoalSeed, flagged)
            } catch CoachError.invalidKey {
                errText = "Your AI coach key was rejected. Reconnect it in Settings, then try again."
            } catch {
                errText = "Couldn't import that race. Check the link, or add it manually."
            }
        }
    }
}

/// Search-by-name. Lists candidates; tapping one hands its draft to the caller to
/// open the editor pre-filled.
struct RaceSearchSheet: View {
    var onPrefill: (RaceGoal, [String]) -> Void
    var onManual: () -> Void
    var onCancel: () -> Void

    private let keyStore = CoachKeyStore()
    private let client = RaceImportClient()

    @State private var query: String = ""
    @State private var results: [RaceSearchResult] = []
    @State private var working = false
    @State private var searched = false
    @State private var errText: String?

    private var canSearch: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !working
    }

    /// Input shown with a connected key, or when a scenario opts in via
    /// `rbCoachConnected` (see `RaceImportSheet.unlocked`).
    private var unlocked: Bool {
        keyStore.key != nil || UserDefaults.standard.bool(forKey: "rbCoachConnected")
    }

    var body: some View {
        RaceImportScaffold(title: "Search online", onCancel: onCancel) {
            if !unlocked {
                RaceImportNoKey(action: "Searching", onManual: onManual)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Type a race name and pick from the matches. You can confirm and edit the details before saving.")
                        .font(Typography.callout).foregroundColor(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("e.g. Cascade Marathon", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { if canSearch { runSearch() } }
                        Button(action: runSearch) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(canSearch ? .white : Palette.subtle)
                                .padding(10)
                                .background(Circle().fill(canSearch ? Palette.brand : Palette.ink.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSearch)
                        .accessibilityLabel("Search races")
                    }

                    if working {
                        HStack(spacing: 8) { ProgressView(); Text("Searching…").font(Typography.caption).foregroundColor(Palette.subtle) }
                    } else if let errText {
                        Text(errText).font(Typography.caption).foregroundColor(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Add manually instead", action: onManual)
                            .font(Typography.headline).foregroundColor(Palette.brandDeep)
                    } else if searched && results.isEmpty {
                        Text("No matches found. Try a different name, or add the race manually.")
                            .font(Typography.caption).foregroundColor(Palette.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Add manually instead", action: onManual)
                            .font(Typography.headline).foregroundColor(Palette.brandDeep)
                    } else {
                        ForEach(results) { result in
                            Button { onPrefill(result.asDraft.asRaceGoalSeed, missingFields(for: result)) } label: {
                                candidateRow(result)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func candidateRow(_ r: RaceSearchResult) -> some View {
        let bits = [r.date.map(prettyDate), r.location].compactMap { $0 }.filter { !$0.isEmpty }
        return HStack(spacing: 12) {
            Image(systemName: "flag.checkered").foregroundColor(Palette.brand).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(Typography.body).foregroundColor(Palette.ink)
                if !bits.isEmpty {
                    Text(bits.joined(separator: " · ")).font(Typography.caption).foregroundColor(Palette.subtle).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(Palette.subtle)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// Which fields the editor should flag for a picked candidate — the ones the
    /// search didn't provide, so the user fills them in.
    private func missingFields(for r: RaceSearchResult) -> [String] {
        var missing: [String] = []
        if r.date == nil || r.date?.isEmpty == true { missing.append("date") }
        if r.distanceMiles == nil { missing.append("distanceMiles") }
        if r.location == nil || r.location?.isEmpty == true { missing.append("location") }
        return missing
    }

    private func runSearch() {
        guard let apiKey = keyStore.key else { onManual(); return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        errText = nil
        working = true
        Task { @MainActor in
            defer { working = false; searched = true }
            do {
                results = try await client.searchRaces(query: q, apiKey: apiKey)
            } catch CoachError.invalidKey {
                errText = "Your AI coach key was rejected. Reconnect it in Settings, then try again."
            } catch {
                errText = "Couldn't search right now. Check your connection, or add the race manually."
            }
        }
    }

    private func prettyDate(_ iso: String) -> String {
        guard let d = Self.iso.date(from: iso) else { return iso }
        return Self.pretty.string(from: d)
    }
    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    private static let pretty: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
}

// MARK: - Shared chrome

/// Header + gradient + scroll shell so both sheets look native and match the app.
private struct RaceImportScaffold<Content: View>: View {
    let title: String
    var onCancel: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel", action: onCancel)
                        .font(Typography.headline).foregroundColor(Palette.subtle)
                    Spacer()
                    Text(title).font(Typography.title3).foregroundColor(Palette.ink)
                    Spacer()
                    // Balance the Cancel button so the title stays centered.
                    Text("Cancel").font(Typography.headline).opacity(0)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                Divider().opacity(0.4)
                ScrollView {
                    content().padding(20)
                }
            }
        }
    }
}

/// The no-key state: mirrors AskCoachView's locked state — explain, and offer the
/// manual path so the user is never blocked.
private struct RaceImportNoKey: View {
    /// The sheet-specific verb ("Importing" / "Searching") so the two sheets'
    /// no-key states read distinctly instead of sharing identical copy.
    let action: String
    var onManual: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundColor(Palette.brand)
                Text("Connect an AI coach key first").font(Typography.headline).foregroundColor(Palette.ink)
            }
            Text("\(action) races from the web uses your Anthropic API key. Connect one in the AI Coach section of Settings, or add a race manually.")
                .font(Typography.callout).foregroundColor(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a race manually", action: onManual)
                .font(Typography.headline).foregroundColor(Palette.brandDeep)
        }
    }
}
