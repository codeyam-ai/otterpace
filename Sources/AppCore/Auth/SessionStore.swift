import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

// MARK: - Session store (Sign in with Apple, optional)
//
// Tracks whether the user has signed in with Apple, chosen to continue as a
// guest, or hasn't decided yet. Sign in with Apple is OPTIONAL — it never gates
// HealthKit or the dashboard (per the "no account required for MVP" spec); it
// only provides a stable identity for a future cross-device/sync story.
//
// Local-only: the Apple user identifier is kept in the Keychain (via the injected
// `TokenStoring`), with no backend. The token store is injectable so the state
// logic is unit-testable without touching the real Keychain.
//
// Session longevity: the signed-in state is meant to be LONG-LIVED (not infinite).
// There is deliberately no TTL — instead we follow Apple's recommended lifecycle.
// On launch/foreground `revalidate()` confirms the stored credential is still
// `.authorized` (throttled to once per `revalidationWindow` so it's cheap), and we
// react immediately to `credentialRevokedNotification`. The session ends ONLY on a
// real revocation (`.revoked`/`.notFound`), and even then it lands the user in
// `.guest` — using the app, no welcome-screen nag. Transient/offline check failures
// keep the user signed in. The explicit `deleteAccount()` path is the only thing
// that returns to the welcome screen.

public enum SessionState: Equatable {
    case undecided                 // show the sign-in screen
    case guest                     // chose "continue without an account"
    case signedIn(userID: String)  // signed in with Apple
}

/// Minimal persistence seam for the Apple user identifier (Keychain in prod,
/// in-memory in tests).
public protocol TokenStoring {
    func read(_ account: String) -> String?
    func save(_ value: String, account: String)
    func delete(_ account: String)
}

public final class SessionStore: ObservableObject {
    @Published public private(set) var state: SessionState

    private let tokens: TokenStoring
    private let defaults: UserDefaults
    private let credentialChecker: AppleCredentialChecking
    private let revalidationWindow: TimeInterval
    private let now: () -> Date
    private var revocationObserver: NSObjectProtocol?

    private static let account = "otterpace.appleUserID"
    private static let guestKey = "otterpaceGuestChosen"
    private static let lastValidatedKey = "otterpaceAppleLastValidatedAt"

    /// `seeded` / `wantsSignInPreview` let CodeYam scenarios skip the sign-in
    /// screen by default (so the existing scenarios go straight to content), while
    /// a scenario can still opt in to preview the sign-in screen.
    ///
    /// `credentialChecker`/`revalidationWindow`/`now` are injectable so the
    /// revalidation lifecycle is unit-testable with a fake credential state and a
    /// fixed clock (the real `ASAuthorizationAppleIDProvider` is never hit in tests).
    public init(tokens: TokenStoring = KeychainTokenStore(),
                defaults: UserDefaults = .standard,
                credentialChecker: AppleCredentialChecking = AppleCredentialChecker(),
                revalidationWindow: TimeInterval = 24 * 60 * 60,
                now: @escaping () -> Date = { Date() },
                seeded: Bool = HealthSource.isScenarioSeeded(),
                wantsSignInPreview: Bool = UserDefaults.standard.string(forKey: "rbStartScreen") == "signin") {
        self.tokens = tokens
        self.defaults = defaults
        self.credentialChecker = credentialChecker
        self.revalidationWindow = revalidationWindow
        self.now = now
        // Scenario/preview hook: a captured scenario can seed `rbSignedInUserID`
        // to render the signed-in states (e.g. the account-sync Settings UI)
        // without a real Sign in with Apple. Production never carries this key.
        if let previewID = defaults.string(forKey: "rbSignedInUserID"), !previewID.isEmpty {
            state = .signedIn(userID: previewID)
        } else if let id = tokens.read(Self.account) {
            state = .signedIn(userID: id)
        } else if defaults.bool(forKey: Self.guestKey) {
            state = .guest
        } else if seeded && !wantsSignInPreview {
            state = .guest               // scenarios skip sign-in unless previewing it
        } else {
            state = .undecided
        }
        subscribeToRevocation()
    }

    deinit {
        if let observer = revocationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Record a successful Sign in with Apple (the stable `user` identifier) and
    /// stamp it validated now, so the next launch trusts it for the full window.
    public func signIn(userID: String) {
        tokens.save(userID, account: Self.account)
        stampValidated()
        state = .signedIn(userID: userID)
    }

    /// Continue without an account — remembered so we don't re-prompt.
    public func continueAsGuest() {
        defaults.set(true, forKey: Self.guestKey)
        state = .guest
    }

    /// Sign out of Apple but keep using the app as a guest (no re-prompt).
    public func signOut() {
        tokens.delete(Self.account)
        defaults.set(true, forKey: Self.guestKey)
        state = .guest
    }

    /// Delete the local account: forget the Apple identity AND the guest choice,
    /// returning to the welcome screen. This is the in-app account-deletion path
    /// App Store guideline 5.1.1(v) requires for apps offering account sign-in.
    public func deleteAccount() {
        tokens.delete(Self.account)
        defaults.set(false, forKey: Self.guestKey)
        state = .undecided
    }

    /// Return to the sign-in screen to upgrade a guest into a signed-in account.
    public func presentSignIn() {
        defaults.set(false, forKey: Self.guestKey)
        state = .undecided
    }

    // MARK: - Durable session revalidation

    /// Confirm the stored Apple credential is still valid, the way Apple intends.
    /// Call on launch and on foreground. Throttled to once per `revalidationWindow`
    /// (pass `force: true` to bypass — used by the revocation notification):
    ///   • `.authorized`        → refresh the validation stamp and stay signed in.
    ///   • `.revoked`/`.notFound` → end the session gracefully (drop to guest).
    ///   • `.unknown` (offline/transient) → keep the session; retry next time.
    /// A no-op unless currently signed in.
    @MainActor
    public func revalidate(force: Bool = false) async {
        guard case .signedIn(let userID) = state else { return }
        if !force, let last = lastValidatedAt(),
           now().timeIntervalSince(last) < revalidationWindow {
            return                       // checked recently — stay signed in, no churn
        }
        switch await credentialChecker.state(forUserID: userID) {
        case .authorized:        stampValidated()
        case .revoked, .notFound: endSession()
        case .unknown:           break
        }
    }

    /// End the session because the Apple credential is genuinely gone: forget the
    /// identity but keep the app usable as a guest (no welcome-screen nag). This is
    /// the graceful counterpart to `deleteAccount()`, which returns to welcome.
    @MainActor
    public func endSession() {
        tokens.delete(Self.account)
        defaults.removeObject(forKey: Self.lastValidatedKey)
        defaults.set(true, forKey: Self.guestKey)
        state = .guest
    }

    private func stampValidated() {
        defaults.set(now().timeIntervalSinceReferenceDate, forKey: Self.lastValidatedKey)
    }

    private func lastValidatedAt() -> Date? {
        let stamp = defaults.double(forKey: Self.lastValidatedKey)
        return stamp == 0 ? nil : Date(timeIntervalSinceReferenceDate: stamp)
    }

    /// React immediately to a real Apple-credential revocation, bypassing the
    /// throttle window.
    private func subscribeToRevocation() {
        #if canImport(AuthenticationServices)
        revocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.revalidate(force: true) }
        }
        #endif
    }
}
