import Foundation

// MARK: - Account sync opt-ins (two independent, health off by default)
//
// Account-backed sync is OPTIONAL and split into two independent streams so a
// privacy-minded user can sync their settings without ever syncing health data:
//
//   • settingsSyncEnabled — "Sync my settings" (step goal, reminder prefs).
//   • healthSyncEnabled    — "Sync my health & activity data". OFF BY DEFAULT.
//     Because health data is sensitive, enabling it requires passing through a
//     one-time consent moment first (tracked by `healthConsentAcknowledged`),
//     and turning it off can delete the already-uploaded health data.
//
// Both flags live in UserDefaults (no account needed to remember the choice);
// the store is injectable so the gating logic is unit-testable. Scenarios can
// seed the flags via the `rb*` preview keys read in `seededPreview`.
public final class SyncConsentStore {
    private let defaults: UserDefaults

    static let settingsKey = "otterpaceSyncSettingsEnabled"
    static let healthKey = "otterpaceSyncHealthEnabled"
    static let healthConsentKey = "otterpaceSyncHealthConsentAcknowledged"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether settings/preferences sync is on. Default off.
    public var settingsSyncEnabled: Bool {
        defaults.bool(forKey: Self.settingsKey)
    }

    /// Whether health/activity sync is on. Default off — health stays on-device
    /// unless the user explicitly turns this on after consenting.
    public var healthSyncEnabled: Bool {
        defaults.bool(forKey: Self.healthKey)
    }

    /// Whether the user has seen + accepted the one-time health-sync consent
    /// explainer. The UI must require this before the first health push.
    public var healthConsentAcknowledged: Bool {
        defaults.bool(forKey: Self.healthConsentKey)
    }

    public func setSettingsSyncEnabled(_ on: Bool) {
        defaults.set(on, forKey: Self.settingsKey)
    }

    /// Record that the user accepted the health-sync consent explainer. Enabling
    /// health sync is only valid once this is true (enforced at the call site).
    public func acknowledgeHealthConsent() {
        defaults.set(true, forKey: Self.healthConsentKey)
    }

    /// Turn health sync on. No-ops unless consent was acknowledged first, so a
    /// health push can never happen without the user passing through consent.
    @discardableResult
    public func setHealthSyncEnabled(_ on: Bool) -> Bool {
        if on && !healthConsentAcknowledged { return false }
        defaults.set(on, forKey: Self.healthKey)
        return true
    }

    /// Forget both opt-ins (e.g. on account deletion) — back to local-only.
    public func reset() {
        defaults.removeObject(forKey: Self.settingsKey)
        defaults.removeObject(forKey: Self.healthKey)
        defaults.removeObject(forKey: Self.healthConsentKey)
    }

    /// Scenario/preview seed: a captured scenario can pre-set the toggle states
    /// via `rbSyncSettings` / `rbSyncHealth` so the Settings account UI renders
    /// in a given sync state. No-op in production (those keys are absent).
    public func applySeededPreviewIfPresent() {
        if defaults.object(forKey: "rbSyncSettings") != nil {
            setSettingsSyncEnabled(defaults.bool(forKey: "rbSyncSettings"))
        }
        if defaults.object(forKey: "rbSyncHealth") != nil {
            // Treat a seeded health-on state as already consented so previews render.
            if defaults.bool(forKey: "rbSyncHealth") { acknowledgeHealthConsent() }
            defaults.set(defaults.bool(forKey: "rbSyncHealth"), forKey: Self.healthKey)
        }
    }
}
