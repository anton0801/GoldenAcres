//
//  AuthStore.swift
//  GoldenAcres
//
//  Session state for the UI: who is signed in, and what the server said last.
//  Local records stay on the device whether or not anyone is signed in — the
//  account adds sync and backup, it is not a gate on your own data.
//

import Foundation
import SwiftUI

// MARK: - DTOs

struct TokenBundle: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let accessExpiresAt: String
    let refreshExpiresAt: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case accessExpiresAt = "access_expires_at"
        case refreshExpiresAt = "refresh_expires_at"
    }
}

struct AccountProfile: Decodable, Equatable {
    let id: String
    let email: String
    let displayName: String?
    let farmName: String?
    let country: String?
    let unitSystem: String
    let currencyCode: String
    let timeZone: String
    let status: String
    let createdAt: String?
    let lastLoginAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, status, country
        case displayName = "display_name"
        case farmName = "farm_name"
        case unitSystem = "unit_system"
        case currencyCode = "currency_code"
        case timeZone = "time_zone"
        case createdAt = "created_at"
        case lastLoginAt = "last_login_at"
    }
}

struct AuthResponse: Decodable {
    let user: AccountProfile
    let tokens: TokenBundle
}

struct ProfileResponse: Decodable {
    let user: AccountProfile
}

struct DeviceSession: Decodable, Identifiable, Equatable {
    let id: String
    let deviceName: String?
    let ipAddress: String?
    let userAgent: String?
    let createdAt: String?
    let lastUsedAt: String?
    let refreshExpiresAt: String?
    let isCurrent: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "device_name"
        case ipAddress = "ip_address"
        case userAgent = "user_agent"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case refreshExpiresAt = "refresh_expires_at"
        case isCurrent = "is_current"
    }
}

struct SessionsResponse: Decodable {
    let sessions: [DeviceSession]
}

struct SecurityEvent: Decodable, Identifiable {
    var id: String { (createdAt ?? "") + event }
    let event: String
    let outcome: String
    let ipAddress: String?
    let detail: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case event, outcome, detail
        case ipAddress = "ip_address"
        case createdAt = "created_at"
    }
}

struct SecurityEventsResponse: Decodable {
    let events: [SecurityEvent]
}

struct DeletionResponse: Decodable {
    let deleted: Bool
    let recordsRemoved: [String: Int]
    let message: String

    enum CodingKeys: String, CodingKey {
        case deleted, message
        case recordsRemoved = "records_removed"
    }
}

// MARK: - Store

@MainActor
final class AuthStore: ObservableObject {
    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(AccountProfile)
    }

    @Published private(set) var state: State = .checking
    @Published var lastError: APIError?
    @Published private(set) var isWorking = false
    @Published private(set) var sessions: [DeviceSession] = []
    @Published private(set) var securityEvents: [SecurityEvent] = []

    var profile: AccountProfile? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    var isSignedIn: Bool { profile != nil }

    init() {
        Task {
            await APIClient.shared.setAuthenticationLostHandler { [weak self] in
                await self?.handleAuthenticationLost()
            }
            await restore()
        }
    }

    /// Called at launch. A stored refresh token is verified against the server
    /// before the UI claims the user is signed in.
    func restore() async {
        guard APIConfiguration.isConfigured, await APIClient.shared.isSignedIn else {
            state = .signedOut
            return
        }
        do {
            let response: ProfileResponse = try await APIClient.shared.authorized("GET", "/me")
            state = .signedIn(response.user)
        } catch {
            // Offline should not sign anyone out; only a rejected token does.
            if let apiError = error as? APIError, apiError.requiresSignOut {
                await APIClient.shared.clearTokens()
                state = .signedOut
            } else {
                state = .signedOut
            }
        }
    }

    func register(
        email: String,
        password: String,
        displayName: String?,
        farmName: String?
    ) async -> Bool {
        await run {
            var body: [String: Any] = ["email": email, "password": password]
            if let displayName, !displayName.isEmpty { body["display_name"] = displayName }
            if let farmName, !farmName.isEmpty { body["farm_name"] = farmName }
            body["device_name"] = Self.deviceName

            let response: AuthResponse = try await APIClient.shared.public_(
                "POST", "/auth/register", body: body
            )
            await APIClient.shared.storeTokens(response.tokens)
            self.state = .signedIn(response.user)
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        await run {
            let response: AuthResponse = try await APIClient.shared.public_(
                "POST", "/auth/login",
                body: ["email": email, "password": password, "device_name": Self.deviceName]
            )
            await APIClient.shared.storeTokens(response.tokens)
            self.state = .signedIn(response.user)
        }
    }

    func signOut() async {
        _ = await run {
            _ = try? await APIClient.shared.authorized("POST", "/auth/logout") as EmptyPayload
            await APIClient.shared.clearTokens()
            self.state = .signedOut
            self.sessions = []
            self.securityEvents = []
        }
    }

    func signOutEverywhere() async -> Bool {
        await run {
            _ = try await APIClient.shared.authorized("POST", "/auth/logout-all") as EmptyPayload
            await APIClient.shared.clearTokens()
            self.state = .signedOut
            self.sessions = []
        }
    }

    func updateProfile(_ fields: [String: Any]) async -> Bool {
        await run {
            let response: ProfileResponse = try await APIClient.shared.authorized(
                "PATCH", "/me", body: fields
            )
            self.state = .signedIn(response.user)
        }
    }

    func changePassword(current: String, next: String) async -> Bool {
        await run {
            _ = try await APIClient.shared.authorized(
                "POST", "/me/password",
                body: ["current_password": current, "new_password": next]
            ) as EmptyPayload
        }
    }

    func loadSessions() async {
        _ = await run {
            let response: SessionsResponse = try await APIClient.shared.authorized("GET", "/me/sessions")
            self.sessions = response.sessions
        }
    }

    func revokeSession(_ id: String) async -> Bool {
        await run {
            try await APIClient.shared.authorizedNoContent("DELETE", "/me/sessions/\(id)")
            self.sessions.removeAll { $0.id == id }
        }
    }

    func loadSecurityEvents() async {
        _ = await run {
            let response: SecurityEventsResponse = try await APIClient.shared.authorized(
                "GET", "/me/security-events?limit=25"
            )
            self.securityEvents = response.events
        }
    }

    /// Deletes the server account. Local records are untouched — the caller
    /// tells the user exactly that.
    func deleteAccount(password: String) async -> DeletionResponse? {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let response: DeletionResponse = try await APIClient.shared.authorized(
                "DELETE", "/me", body: ["password": password, "confirm": "DELETE"]
            )
            await APIClient.shared.clearTokens()
            state = .signedOut
            sessions = []
            securityEvents = []
            return response
        } catch let error as APIError {
            lastError = error
            return nil
        } catch {
            lastError = .server(error.localizedDescription)
            return nil
        }
    }

    private func handleAuthenticationLost() async {
        await APIClient.shared.clearTokens()
        state = .signedOut
        lastError = .unauthorized("Your session ended. Sign in again.")
    }

    @discardableResult
    private func run(_ work: @escaping () async throws -> Void) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await work()
            return true
        } catch let error as APIError {
            lastError = error
            return false
        } catch {
            lastError = .server(error.localizedDescription)
            return false
        }
    }

    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "GoldenAcres"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
