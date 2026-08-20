//
//  SyncService.swift
//  GoldenAcres
//
//  Two-way sync between the local SwiftData store and the API.
//
//  The device stays the source of truth for work in progress: nothing is
//  deleted locally because the server has not heard of it. When both sides
//  changed the same record, the server reports a conflict and this service
//  surfaces it rather than silently overwriting either copy.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Status

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    enum Status: Equatable {
        case idle
        case syncing
        case succeeded(Date)
        case failed(String)
        case offline
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastPushed = 0
    @Published private(set) var lastPulled = 0
    @Published private(set) var conflicts: [SyncConflict] = []

    private let cursorKey = "sync.cursor"

    var cursor: String? {
        get { UserDefaults.standard.string(forKey: cursorKey) }
        set { UserDefaults.standard.set(newValue, forKey: cursorKey) }
    }

    var lastSyncDate: Date? {
        if case .succeeded(let date) = status { return date }
        return nil
    }

    struct SyncConflict: Identifiable, Equatable {
        let id = UUID()
        let resource: String
        let recordID: String
        let serverSummary: String
    }

    private var lastAutoSync: Date?
    private let autoSyncInterval: TimeInterval = 60

    /// Called on sign-in and whenever the app comes to the foreground.
    /// Throttled, and silent when signed out — an account is optional, so a
    /// signed-out user is never nagged about syncing.
    func autoSynchronize(context: ModelContext) async {
        guard await APIClient.shared.isSignedIn else { return }
        if status == .syncing { return }
        if let last = lastAutoSync, Date().timeIntervalSince(last) < autoSyncInterval { return }
        lastAutoSync = Date()
        await synchronize(context: context)
    }

    /// Push local changes, then pull whatever the server has that we do not.
    func synchronize(context: ModelContext) async {
        guard await APIClient.shared.isSignedIn else {
            status = .idle
            return
        }
        status = .syncing
        conflicts = []

        do {
            let pushed = try await push(context: context)
            let pulled = try await pull(context: context)
            lastPushed = pushed
            lastPulled = pulled
            status = .succeeded(Date())
        } catch let error as APIError {
            if case .offline = error {
                status = .offline
            } else {
                status = .failed(error.localizedDescription)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Push

    private struct PushResponse: Decodable {
        struct Applied: Decodable { let resource: String; let id: String; let status: String }
        struct Conflict: Decodable {
            let resource: String
            let id: String
            let serverRecord: [String: AnyDecodable]?
            enum CodingKeys: String, CodingKey {
                case resource, id
                case serverRecord = "server_record"
            }
        }
        struct Rejected: Decodable { let resource: String; let id: String?; let reason: String }
        let applied: [Applied]
        let conflicts: [Conflict]
        let rejected: [Rejected]
        let cursor: String?
    }

    private func push(context: ModelContext) async throws -> Int {
        let changes = SyncMapper.collectLocalChanges(context: context)
        guard !changes.isEmpty else { return 0 }

        var pushedTotal = 0
        // The server caps a push at 500 records, so send in batches.
        for batch in SyncMapper.batched(changes, limit: 400) {
            let response: PushResponse = try await APIClient.shared.authorized(
                "POST", "/sync", body: ["changes": batch]
            )
            pushedTotal += response.applied.count

            for conflict in response.conflicts {
                let name = conflict.serverRecord?["name"]?.stringValue
                    ?? conflict.serverRecord?["title"]?.stringValue
                    ?? conflict.serverRecord?["crop_name"]?.stringValue
                    ?? conflict.id
                conflicts.append(SyncConflict(
                    resource: conflict.resource,
                    recordID: conflict.id,
                    serverSummary: "The server has a newer version of “\(name)”."
                ))
            }
            for rejection in response.rejected {
                conflicts.append(SyncConflict(
                    resource: rejection.resource,
                    recordID: rejection.id ?? "—",
                    serverSummary: rejection.reason
                ))
            }
        }
        return pushedTotal
    }

    // MARK: - Pull

    private struct PullResponse: Decodable {
        let changes: [String: [[String: AnyDecodable]]]
        let cursor: String?
    }

    private func pull(context: ModelContext) async throws -> Int {
        var path = "/sync"
        if let cursor, !cursor.isEmpty {
            let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? cursor
            path += "?since=\(encoded)"
        }

        let response: PullResponse = try await APIClient.shared.authorized("GET", path)
        let applied = SyncMapper.applyRemoteChanges(response.changes, context: context)

        if let newCursor = response.cursor {
            cursor = newCursor
        }
        return applied
    }

    /// Drops the cursor so the next sync pulls the full account again.
    func resetCursor() {
        cursor = nil
    }
}

/// Minimal type-erased JSON value for reading server records.
struct AnyDecodable: Decodable, Equatable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = nil
        }
    }

    var stringValue: String? { value as? String }
    var doubleValue: Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }
    var boolValue: Bool? {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int == 1 }
        return nil
    }
    var dateValue: Date? { ISO8601DateFormatter.parseAPIDate(stringValue) }
    var dictValue: [String: Any]? { value as? [String: Any] }
    var arrayValue: [Any]? { value as? [Any] }

    static func == (lhs: AnyDecodable, rhs: AnyDecodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// MARK: - Status card

struct SyncStatusCard: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.modelContext) private var context
    @StateObject private var sync = SyncService.shared

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Sync")

                HStack {
                    statusIcon
                    VStack(alignment: .leading, spacing: 1) {
                        Text(statusText)
                            .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                        Text(detailText)
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                if !sync.conflicts.isEmpty {
                    Divider().overlay(Palette.hairline)
                    Text("\(sync.conflicts.count) record(s) need your attention")
                        .stampLabel(Palette.amber)
                    ForEach(sync.conflicts.prefix(4)) { conflict in
                        Text("— \(conflict.resource): \(conflict.serverSummary)")
                            .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Nothing was overwritten. Open the record to decide which version to keep.")
                        .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Spacing.s) {
                    ChipButton(title: sync.status == .syncing ? "Syncing…" : "Sync now",
                               systemImage: "arrow.triangle.2.circlepath") {
                        Task { await sync.synchronize(context: context) }
                    }
                    ChipButton(title: "Full re-pull", systemImage: "arrow.down.circle",
                               tint: Palette.textSecondary) {
                        sync.resetCursor()
                        Task { await sync.synchronize(context: context) }
                    }
                }
            }
        }
    }

    private var statusIcon: some View {
        Group {
            switch sync.status {
            case .syncing:
                ProgressView().tint(Palette.gold).scaleEffect(0.8)
            case .succeeded:
                Image(systemName: "checkmark.icloud").foregroundStyle(Palette.positive)
            case .failed:
                Image(systemName: "exclamationmark.icloud").foregroundStyle(Palette.burgundy)
            case .offline:
                Image(systemName: "wifi.slash").foregroundStyle(Palette.amber)
            case .idle:
                Image(systemName: "icloud").foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(width: 22)
    }

    private var statusText: String {
        switch sync.status {
        case .idle: return "Not synced yet"
        case .syncing: return "Syncing…"
        case .succeeded: return "Up to date"
        case .failed: return "Sync failed"
        case .offline: return "Offline"
        }
    }

    private var detailText: String {
        switch sync.status {
        case .idle:
            return "Tap Sync now to send this device's records to the server."
        case .syncing:
            return "Sending local changes, then fetching anything new."
        case .succeeded(let date):
            return "\(sync.lastPushed) sent, \(sync.lastPulled) received · \(Fmt.dateTime(date) ?? "")"
        case .failed(let message):
            return message
        case .offline:
            return "Your records are safe on this device and will sync when you reconnect."
        }
    }
}
