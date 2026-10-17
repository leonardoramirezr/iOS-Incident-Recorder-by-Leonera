import CryptoKit
import Foundation
import Security

/// Tokens de Google guardados en el llavero.
struct GoogleTokens: Codable {
    var accessToken: String
    var expiresAt: Date
    var refreshToken: String
    var email: String?
}

enum DriveError: LocalizedError {
    case notConfigured
    case notSignedIn
    case reauthorizationRequired
    case cancelled
    case oauth(code: String, description: String?)
    case http(status: Int, reason: String?, message: String?)
    case invalidResponse
    case missingLocalFile

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Este build no tiene configurado Google Drive (falta GOOGLE_IOS_CLIENT_ID)."
        case .notSignedIn:
            return "Conecta Google Drive para subir los videos."
        case .reauthorizationRequired:
            return "Google pidió volver a iniciar sesión. Conecta Google Drive de nuevo."
        case .cancelled:
            return "Se canceló el inicio de sesión."
        case .oauth(let code, let description):
            return description.map { "\($0) (\(code))" } ?? "Error de Google: \(code)"
        case .http(let status, let reason, let message):
            let detail = [reason, message].compactMap { $0 }.joined(separator: ": ")
            return detail.isEmpty ? "Google Drive respondió \(status)." : "Google Drive respondió \(status): \(detail)"
        case .invalidResponse:
            return "Respuesta inesperada de Google Drive."
        case .missingLocalFile:
            return "El archivo ya no existe en el teléfono."
        }
    }

    /// Construye el error a partir de una respuesta JSON de la API de Drive.
    static func fromDrive(status: Int, data: Data) -> DriveError {
        struct Envelope: Decodable {
            struct Body: Decodable {
                struct Item: Decodable { let reason: String? }
                let message: String?
                let errors: [Item]?
            }
            let error: Body
        }
        let body = try? JSONDecoder().decode(Envelope.self, from: data)
        return .http(status: status, reason: body?.error.errors?.first?.reason, message: body?.error.message)
    }
}

/// Utilidades PKCE (RFC 7636).
enum PKCE {
    static func makeVerifier() -> String { randomURLSafeString(byteCount: 32) }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255) }
        }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// OAuth 2.0 para apps instaladas (cliente tipo iOS, sin secreto) con PKCE.
enum GoogleOAuth {
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// `drive.file`: la app solo ve y modifica los archivos que ella misma crea.
    static let scopes = ["openid", "email", "https://www.googleapis.com/auth/drive.file"]

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`.
    static func redirectScheme(for clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static func redirectURI(for clientID: String) -> String {
        redirectScheme(for: clientID) + ":/oauth2redirect"
    }

    static func authorizationURL(clientID: String, codeChallenge: String, state: String) -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI(for: clientID)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account consent"),
        ]
        return components.url!
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int?
        let refreshToken: String?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    static func exchange(code: String, verifier: String, clientID: String) async throws -> GoogleTokens {
        let response = try await postForm([
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI(for: clientID),
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refreshToken = response.refreshToken else {
            throw DriveError.oauth(code: "no_refresh_token", description: "Google no devolvió un token de actualización")
        }
        return GoogleTokens(
            accessToken: response.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600)),
            refreshToken: refreshToken,
            email: email(fromIDToken: response.idToken)
        )
    }

    static func refresh(_ tokens: GoogleTokens) async throws -> GoogleTokens {
        guard let clientID = AppConfig.googleClientID else { throw DriveError.notConfigured }
        do {
            let response = try await postForm([
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": tokens.refreshToken,
            ])
            var updated = tokens
            updated.accessToken = response.accessToken
            updated.expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
            if let newRefreshToken = response.refreshToken {
                updated.refreshToken = newRefreshToken
            }
            return updated
        } catch DriveError.oauth(let code, _) where code == "invalid_grant" {
            throw DriveError.reauthorizationRequired
        }
    }

    static func revoke(_ token: String) async {
        var request = URLRequest(url: revokeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(["token": token]).utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func postForm(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(fields).utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        }
        if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw DriveError.oauth(code: error.error, description: error.errorDescription)
        }
        throw DriveError.http(status: status, reason: nil, message: String(data: data, encoding: .utf8))
    }

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }

    /// Lee el correo del `id_token` (JWT) sin validar la firma: solo se usa para mostrarlo.
    static func email(fromIDToken token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["email"] as? String
    }
}

/// Guarda los tokens y los renueva (una sola renovación a la vez).
actor GoogleTokenStore {
    static let shared = GoogleTokenStore()

    private static let keychainAccount = "oauth-tokens"
    private var tokens: GoogleTokens?
    private var refreshTask: Task<GoogleTokens, Error>?
    private(set) var needsReauthorization = false
    private(set) var lastKnownEmail: String?

    init() {
        if let data = Keychain.data(for: Self.keychainAccount),
           let decoded = try? JSONDecoder().decode(GoogleTokens.self, from: data) {
            tokens = decoded
            lastKnownEmail = decoded.email
        }
    }

    var isSignedIn: Bool { tokens != nil }

    func store(_ newTokens: GoogleTokens?) {
        tokens = newTokens
        if let newTokens {
            lastKnownEmail = newTokens.email
            needsReauthorization = false
            if let data = try? JSONEncoder().encode(newTokens) {
                Keychain.set(data, for: Self.keychainAccount)
            }
        } else {
            Keychain.remove(Self.keychainAccount)
        }
    }

    /// Cierra sesión y revoca el acceso en Google.
    func signOut() async {
        let refreshToken = tokens?.refreshToken
        store(nil)
        lastKnownEmail = nil
        needsReauthorization = false
        if let refreshToken {
            await GoogleOAuth.revoke(refreshToken)
        }
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else {
            throw needsReauthorization ? DriveError.reauthorizationRequired : DriveError.notSignedIn
        }
        if !forceRefresh, current.expiresAt.timeIntervalSinceNow > 120 {
            return current.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        let task = Task { try await GoogleOAuth.refresh(current) }
        refreshTask = task
        do {
            let refreshed = try await task.value
            refreshTask = nil
            store(refreshed)
            return refreshed.accessToken
        } catch {
            refreshTask = nil
            if case DriveError.reauthorizationRequired = error {
                store(nil)
                needsReauthorization = true
            }
            throw error
        }
    }
}
