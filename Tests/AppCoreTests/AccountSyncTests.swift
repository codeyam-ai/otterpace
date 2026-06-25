import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
//
// Covers the optional account-sync layer's gating + merge logic without a live
// backend, via a spy transport. The privacy-critical guarantees are explicit:
// guests never sync, and health never uploads while the health opt-in is off.
final class AccountSyncTests: XCTestCase {

    // Records every call so tests can assert what did / didn't reach the network.
    private final class SpyTransport: AccountSyncTransport {
        var prefsPushes: [(userID: String, payload: SyncablePreferences, updatedAt: Date)] = []
        var healthPushes: [(userID: String, payload: SyncableHealthSnapshot, updatedAt: Date)] = []
        var healthDeletes: [String] = []
        var remotePrefs: TimestampedPayload<SyncablePreferences>?

        func fetchPrefs(userID: String) async throws -> TimestampedPayload<SyncablePreferences>? { remotePrefs }
        func pushPrefs(userID: String, payload: SyncablePreferences, updatedAt: Date) async throws {
            prefsPushes.append((userID, payload, updatedAt))
        }
        func fetchHealth(userID: String) async throws -> TimestampedPayload<SyncableHealthSnapshot>? { nil }
        func pushHealth(userID: String, payload: SyncableHealthSnapshot, updatedAt: Date) async throws {
            healthPushes.append((userID, payload, updatedAt))
        }
        func deleteHealth(userID: String) async throws { healthDeletes.append(userID) }
    }

    private func consentStore() -> SyncConsentStore {
        SyncConsentStore(defaults: UserDefaults(suiteName: "AccountSyncTests.\(UUID().uuidString)")!)
    }

    private let signedIn = SessionState.signedIn(userID: "apple-user-1")

    // MARK: Pure merge — last-write-wins

    func testMergeNoRemotePushesLocal() {
        let res = SyncMerge.resolve(local: SyncablePreferences(goalSteps: 8000),
                                    localUpdatedAt: Date(timeIntervalSince1970: 100),
                                    remote: nil, remoteUpdatedAt: nil)
        XCTAssertEqual(res.winner, SyncablePreferences(goalSteps: 8000))
        XCTAssertTrue(res.shouldPush)
        XCTAssertFalse(res.shouldAdopt)
    }

    func testMergeRemoteNewerAdoptsRemote() {
        let res = SyncMerge.resolve(local: SyncablePreferences(goalSteps: 8000),
                                    localUpdatedAt: Date(timeIntervalSince1970: 100),
                                    remote: SyncablePreferences(goalSteps: 12000),
                                    remoteUpdatedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(res.winner, SyncablePreferences(goalSteps: 12000))
        XCTAssertTrue(res.shouldAdopt)
        XCTAssertFalse(res.shouldPush)
    }

    func testMergeLocalNewerPushesLocal() {
        let res = SyncMerge.resolve(local: SyncablePreferences(goalSteps: 15000),
                                    localUpdatedAt: Date(timeIntervalSince1970: 300),
                                    remote: SyncablePreferences(goalSteps: 12000),
                                    remoteUpdatedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(res.winner, SyncablePreferences(goalSteps: 15000))
        XCTAssertTrue(res.shouldPush)
        XCTAssertFalse(res.shouldAdopt)
    }

    func testMergeEqualTimestampsLocalWinsNoPushWhenSame() {
        let same = SyncablePreferences(goalSteps: 10000)
        let res = SyncMerge.resolve(local: same, localUpdatedAt: Date(timeIntervalSince1970: 200),
                                    remote: same, remoteUpdatedAt: Date(timeIntervalSince1970: 200))
        XCTAssertFalse(res.shouldPush) // identical → nothing to push
        XCTAssertFalse(res.shouldAdopt)
    }

    // MARK: Payload round-trips

    func testPreferencesRoundTrip() throws {
        let original = SyncablePreferences(goalSteps: 12000)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(SyncablePreferences.self, from: data), original)
    }

    func testHealthSnapshotRoundTrip() throws {
        let original = SyncableHealthSnapshot(steps: 6420, distanceMiles: 4.2, activeMinutes: 38, activeEnergyKcal: 310)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(SyncableHealthSnapshot.self, from: data), original)
    }

    // MARK: Guests never sync

    func testGuestNeverPushesPreferences() async {
        let spy = SpyTransport()
        let consent = consentStore()
        consent.setSettingsSyncEnabled(true)
        let svc = AccountSyncService(transport: spy, consent: consent)
        await svc.pushPreferences(SyncablePreferences(goalSteps: 8000), session: .guest)
        XCTAssertTrue(spy.prefsPushes.isEmpty)
    }

    func testGuestNeverPushesHealth() async {
        let spy = SpyTransport()
        let consent = consentStore()
        consent.acknowledgeHealthConsent()
        consent.setHealthSyncEnabled(true)
        let svc = AccountSyncService(transport: spy, consent: consent)
        await svc.pushHealth(SyncableHealthSnapshot(steps: 1, distanceMiles: 0, activeMinutes: 0, activeEnergyKcal: 0),
                             session: .guest)
        XCTAssertTrue(spy.healthPushes.isEmpty)
    }

    // MARK: Settings opt-in gating

    func testSettingsPushBlockedWhenToggleOff() async {
        let spy = SpyTransport()
        let svc = AccountSyncService(transport: spy, consent: consentStore()) // default: off
        await svc.pushPreferences(SyncablePreferences(goalSteps: 8000), session: signedIn)
        XCTAssertTrue(spy.prefsPushes.isEmpty)
    }

    func testSettingsPushHappensWhenSignedInAndOn() async {
        let spy = SpyTransport()
        let consent = consentStore()
        consent.setSettingsSyncEnabled(true)
        let svc = AccountSyncService(transport: spy, consent: consent)
        await svc.pushPreferences(SyncablePreferences(goalSteps: 8000), session: signedIn)
        XCTAssertEqual(spy.prefsPushes.count, 1)
        XCTAssertEqual(spy.prefsPushes.first?.userID, "apple-user-1")
        XCTAssertEqual(spy.prefsPushes.first?.payload, SyncablePreferences(goalSteps: 8000))
    }

    // MARK: Health is HARD-gated on the opt-in

    func testHealthNeverUploadsWhileOptInOff() async {
        let spy = SpyTransport()
        // Even signed in, with consent acknowledged but the toggle OFF, no upload.
        let consent = consentStore()
        consent.acknowledgeHealthConsent()
        let svc = AccountSyncService(transport: spy, consent: consent)
        await svc.pushHealth(SyncableHealthSnapshot(steps: 6420, distanceMiles: 4.2, activeMinutes: 38, activeEnergyKcal: 310),
                             session: signedIn)
        XCTAssertTrue(spy.healthPushes.isEmpty, "health must never upload while the health opt-in is off")
    }

    func testHealthUploadsOnlyWhenOptInOn() async {
        let spy = SpyTransport()
        let consent = consentStore()
        consent.acknowledgeHealthConsent()
        XCTAssertTrue(consent.setHealthSyncEnabled(true))
        let svc = AccountSyncService(transport: spy, consent: consent)
        await svc.pushHealth(SyncableHealthSnapshot(steps: 6420, distanceMiles: 4.2, activeMinutes: 38, activeEnergyKcal: 310),
                             session: signedIn)
        XCTAssertEqual(spy.healthPushes.count, 1)
    }

    // Enabling health sync without consent is refused (so a push can't follow).
    func testHealthSyncCannotEnableWithoutConsent() {
        let consent = consentStore()
        XCTAssertFalse(consent.setHealthSyncEnabled(true))
        XCTAssertFalse(consent.healthSyncEnabled)
    }

    // MARK: Opt-out deletes the remote health row

    func testDisableHealthSyncWithDeleteRemovesRemoteRow() async {
        let spy = SpyTransport()
        let consent = consentStore()
        consent.acknowledgeHealthConsent()
        consent.setHealthSyncEnabled(true)
        let svc = AccountSyncService(transport: spy, consent: consent)
        await svc.disableHealthSync(deleteRemote: true, session: signedIn)
        XCTAssertEqual(spy.healthDeletes, ["apple-user-1"])
        XCTAssertFalse(consent.healthSyncEnabled)
    }

    func testDisableHealthSyncKeepDoesNotDelete() async {
        let spy = SpyTransport()
        let consent = consentStore()
        consent.acknowledgeHealthConsent()
        consent.setHealthSyncEnabled(true)
        let svc = AccountSyncService(transport: spy, consent: consent)
        await svc.disableHealthSync(deleteRemote: false, session: signedIn)
        XCTAssertTrue(spy.healthDeletes.isEmpty)
        XCTAssertFalse(consent.healthSyncEnabled)
    }

    // MARK: Reconcile pulls remote-newer and adopts it

    func testReconcileAdoptsRemoteWhenNewer() async {
        let spy = SpyTransport()
        spy.remotePrefs = TimestampedPayload(value: SyncablePreferences(goalSteps: 12000),
                                             updatedAt: Date(timeIntervalSince1970: 500))
        let consent = consentStore()
        consent.setSettingsSyncEnabled(true)
        let svc = AccountSyncService(transport: spy, consent: consent)
        let winner = await svc.reconcilePreferences(local: SyncablePreferences(goalSteps: 8000),
                                                    localUpdatedAt: Date(timeIntervalSince1970: 100),
                                                    session: signedIn)
        XCTAssertEqual(winner, SyncablePreferences(goalSteps: 12000))
    }

    // Account deletion purges remote health + forgets both opt-ins.
    func testPurgeOnAccountDeletion() async {
        let spy = SpyTransport()
        let consent = consentStore()
        consent.setSettingsSyncEnabled(true)
        consent.acknowledgeHealthConsent()
        consent.setHealthSyncEnabled(true)
        let svc = AccountSyncService(transport: spy, consent: consent)
        await svc.purgeOnAccountDeletion(session: signedIn)
        XCTAssertEqual(spy.healthDeletes, ["apple-user-1"])
        XCTAssertFalse(consent.settingsSyncEnabled)
        XCTAssertFalse(consent.healthSyncEnabled)
    }
}
