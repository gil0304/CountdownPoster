import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct GoogleOAuthTokenSet: Codable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var expiresAt: Date
    var scope: String?

    var isAccessTokenValid: Bool {
        expiresAt.timeIntervalSinceNow > 90
    }
}

@MainActor
final class GoogleOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let configuration: APIConfiguration
    private let service = "CountdownPoster.GoogleOAuth"
    private let account = "primary"
    private var currentSession: ASWebAuthenticationSession?

    init(configuration: APIConfiguration) {
        self.configuration = configuration
    }

    var hasStoredCredentials: Bool {
        loadTokenSet()?.refreshToken?.isBlank == false || loadTokenSet()?.isAccessTokenValid == true
    }

    func signIn() async throws -> GoogleOAuthTokenSet {
        guard configuration.hasGoogleOAuth else {
            throw APIError(message: "GoogleOAuthClientID と GoogleOAuthRedirectScheme を Secrets.plist に設定してください。")
        }

        let verifier = PKCE.codeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)
        let redirectURI = "\(configuration.googleOAuthRedirectScheme):/oauth2redirect"
        let scopes = ["https://www.googleapis.com/auth/calendar.readonly"]

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.googleOAuthClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else {
            throw APIError(message: "Google OAuth URLを作れませんでした。")
        }

        let callbackURL = try await authenticate(url: authURL)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
        else {
            let error = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "error" })?
                .value ?? "unknown"
            throw APIError(message: "Google OAuthが完了しませんでした: \(error)")
        }

        let tokenSet = try await exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
        save(tokenSet)
        return tokenSet
    }

    func accessToken() async throws -> String {
        guard configuration.hasGoogleOAuth else {
            throw APIError(message: "Google OAuth設定がありません。")
        }

        if let tokenSet = loadTokenSet(), tokenSet.isAccessTokenValid {
            return tokenSet.accessToken
        }

        guard let tokenSet = loadTokenSet(),
              let refreshToken = tokenSet.refreshToken,
              !refreshToken.isBlank
        else {
            return try await signIn().accessToken
        }

        let refreshed = try await refreshAccessToken(refreshToken: refreshToken, existing: tokenSet)
        save(refreshed)
        return refreshed.accessToken
    }

    func signOut() {
        KeychainStore.delete(service: service, account: account)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        if let keyWindow {
            return keyWindow
        }

        if let windowScene = scenes.first {
            return ASPresentationAnchor(windowScene: windowScene)
        }

        preconditionFailure("Google OAuth requires an active window scene.")
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: configuration.googleOAuthRedirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? APIError(message: "Google OAuthがキャンセルされました。"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            if !session.start() {
                continuation.resume(throwing: APIError(message: "Google OAuthセッションを開始できませんでした。"))
            }
        }
    }

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> GoogleOAuthTokenSet {
        let body = [
            "client_id": configuration.googleOAuthClientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        let response: GoogleTokenResponse = try await postTokenRequest(body: body)
        return response.tokenSet(existingRefreshToken: nil)
    }

    private func refreshAccessToken(refreshToken: String, existing: GoogleOAuthTokenSet) async throws -> GoogleOAuthTokenSet {
        let body = [
            "client_id": configuration.googleOAuthClientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let response: GoogleTokenResponse = try await postTokenRequest(body: body)
        return response.tokenSet(existingRefreshToken: existing.refreshToken)
    }

    private func postTokenRequest<T: Decodable>(body: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key.urlFormEncoded)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPValidator.validate(data: data, response: response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func save(_ tokenSet: GoogleOAuthTokenSet) {
        guard let data = try? JSONEncoder().encode(tokenSet) else {
            return
        }
        try? KeychainStore.save(data: data, service: service, account: account)
    }

    private func loadTokenSet() -> GoogleOAuthTokenSet? {
        guard let data = KeychainStore.load(service: service, account: account) else {
            return nil
        }
        return try? JSONDecoder().decode(GoogleOAuthTokenSet.self, from: data)
    }
}

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    let refreshToken: String?
    let tokenType: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
    }

    func tokenSet(existingRefreshToken: String?) -> GoogleOAuthTokenSet {
        GoogleOAuthTokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken ?? existingRefreshToken,
            tokenType: tokenType,
            expiresAt: Date().addingTimeInterval(expiresIn),
            scope: scope
        )
    }
}

private enum PKCE {
    static func codeVerifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
