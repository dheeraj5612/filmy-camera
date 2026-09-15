@preconcurrency import AuthenticationServices
import Combine
import CryptoKit
@preconcurrency import FirebaseAuth
import FirebaseCore
@preconcurrency import GoogleSignIn
import Security
import UIKit

@MainActor
final class AuthenticationStore: ObservableObject {
    struct Identity: Equatable, Sendable {
        let uid: String
        let name: String?
        let email: String?
    }

    static let shared = AuthenticationStore()
    @Published private(set) var identity: Identity?
    @Published private(set) var isConfigured = false
    @Published private(set) var isWorking = false
    @Published var message: String?
    private var listener: AuthStateDidChangeListenerHandle?
    private var appleNonce: String?
    private var appleState: String?
    private var reauthorization: AppleReauthorization?

    init() {
        guard !MonetizationConfiguration.isAutomatedTest,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == Bundle.main.bundleIdentifier else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
        isConfigured = true
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let identity = user.map { Identity(uid: $0.uid, name: $0.displayName, email: $0.email) }
            Task { @MainActor [weak self] in
                guard Auth.auth().currentUser?.uid == identity?.uid else { return }
                self?.identity = identity
            }
        }
    }

    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        guard isConfigured, !isWorking else { return }
        message = nil
        do {
            let nonce = try Self.randomNonce()
            let state = UUID().uuidString
            appleNonce = nonce
            appleState = state
            isWorking = true
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.hash(nonce)
            request.state = state
        } catch { message = "Secure sign-in could not start. Please try again." }
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        defer { appleNonce = nil; appleState = nil; isWorking = false }
        guard isConfigured else { return }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = appleNonce, credential.state == appleState,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                throw SignInFailure.invalidCredential
            }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: token, rawNonce: nonce, fullName: credential.fullName
            )
            // Firebase validates the token's signature, audience, expiry and nonce.
            _ = try await Auth.auth().signIn(with: firebaseCredential)
        } catch { report(error) }
    }

    func signInWithGoogle() async {
        guard isConfigured, !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let credential = try await googleCredential()
            _ = try await Auth.auth().signIn(with: credential)
        }
        catch { report(error) }
    }

    private func googleCredential() async throws -> AuthCredential {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let presenter = MembershipPresentation.topController else { throw SignInFailure.unavailable }
        // Verify the callback is registered before invoking an SDK that would
        // otherwise raise an Objective-C exception for invalid configuration.
        let requiredScheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        guard schemes.contains(requiredScheme) else { throw SignInFailure.unavailable }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let token = result.user.idToken?.tokenString else { throw SignInFailure.invalidCredential }
        return GoogleAuthProvider.credential(withIDToken: token, accessToken: result.user.accessToken.tokenString)
    }

    func handle(_ url: URL) -> Bool {
        guard isConfigured else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }

    func signOut() {
        guard isConfigured, !isWorking else { return }
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            identity = nil
            // Do not erase quota or App Store entitlements when signing out.
        } catch { message = "Sign-out could not be completed. Please try again." }
    }

    func checkAppleCredential() async {
        guard isConfigured, !isWorking, let user = Auth.auth().currentUser,
              let provider = user.providerData.first(where: { $0.providerID == "apple.com" }) else { return }
        let uid = user.uid
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: provider.uid)
            guard Auth.auth().currentUser?.uid == uid else { return }
            if state == .revoked || state == .notFound { signOut() }
        } catch {
            // Offline credential-state lookup alone must not log a user out.
        }
    }

    /// Reauthenticate before deleting. Revoking Apple authorization is part of
    /// deletion, not merely removing a local profile or signing out.
    func deleteAccount() async {
        guard isConfigured, !isWorking, let user = Auth.auth().currentUser else { return }
        isWorking = true
        message = nil
        defer { isWorking = false; reauthorization = nil }
        do {
            if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
                let prompt = AppleReauthorization()
                reauthorization = prompt
                let (apple, nonce) = try await prompt.authorize()
                guard let tokenData = apple.identityToken, let token = String(data: tokenData, encoding: .utf8),
                      let codeData = apple.authorizationCode, let code = String(data: codeData, encoding: .utf8) else {
                    throw SignInFailure.invalidCredential
                }
                let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
                _ = try await user.reauthenticate(with: credential)
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
            } else if user.providerData.contains(where: { $0.providerID == "google.com" }) {
                let credential = try await googleCredential()
                _ = try await user.reauthenticate(with: credential)
                try await GIDSignIn.sharedInstance.disconnect()
            } else { throw SignInFailure.unavailable }
            try await user.delete()
            GIDSignIn.sharedInstance.signOut()
            identity = nil
            message = "Your account was deleted. Saved photos remain on this device. App Store subscriptions must be canceled separately."
        } catch { report(error) }
    }

    private func report(_ error: Error) {
        let nsError = error as NSError
        if (error as? ASAuthorizationError)?.code == .canceled
            || (nsError.domain == "com.google.GIDSignIn" && nsError.code == -5) { return }
        if AuthErrorCode(rawValue: nsError.code) == .accountExistsWithDifferentCredential {
            message = "This email already uses another sign-in method. Sign in with that provider instead."
        } else {
            message = "Account verification could not be completed. Check your connection and try again."
        }
    }

    fileprivate enum SignInFailure: Error { case invalidCredential, unavailable }

    fileprivate static func randomNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SignInFailure.unavailable
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private final class AppleReauthorization: NSObject,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<(ASAuthorizationAppleIDCredential, String), Error>?
    private var nonce = ""
    private var state = ""
    private var window: UIWindow?
    private var controller: ASAuthorizationController?

    func authorize() async throws -> (ASAuthorizationAppleIDCredential, String) {
        guard let window = MembershipPresentation.topController?.view.window else {
            throw AuthenticationStore.SignInFailure.unavailable
        }
        self.window = window
        nonce = try AuthenticationStore.randomNonce()
        state = UUID().uuidString
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.nonce = AuthenticationStore.hash(nonce)
        request.state = state
        let controller = ASAuthorizationController(authorizationRequests: [request])
        self.controller = controller
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { window ?? UIWindow() }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential, credential.state == state else {
            finish(.failure(AuthenticationStore.SignInFailure.invalidCredential))
            return
        }
        finish(.success((credential, nonce)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<(ASAuthorizationAppleIDCredential, String), Error>) {
        let pending = continuation
        continuation = nil
        controller = nil
        pending?.resume(with: result)
    }
}
