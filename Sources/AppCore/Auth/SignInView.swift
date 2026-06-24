import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

// MARK: - Sign-in screen (optional)
//
// Shown in production before the dashboard when the user hasn't decided. Sign in
// with Apple is OPTIONAL — "Continue without an account" is given equal weight,
// and everything (including HealthKit) works as a guest. Scenarios skip this
// screen unless one seeds `rbStartScreen = "signin"` to preview it.
struct SignInView: View {
    @ObservedObject var session: SessionStore

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            PuffyBuddy(mood: .ready, size: 130).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Welcome to Otterpace")
                    .font(Typography.title)
                    .foregroundColor(Palette.ink)
                Text("Sign in to keep your coaching across devices — or continue without an account. Either way, your health data stays on your device.")
                    .font(Typography.callout)
                    .foregroundColor(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }

            VStack(spacing: 12) {
                appleButton
                Button(action: session.continueAsGuest) {
                    Text("Continue without an account")
                        .font(Typography.headline)
                        .foregroundColor(Palette.brandDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Palette.brand.opacity(0.12)))
                }
                .accessibilityLabel("Continue without an account")
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    @ViewBuilder private var appleButton: some View {
        #if canImport(AuthenticationServices)
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            // The stable `user` identifier is all we keep (no backend). Email/name
            // arrive only on first authorization — we don't depend on them.
            if case .success(let auth) = result,
               let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                session.signIn(userID: credential.user)
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        #else
        EmptyView()
        #endif
    }
}
