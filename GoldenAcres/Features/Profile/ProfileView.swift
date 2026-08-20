//
//  ProfileView.swift
//  GoldenAcres
//
//  The account screen: profile, sync state, signed-in devices, recent security
//  activity, password change, sign out, and account deletion.
//
//  Deleting the account removes what is on the server. Records on this device
//  are a separate thing, and the screen says which is which before anything
//  is destroyed.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context

    @State private var showSignIn = false
    @State private var showEdit = false
    @State private var showPassword = false
    @State private var showDelete = false
    @State private var showServerSettings = false
    @State private var deletionSummary: DeletionResponse?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if let error = auth.lastError, auth.isSignedIn {
                    ErrorBanner(title: "Sync problem", message: error.localizedDescription,
                                onRetry: { Task { await auth.restore() } },
                                onDismiss: { auth.lastError = nil })
                }

                switch auth.state {
                case .checking:
                    CardShell { LoadingBlock(lines: 3) }
                case .signedOut:
                    signedOutCard
                case .signedIn(let user):
                    accountCard(user)
                    SyncStatusCard()
                    sessionsCard
                    securityCard
                    actionsCard
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showServerSettings = true } label: {
                    Image(systemName: "server.rack").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .sheet(isPresented: $showEdit) { EditProfileView() }
        .sheet(isPresented: $showPassword) { ChangePasswordView() }
        .sheet(isPresented: $showDelete) { DeleteAccountView(summary: $deletionSummary) }
        .sheet(isPresented: $showServerSettings) { ServerSettingsView() }
        .task {
            if auth.isSignedIn {
                await auth.loadSessions()
                await auth.loadSecurityEvents()
            }
        }
        .alert("Account deleted", isPresented: .constant(deletionSummary != nil)) {
            Button("OK") { deletionSummary = nil }
        } message: {
            if let summary = deletionSummary {
                Text("\(summary.message)\n\nRemoved from the server: "
                     + (summary.recordsRemoved.isEmpty
                        ? "no stored records."
                        : summary.recordsRemoved.map { "\($0.value) \($0.key)" }.sorted().joined(separator: ", "))
                     + "\n\nRecords on this device were not touched.")
            }
        }
    }

    // MARK: - Cards

    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            GoldPlate {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack {
                        ZStack {
                            Circle().fill(Palette.surfaceRaised).frame(width: 52, height: 52)
                            Image(systemName: "person")
                                .font(.system(size: 22)).foregroundStyle(Palette.gold)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not signed in")
                                .font(TypeScale.title(18)).foregroundStyle(Palette.cream)
                            Text("Working on this device only")
                                .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                    }
                    Text("Your fields, seasons and harvests are stored on this device and work exactly as they do now. Signing in adds a server copy so you can use another device or restore after a reinstall.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    AmberButton(title: "Sign in or create an account", systemImage: "person.badge.key") {
                        showSignIn = true
                    }
                }
                .padding(Spacing.l)
            }
        }
    }

    private func accountCard(_ user: AccountProfile) -> some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle().fill(Plating.plate).frame(width: 52, height: 52)
                        Text(initials(for: user))
                            .font(TypeScale.title(20)).foregroundStyle(Palette.graphite)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName ?? user.email)
                            .font(TypeScale.title(18)).foregroundStyle(Palette.cream)
                        Text(user.email)
                            .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    StatusPill(text: user.status, tone: user.status == "active" ? .positive : .warning)
                }

                Divider().overlay(Palette.hairline)

                ValueRow(label: "Farm name", value: user.farmName, onFill: { showEdit = true })
                ValueRow(label: "Country", value: user.country, onFill: { showEdit = true })
                ValueRow(label: "Units", value: user.unitSystem.capitalized)
                ValueRow(label: "Currency", value: user.currencyCode)
                ValueRow(label: "Member since",
                         value: Fmt.date(ISO8601DateFormatter.parseAPIDate(user.createdAt)))
                ValueRow(label: "Last sign-in",
                         value: Fmt.dateTime(ISO8601DateFormatter.parseAPIDate(user.lastLoginAt)))

                ChipButton(title: "Edit profile", systemImage: "pencil") { showEdit = true }
            }
            .padding(Spacing.l)
        }
    }

    private var sessionsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Signed-in devices",
                              subtitle: "Each device holds its own token.")
                if auth.sessions.isEmpty {
                    Text("No other devices are signed in.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(auth.sessions) { session in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(session.deviceName ?? "Unnamed device")
                                    .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                                if session.isCurrent {
                                    StatusPill(text: "this device", tone: .positive)
                                }
                                Spacer()
                                if !session.isCurrent {
                                    Button("Sign out") {
                                        Task { await auth.revokeSession(session.id) }
                                    }
                                    .font(.system(size: 12)).foregroundStyle(Palette.burgundy)
                                }
                            }
                            Text([
                                session.ipAddress,
                                Fmt.dateTime(ISO8601DateFormatter.parseAPIDate(session.lastUsedAt))
                                    .map { "last used \($0)" },
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.vertical, 3)
                        if session.id != auth.sessions.last?.id {
                            Divider().overlay(Palette.hairline)
                        }
                    }
                }
            }
        }
    }

    private var securityCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Recent account activity",
                              subtitle: "Recorded by the server, including failures.")
                if auth.securityEvents.isEmpty {
                    Text("No activity recorded yet.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(auth.securityEvents.prefix(8)) { event in
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Image(systemName: event.outcome == "success"
                                  ? "checkmark.circle" : "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundStyle(event.outcome == "success"
                                                 ? Palette.positive : Palette.amber)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.event.replacingOccurrences(of: ".", with: " · "))
                                    .font(TypeScale.body(12)).foregroundStyle(Palette.cream)
                                Text([
                                    Fmt.dateTime(ISO8601DateFormatter.parseAPIDate(event.createdAt)),
                                    event.ipAddress,
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(spacing: Spacing.s) {
            GhostButton(title: "Change password", systemImage: "key") { showPassword = true }
            GhostButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                Task {
                    await auth.signOut()
                    appState.confirm("Signed out", detail: "Your records stay on this device.")
                }
            }
            GhostButton(title: "Sign out on all devices",
                        systemImage: "rectangle.portrait.and.arrow.right.fill",
                        tint: Palette.amber) {
                Task {
                    if await auth.signOutEverywhere() {
                        appState.confirm("Signed out everywhere")
                    }
                }
            }
            Button {
                showDelete = true
            } label: {
                Text("Delete account…")
                    .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: Radius.medium)
                        .fill(Palette.burgundy.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
    }

    private func initials(for user: AccountProfile) -> String {
        let source = user.displayName ?? user.email
        let parts = source.split(separator: " ").prefix(2)
        if parts.count >= 2 {
            return parts.map { String($0.prefix(1)).uppercased() }.joined()
        }
        return String(source.prefix(2)).uppercased()
    }
}

// MARK: - Edit profile

struct EditProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var farmName = ""
    @State private var country = ""
    @State private var unitSystem = "metric"
    @State private var currency = "USD"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let error = auth.lastError {
                        ErrorBanner(title: "Could not save", message: error.localizedDescription,
                                    onRetry: nil, onDismiss: { auth.lastError = nil })
                    }
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            PlateTextField(label: "Your name", placeholder: "Optional",
                                           text: $displayName,
                                           error: auth.lastError?.fieldErrors["display_name"])
                            PlateTextField(label: "Farm name", placeholder: "Optional",
                                           text: $farmName,
                                           error: auth.lastError?.fieldErrors["farm_name"])
                            PlateTextField(label: "Country", placeholder: "Optional",
                                           text: $country)
                            PlateField(label: "Units") {
                                Picker("", selection: $unitSystem) {
                                    Text("Metric").tag("metric")
                                    Text("Imperial").tag("imperial")
                                }
                                .pickerStyle(.segmented)
                            }
                            PlateTextField(label: "Currency code", placeholder: "USD",
                                           text: $currency,
                                           error: auth.lastError?.fieldErrors["currency_code"])
                                .textInputAutocapitalization(.characters)
                        }
                    }
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Label("Email changes are not available here",
                                  systemImage: "envelope.badge.shield.half.filled")
                                .font(TypeScale.headline(13)).foregroundStyle(Palette.gold)
                            Text("Changing the address on an account is a sensitive operation that needs a verification step, so it is deliberately not a plain profile edit.")
                                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    AmberButton(title: "Save profile", systemImage: "checkmark",
                                isBusy: auth.isWorking) {
                        Task {
                            let fields: [String: Any] = [
                                "display_name": displayName,
                                "farm_name": farmName,
                                "country": country,
                                "unit_system": unitSystem,
                                "currency_code": currency.uppercased(),
                            ]
                            if await auth.updateProfile(fields) {
                                appState.confirm("Profile saved")
                                dismiss()
                            }
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear {
                guard let user = auth.profile else { return }
                displayName = user.displayName ?? ""
                farmName = user.farmName ?? ""
                country = user.country ?? ""
                unitSystem = user.unitSystem
                currency = user.currencyCode
            }
            .onDisappear { auth.lastError = nil }
        }
    }
}

// MARK: - Change password

struct ChangePasswordView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var next = ""
    @State private var confirm = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let error = auth.lastError {
                        ErrorBanner(title: "Could not change the password",
                                    message: error.localizedDescription,
                                    onRetry: nil, onDismiss: { auth.lastError = nil })
                    }
                    if let localError {
                        ErrorBanner(title: "Check the form", message: localError,
                                    onRetry: nil, onDismiss: { self.localError = nil })
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SecureFieldRow(label: "Current password", text: $current,
                                           isRequired: true,
                                           error: auth.lastError?.fieldErrors["current_password"])
                            SecureFieldRow(label: "New password", text: $next, isRequired: true,
                                           error: auth.lastError?.fieldErrors["new_password"])
                            SecureFieldRow(label: "Repeat new password", text: $confirm,
                                           isRequired: true)
                            PasswordStrengthBar(password: next)
                        }
                    }

                    CardShell {
                        Label("Every other signed-in device will be signed out. This one stays signed in.",
                              systemImage: "info.circle")
                            .font(TypeScale.body(12)).foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AmberButton(title: "Change password", systemImage: "key.fill",
                                isBusy: auth.isWorking,
                                isEnabled: !current.isEmpty && !next.isEmpty) {
                        submit()
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onDisappear { auth.lastError = nil }
        }
    }

    private func submit() {
        localError = nil
        guard next == confirm else {
            localError = "The two new passwords do not match."
            return
        }
        Task {
            if await auth.changePassword(current: current, next: next) {
                appState.confirm("Password changed", detail: "Other devices were signed out.")
                dismiss()
            }
        }
    }
}

// MARK: - Delete account

struct DeleteAccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Binding var summary: DeletionResponse?

    @State private var password = ""
    @State private var typed = ""

    private var canDelete: Bool {
        !password.isEmpty && typed.uppercased() == "DELETE"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let error = auth.lastError {
                        ErrorBanner(title: "Could not delete the account",
                                    message: error.localizedDescription,
                                    onRetry: nil, onDismiss: { auth.lastError = nil })
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text("What this removes").stampLabel(Palette.burgundy)
                            bullet("Your account on the server, and the ability to sign in with it.")
                            bullet("Every record synced to the server: farms, fields, seasons, observations, soil tests, irrigation, tasks, inventory, applications and harvests.")
                            bullet("All signed-in devices are signed out immediately.")

                            Divider().overlay(Palette.hairline)

                            Text("What stays").stampLabel(Palette.positive)
                            bullet("The records already on this device. They keep working offline.")
                            bullet("Photos and files stored locally.")

                            Text("This cannot be undone. If you want a copy first, export your data from Records before continuing.")
                                .font(.system(size: 11)).foregroundStyle(Palette.amber)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SecureFieldRow(label: "Your password", text: $password,
                                           isRequired: true,
                                           error: auth.lastError?.fieldErrors["password"])
                            PlateTextField(label: "Type DELETE to confirm", placeholder: "DELETE",
                                           text: $typed, isRequired: true,
                                           error: auth.lastError?.fieldErrors["confirm"])
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                    }

                    Button {
                        Task {
                            if let result = await auth.deleteAccount(password: password) {
                                summary = result
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if auth.isWorking { ProgressView().tint(Palette.cream) }
                            Text("Delete my account permanently")
                                .font(TypeScale.headline(15))
                        }
                        .foregroundStyle(Palette.cream)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Palette.burgundy))
                        .opacity(canDelete ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDelete || auth.isWorking)
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onDisappear { auth.lastError = nil }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Text("•").foregroundStyle(Palette.textTertiary)
            Text(text)
                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
