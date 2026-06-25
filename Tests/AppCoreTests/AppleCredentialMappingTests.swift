import XCTest
@testable import AppCore
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
// Covers the pure mapping from Apple's CredentialState to our decoupled enum.
#if canImport(AuthenticationServices)
final class AppleCredentialMappingTests: XCTestCase {

    // An authorized Apple credential maps to .authorized (stay signed in).
    func testAuthorizedMapsToAuthorized() {
        XCTAssertEqual(appleCredentialState(from: .authorized), .authorized)
    }

    // A revoked credential maps to .revoked (end the session).
    func testRevokedMapsToRevoked() {
        XCTAssertEqual(appleCredentialState(from: .revoked), .revoked)
    }

    // An unknown identifier maps to .notFound (end the session).
    func testNotFoundMapsToNotFound() {
        XCTAssertEqual(appleCredentialState(from: .notFound), .notFound)
    }

    // A transferred app (moved dev teams) is inconclusive → .unknown (stay signed in).
    func testTransferredMapsToUnknown() {
        XCTAssertEqual(appleCredentialState(from: .transferred), .unknown)
    }
}
#endif
