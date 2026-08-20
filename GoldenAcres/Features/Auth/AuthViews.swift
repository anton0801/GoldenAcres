//
//  AuthViews.swift
//  GoldenAcres
//
//  Sign in and registration. Signing in is optional: the app works fully
//  offline on this device, and an account only adds sync and backup. That is
//  stated on the screen rather than implied.
//

import SwiftUI

// MARK: - Sign in

struct SignInView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false
    @State private var showServerSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header

                    if let error = auth.lastError {
                        ErrorBanner(title: "Could not sign in",
                                    message: error.localizedDescription,
                                    onRetry: nil,
                                    onDismiss: { auth.lastError = nil })
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            PlateTextField(label: "Email", placeholder: "you@farm.example",
                                           text: $email, isRequired: true, keyboard: .emailAddress,
                                           error: auth.lastError?.fieldErrors["email"])
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            SecureFieldRow(label: "Password", text: $password,
                                           error: auth.lastError?.fieldErrors["password"])
                        }
                    }

                    AmberButton(title: "Sign in", systemImage: "arrow.right",
                                isBusy: auth.isWorking,
                                isEnabled: !email.isEmpty && !password.isEmpty) {
                        Task {
                            if await auth.signIn(email: email, password: password) {
                                password = ""
                                dismiss()
                            }
                        }
                    }

                    GhostButton(title: "Create an account", systemImage: "person.badge.plus") {
                        showRegister = true
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Label("An account is optional", systemImage: "info.circle")
                                .font(TypeScale.headline(13)).foregroundStyle(Palette.gold)
                            Text("Everything you record works on this device without signing in. An account adds encrypted sync across your devices and a backup you can restore from.")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(Spacing.l)
                .padding(.bottom, Spacing.xxl)
            }
            .farmBackground()
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showServerSettings = true } label: {
                        Image(systemName: "server.rack").foregroundStyle(Palette.gold)
                    }
                }
            }
            .sheet(isPresented: $showRegister) { RegisterView() }
            .sheet(isPresented: $showServerSettings) { ServerSettingsView() }
            .onDisappear { auth.lastError = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            WheatMark(size: 30)
            Text("Sync your records")
                .font(TypeScale.display(26)).foregroundStyle(Palette.cream)
            Text("Sign in to keep your fields, seasons and harvests backed up and available on every device you use.")
                .font(TypeScale.body(14)).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.s)
    }
}

// MARK: - Register

struct RegisterView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var farmName = ""
    @State private var localError: String?

    private var passwordsMatch: Bool {
        confirmPassword.isEmpty || password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let error = auth.lastError {
                        ErrorBanner(title: "Could not create the account",
                                    message: error.localizedDescription,
                                    onRetry: nil,
                                    onDismiss: { auth.lastError = nil })
                    }
                    if let localError {
                        ErrorBanner(title: "Check the form", message: localError,
                                    onRetry: nil, onDismiss: { self.localError = nil })
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            PlateTextField(label: "Email", placeholder: "you@farm.example",
                                           text: $email, isRequired: true, keyboard: .emailAddress,
                                           error: auth.lastError?.fieldErrors["email"])
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            SecureFieldRow(label: "Password", text: $password,
                                           isRequired: true,
                                           error: auth.lastError?.fieldErrors["password"],
                                           helper: "At least 10 characters. A passphrase of 16+ is simplest.")

                            SecureFieldRow(label: "Repeat password", text: $confirmPassword,
                                           isRequired: true,
                                           error: passwordsMatch ? nil : "The two passwords do not match.")

                            PasswordStrengthBar(password: password)

                            Divider().overlay(Palette.hairline)

                            PlateTextField(label: "Your name", placeholder: "Optional",
                                           text: $displayName)
                            PlateTextField(label: "Farm name", placeholder: "Optional",
                                           text: $farmName)
                        }
                    }

                    AmberButton(title: "Create account", systemImage: "checkmark",
                                isBusy: auth.isWorking,
                                isEnabled: !email.isEmpty && !password.isEmpty) {
                        submit()
                    }

                    Text("Your password is never stored or sent anywhere in readable form. We keep only a hash that cannot be reversed.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.l)
                .padding(.bottom, Spacing.xxl)
            }
            .farmBackground()
            .navigationTitle("Create account")
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
        guard password == confirmPassword else {
            localError = "The two passwords do not match."
            return
        }
        Task {
            let created = await auth.register(
                email: email, password: password,
                displayName: displayName.isEmpty ? nil : displayName,
                farmName: farmName.isEmpty ? nil : farmName
            )
            if created { dismiss() }
        }
    }
}

// MARK: - Shared controls

struct SecureFieldRow: View {
    var label: String
    @Binding var text: String
    var isRequired: Bool = false
    var error: String?
    var helper: String?

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            FieldLabel(text: label, isRequired: isRequired)
            HStack {
                Group {
                    if isRevealed {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .font(TypeScale.body(15))
                .foregroundStyle(Palette.cream)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Palette.graphite.opacity(0.7))
                    .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .strokeBorder(error == nil ? Palette.hairline : Palette.burgundy,
                                      lineWidth: error == nil ? 1 : 1.5))
            )
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.burgundy)
            } else if let helper {
                Text(helper).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// Rough local feedback only. The server applies the authoritative policy.
struct PasswordStrengthBar: View {
    var password: String

    private var score: Int {
        guard !password.isEmpty else { return 0 }
        var value = 0
        if password.count >= 10 { value += 1 }
        if password.count >= 16 { value += 1 }
        var classes = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { classes += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { classes += 1 }
        if classes >= 3 { value += 1 }
        if classes == 4 { value += 1 }
        return min(value, 4)
    }

    private var label: String {
        switch score {
        case 0: return "Too short"
        case 1: return "Weak"
        case 2: return "Fair"
        case 3: return "Good"
        default: return "Strong"
        }
    }

    private var tone: Color {
        switch score {
        case 0, 1: return Palette.burgundy
        case 2: return Palette.amber
        case 3: return Palette.gold
        default: return Palette.positive
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < score ? tone : Palette.surfaceRaised)
                        .frame(height: 4)
                }
            }
            Text(password.isEmpty ? "Strength shown as you type" : label)
                .font(.system(size: 10))
                .foregroundStyle(password.isEmpty ? Palette.textTertiary : tone)
        }
    }
}

// MARK: - Server settings

struct ServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = APIConfiguration.baseURL
    @State private var status: String?
    @State private var isChecking = false
    @State private var isReachable: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "API endpoint",
                                          subtitle: "Where this app syncs to.")
                            PlateTextField(label: "Base URL",
                                           placeholder: "https://api.example.com/v1",
                                           text: $baseURL, keyboard: .URL,
                                           error: transportWarning)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            if let status {
                                Label(status, systemImage: isReachable == true
                                      ? "checkmark.seal.fill" : "exclamationmark.triangle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(isReachable == true ? Palette.positive : Palette.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: Spacing.s) {
                                ChipButton(title: isChecking ? "Checking…" : "Test connection",
                                           systemImage: "antenna.radiowaves.left.and.right") {
                                    test()
                                }
                            }
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Label("Credentials are only sent over HTTPS",
                                  systemImage: "lock.shield")
                                .font(TypeScale.headline(13)).foregroundStyle(Palette.gold)
                            Text("The app refuses to send your password or token to a plain http:// address, apart from a loopback address used during development.")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    AmberButton(title: "Save endpoint", systemImage: "checkmark") {
                        APIConfiguration.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var transportWarning: String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let host = url.host else { return nil }
        if url.scheme == "https" { return nil }
        if ["127.0.0.1", "localhost", "::1"].contains(host) { return nil }
        return "Only https:// is allowed for a remote server."
    }

    private func test() {
        isChecking = true
        status = nil
        let candidate = baseURL.trimmingCharacters(in: .whitespaces)
        Task {
            let previous = APIConfiguration.baseURL
            APIConfiguration.baseURL = candidate
            do {
                struct Health: Decodable { let status: String; let time: String? }
                let health: Health = try await APIClient.shared.public_("GET", "/health")
                isReachable = true
                status = "Reachable — server reports \(health.status)."
            } catch {
                isReachable = false
                APIConfiguration.baseURL = previous
                status = (error as? APIError)?.localizedDescription
                    ?? "Could not reach that address."
            }
            isChecking = false
        }
    }
}
