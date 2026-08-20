//
//  AppState.swift
//  GoldenAcres
//
//  Session-level state: onboarding progress, connectivity, and the toast used
//  to confirm exactly what changed after a save.
//

import SwiftUI
import Network
import Combine

@MainActor
final class AppState: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false

    @Published var toast: ToastMessage?
    @Published var isOnline: Bool = true
    /// True until the first network path evaluation arrives.
    @Published var connectivityUnknown: Bool = true

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "GoldenAcres.network")

    struct ToastMessage: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var detail: String?
    }

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.connectivityUnknown = false
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Confirms a completed action, naming what changed.
    func confirm(_ message: String, detail: String? = nil) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toast = ToastMessage(message: message, detail: detail)
        }
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
            }
        }
    }
}

// MARK: - Draft persistence

/// Keeps an in-progress form alive across a crash, a cancel, or a failed save,
/// so entered work is never silently lost.
@MainActor
final class DraftStore: ObservableObject {
    static let shared = DraftStore()

    private let defaults = UserDefaults.standard
    private let prefix = "draft."

    func save<T: Codable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: prefix + key)
    }

    func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func clear(key: String) {
        defaults.removeObject(forKey: prefix + key)
    }

    func exists(key: String) -> Bool {
        defaults.data(forKey: prefix + key) != nil
    }
}

// MARK: - Save guard

/// Blocks a second submit while the first is still running.
@MainActor
final class SaveGuard: ObservableObject {
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    /// Runs `work` once; concurrent calls while saving are ignored.
    func run(_ work: () throws -> Void) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func runAsync(_ work: @escaping () async throws -> Void) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await work()
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
            await MainActor.run { self.isSaving = false }
        }
    }
}
