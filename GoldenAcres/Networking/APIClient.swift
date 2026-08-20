//
//  APIClient.swift
//  GoldenAcres
//
//  Every call carries a bearer token. When the access token expires the client
//  refreshes once, serialised so a burst of parallel requests produces exactly
//  one refresh, and retries. A refresh failure signs the user out rather than
//  leaving the app in a half-authenticated state.
//

import Foundation

// MARK: - Errors

enum APIError: LocalizedError, Equatable {
    case notConfigured
    case offline
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case conflict(String, [String: String])
    case validation(String, [String: String])
    case rateLimited(String, Int?)
    case server(String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No server address is configured yet."
        case .offline:
            return "You appear to be offline. Your work is saved on this device."
        case .unauthorized(let message), .forbidden(let message), .notFound(let message),
             .server(let message), .transport(let message), .decoding(let message):
            return message
        case .conflict(let message, _), .validation(let message, _):
            return message
        case .rateLimited(let message, let seconds):
            if let seconds { return "\(message) Try again in \(seconds)s." }
            return message
        }
    }

    /// Field-level messages the form can show next to the offending input.
    var fieldErrors: [String: String] {
        switch self {
        case .validation(_, let details), .conflict(_, let details):
            return details
        default:
            return [:]
        }
    }

    var requiresSignOut: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

// MARK: - Wire envelopes

private struct APIEnvelope<T: Decodable>: Decodable {
    let data: T
}

private struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
        let details: [String: DetailValue]?
    }
    let error: Payload
}

/// Error details are usually strings, but a few carry numbers or objects.
private enum DetailValue: Decodable {
    case string(String)
    case int(Int)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else {
            self = .other
        }
    }

    var text: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .other: return nil
        }
    }
}

// MARK: - Configuration

enum APIConfiguration {
    private static let baseURLKey = "api.baseURL"

    static let defaultBaseURL = "https://goldenacres.site/v1"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    static var isConfigured: Bool {
        guard let url = URL(string: baseURL) else { return false }
        return url.scheme != nil && url.host != nil
    }

    /// The app refuses to send credentials over plaintext to a remote host.
    /// Loopback is allowed so the API can be exercised locally during development.
    static var isTransportAcceptable: Bool {
        guard let url = URL(string: baseURL), let host = url.host else { return false }
        if url.scheme == "https" { return true }
        return ["127.0.0.1", "localhost", "::1"].contains(host)
    }
}

// MARK: - Client

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var refreshTask: Task<Void, Error>?

    /// Set by AuthStore so a hard auth failure can clear the UI session.
    var onAuthenticationLost: (@Sendable () async -> Void)?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: configuration)
    }

    func setAuthenticationLostHandler(_ handler: @escaping @Sendable () async -> Void) {
        self.onAuthenticationLost = handler
    }

    // MARK: Token state

    var isSignedIn: Bool {
        KeychainStore.get(.refreshToken) != nil
    }

    func storeTokens(_ tokens: TokenBundle) {
        KeychainStore.set(tokens.accessToken, for: .accessToken)
        KeychainStore.set(tokens.refreshToken, for: .refreshToken)
        KeychainStore.set(tokens.accessExpiresAt, for: .accessExpiry)
    }

    func clearTokens() {
        KeychainStore.clearAll()
    }

    // MARK: Requests

    /// Unauthenticated call, used for register/login/refresh.
    func public_<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        let request = try buildRequest(method: method, path: path, body: body, token: nil)
        let (data, response) = try await perform(request)
        return try decode(T.self, data: data, response: response)
    }

    /// Authenticated call with a single transparent refresh-and-retry on 401.
    func authorized<T: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let (data, _) = try await authorizedRaw(
            method, path, body: body, idempotencyKey: idempotencyKey
        )
        return try decodeBody(T.self, data: data)
    }

    /// For endpoints that answer 204 with no body. Errors propagate — a failed
    /// revoke must not look like a successful one.
    func authorizedNoContent(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil,
        idempotencyKey: String? = nil
    ) async throws {
        _ = try await authorizedRaw(method, path, body: body, idempotencyKey: idempotencyKey)
    }

    /// Shared transport for authenticated calls: refresh if stale, send, and on
    /// a 401 refresh exactly once and retry. Throws on any non-2xx status.
    private func authorizedRaw(
        _ method: String,
        _ path: String,
        body: [String: Any]?,
        idempotencyKey: String?
    ) async throws -> (Data, HTTPURLResponse) {
        try await refreshIfExpired()

        guard let token = KeychainStore.get(.accessToken) else {
            throw APIError.unauthorized("You are signed out.")
        }

        var request = try buildRequest(method: method, path: path, body: body, token: token)
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        var (data, response) = try await perform(request)

        if response.statusCode == 401 {
            // The token may have been invalidated early; try exactly one refresh.
            try await refresh()
            guard let retryToken = KeychainStore.get(.accessToken) else {
                await signalAuthenticationLost()
                throw APIError.unauthorized("Your session ended. Sign in again.")
            }
            var retry = try buildRequest(method: method, path: path, body: body, token: retryToken)
            if let idempotencyKey {
                retry.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            }
            (data, response) = try await perform(retry)
        }

        try validate(data: data, response: response)
        return (data, response)
    }

    // MARK: Refresh

    private func refreshIfExpired() async throws {
        guard let expiryText = KeychainStore.get(.accessExpiry),
              let expiry = ISO8601DateFormatter.apiFormatter.date(from: expiryText) else {
            return
        }
        // Refresh a little early so a request in flight doesn't expire mid-way.
        if expiry.timeIntervalSinceNow < 60 {
            try await refresh()
        }
    }

    /// Serialised: concurrent callers await the same refresh rather than
    /// each rotating the refresh token and invalidating one another.
    private func refresh() async throws {
        if let existing = refreshTask {
            try await existing.value
            return
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            guard let refreshToken = KeychainStore.get(.refreshToken) else {
                throw APIError.unauthorized("You are signed out.")
            }
            do {
                let response: AuthResponse = try await self.public_(
                    "POST", "/auth/refresh", body: ["refresh_token": refreshToken]
                )
                await self.storeTokens(response.tokens)
            } catch let error as APIError {
                // A refused refresh means the session is gone for good.
                if case .unauthorized = error {
                    await self.clearTokens()
                    await self.signalAuthenticationLost()
                }
                throw error
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func signalAuthenticationLost() async {
        await onAuthenticationLost?()
    }

    // MARK: Plumbing

    private func buildRequest(
        method: String,
        path: String,
        body: [String: Any]?,
        token: String?
    ) throws -> URLRequest {
        guard APIConfiguration.isConfigured else { throw APIError.notConfigured }
        guard APIConfiguration.isTransportAcceptable else {
            throw APIError.transport("Refusing to send credentials over an unencrypted connection.")
        }
        guard let url = URL(string: APIConfiguration.baseURL + path) else {
            throw APIError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.deviceName, forHTTPHeaderField: "X-Device-Name")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("The server sent an unexpected response.")
            }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .timedOut, .dataNotAllowed:
                throw APIError.offline
            case .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed,
                 .serverCertificateUntrusted, .serverCertificateHasBadDate:
                throw APIError.transport("The secure connection to the server failed.")
            default:
                throw APIError.transport(error.localizedDescription)
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: HTTPURLResponse) throws -> T {
        try validate(data: data, response: response)
        return try decodeBody(T.self, data: data)
    }

    private func decodeBody<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        // 204 and friends carry no body.
        if data.isEmpty, let empty = EmptyPayload() as? T {
            return empty
        }
        do {
            return try decoder.decode(APIEnvelope<T>.self, from: data).data
        } catch {
            throw APIError.decoding("The server response could not be read.")
        }
    }

    /// Turns a non-2xx response into a typed error. Never surfaces a raw body.
    private func validate(data: Data, response: HTTPURLResponse) throws {
        if (200..<300).contains(response.statusCode) { return }
        var message = "Request failed (\(response.statusCode))."
        var details: [String: String] = [:]
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
            message = envelope.error.message
            for (key, value) in envelope.error.details ?? [:] {
                if let text = value.text { details[key] = text }
            }
        }

        switch response.statusCode {
        case 401: throw APIError.unauthorized(message)
        case 403: throw APIError.forbidden(message)
        case 404: throw APIError.notFound(message)
        case 409: throw APIError.conflict(message, details)
        case 422: throw APIError.validation(message, details)
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw APIError.rateLimited(message, retry)
        default:
            throw APIError.server(message)
        }
    }

    /// A coarse label only. The real device name is sent by AuthStore in the
    /// sign-in body, where it can be read on the main actor.
    private static let deviceName = "GoldenAcres iOS"
}

struct EmptyPayload: Decodable {}

extension ISO8601DateFormatter {
    static let apiFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let apiFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseAPIDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return apiFormatter.date(from: text) ?? apiFormatterNoFraction.date(from: text)
    }
}

