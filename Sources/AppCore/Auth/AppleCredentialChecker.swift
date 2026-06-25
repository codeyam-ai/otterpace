import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

// MARK: - Apple credential-state seam
//
// Lets `SessionStore` ask Apple whether a stored Sign in with Apple credential is
// still valid, the way Apple intends (`getCredentialState(forUserID:)`), without
// the unit suite ever touching `ASAuthorizationAppleIDProvider`. Mirrors the
// injectable `TokenStoring` pattern: production uses the real provider; tests inject
// a fake that returns a canned state.

/// Validity of a stored Apple credential, decoupled from
/// `ASAuthorizationAppleIDProvider.CredentialState` so the session logic stays
/// testable without AuthenticationServices.
public enum AppleCredentialState: Equatable {
    case authorized   // credential still valid → stay signed in
    case revoked      // user revoked Apple access → end the session
    case notFound     // identifier unknown to Apple → end the session
    case unknown      // transient/offline/unsupported → treat as "stay signed in"
}

/// Seam for checking whether a stored Apple user identifier is still authorized.
public protocol AppleCredentialChecking {
    func state(forUserID userID: String) async -> AppleCredentialState
}

#if canImport(AuthenticationServices)
/// Pure mapping from Apple's `CredentialState` to our decoupled enum. Extracted so
/// the lifecycle branches are unit-tested without a live provider, leaving
/// `AppleCredentialChecker` a thin boundary passthrough.
public func appleCredentialState(
    from state: ASAuthorizationAppleIDProvider.CredentialState
) -> AppleCredentialState {
    switch state {
    case .authorized:  return .authorized
    case .revoked:     return .revoked
    case .notFound:    return .notFound
    // `.transferred` (app moved between dev teams) isn't a revocation — treat it as
    // inconclusive and keep the user signed in.
    case .transferred: return .unknown
    @unknown default:  return .unknown
    }
}
#endif

/// Production checker wrapping `ASAuthorizationAppleIDProvider.getCredentialState`.
/// On platforms without AuthenticationServices it reports `.unknown`, so a missing
/// framework never spuriously drops the session. The state translation lives in the
/// pure `appleCredentialState(from:)` helper so this stays a thin I/O passthrough.
public struct AppleCredentialChecker: AppleCredentialChecking {
    public init() {}

    public func state(forUserID userID: String) async -> AppleCredentialState {
        #if canImport(AuthenticationServices)
        let provider = ASAuthorizationAppleIDProvider()
        return await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: appleCredentialState(from: state))
            }
        }
        #else
        return .unknown
        #endif
    }
}
