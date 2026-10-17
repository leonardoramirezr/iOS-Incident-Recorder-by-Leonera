import AuthenticationServices
import Foundation
import Observation
import UIKit

/// Estado de la conexión con Google Drive para la interfaz.
@Observable
final class GoogleAuthService {
    enum Status: Equatable {
        case notConfigured
        case signedOut
        case signingIn
        case signedIn
        case needsReauthorization
    }

    private(set) var status: Status
    private(set) var email: String?
    private(set) var lastError: String?

    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private var presentationProvider: WebAuthPresentationProvider?

    init() {
        status = AppConfig.googleClientID == nil ? .notConfigured : .signedOut
    }

    var isConnected: Bool { status == .signedIn }

    @MainActor
    func refreshStatus() async {
        guard AppConfig.googleClientID != nil else {
            status = .notConfigured
            return
        }
        guard status != .signingIn else { return }
        let store = GoogleTokenStore.shared
        let signedIn = await store.isSignedIn
        let needsReauthorization = await store.needsReauthorization
        email = await store.lastKnownEmail
        status = signedIn ? .signedIn : (needsReauthorization ? .needsReauthorization : .signedOut)
    }

    /// Abre el inicio de sesión de Google. Devuelve `true` si quedó conectado.
    @MainActor
    @discardableResult
    func signIn() async -> Bool {
        guard let clientID = AppConfig.googleClientID else {
            status = .notConfigured
            return false
        }
        status = .signingIn
        lastError = nil

        let verifier = PKCE.makeVerifier()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        let url = GoogleOAuth.authorizationURL(
            clientID: clientID,
            codeChallenge: PKCE.challenge(for: verifier),
            state: state
        )
        do {
            let callback = try await authenticate(url: url, callbackScheme: GoogleOAuth.redirectScheme(for: clientID))
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                throw DriveError.oauth(code: error, description: nil)
            }
            guard items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                throw DriveError.oauth(code: "invalid_response", description: "Respuesta de Google inválida")
            }
            let tokens = try await GoogleOAuth.exchange(code: code, verifier: verifier, clientID: clientID)
            await GoogleTokenStore.shared.store(tokens)
            email = tokens.email
            status = .signedIn
            return true
        } catch {
            if !Self.isCancellation(error) {
                lastError = error.localizedDescription
            }
            status = .signedOut
            await refreshStatus()
            return false
        }
    }

    @MainActor
    func signOut() async {
        await GoogleTokenStore.shared.signOut()
        email = nil
        status = AppConfig.googleClientID == nil ? .notConfigured : .signedOut
    }

    @MainActor
    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let provider = WebAuthPresentationProvider()
        presentationProvider = provider
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let once = OneShot()
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                guard once.fire() else { return }
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? DriveError.cancelled)
                }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start(), once.fire() {
                continuation.resume(throwing: DriveError.oauth(code: "start_failed", description: "No se pudo abrir el inicio de sesión"))
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
            return true
        }
        if case DriveError.cancelled = error { return true }
        return false
    }
}

/// Ventana sobre la que se presenta el inicio de sesión.
@MainActor
final class WebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow }) ?? windows.first ?? ASPresentationAnchor()
    }
}

/// Garantiza que una continuación se reanude una sola vez.
final class OneShot {
    private let lock = NSLock()
    private var fired = false

    /// Devuelve `true` solo la primera vez.
    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
