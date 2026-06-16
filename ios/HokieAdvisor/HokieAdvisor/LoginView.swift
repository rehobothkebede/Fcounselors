import SwiftUI

struct LoginView: View {
    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Sign Up"

        var id: String { rawValue }
    }

    @Binding var isAuthenticated: Bool
    @EnvironmentObject var appState: AppState
    @AppStorage("studentName") private var studentName = ""
    @AppStorage("vtEmail") private var vtEmail = ""
    @AppStorage("vtPID") private var vtPID = ""
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("authSessionActive") private var authSessionActive = false
    @AppStorage("pendingSignupEmail") private var pendingSignupEmail = ""

    @State private var mode: AuthMode = .signIn
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var infoMessage = ""
    @State private var isLoading = false
    @State private var isKeyboardVisible = false

    private let submitButtonID = "authSubmitButton"

    private var normalizedEmail: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return trimmed.contains("@") ? trimmed : "\(trimmed)@vt.edu"
    }

    private var normalizedPID: String {
        normalizedEmail.components(separatedBy: "@").first ?? ""
    }

    private var canSubmit: Bool {
        guard !normalizedEmail.isEmpty, password.count >= 6, !isLoading else { return false }
        if mode == .signUp {
            return !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                password == confirmPassword
        }
        return true
    }

    var body: some View {
        ZStack {
            HokieAppBackground()
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 28) {
                        header
                        authCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, isKeyboardVisible ? 32 : 86)
                    .padding(.bottom, isKeyboardVisible ? 340 : 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .onKeyboardVisibilityChange { visible in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isKeyboardVisible = visible
                    }
                    if visible {
                        scrollSubmitIntoView(proxy)
                    }
                }
                .onChange(of: mode) { _, _ in
                    guard isKeyboardVisible else { return }
                    scrollSubmitIntoView(proxy)
                }
            }
        }
        .swipeDownToDismissKeyboard()
        .onAppear {
            fullName = studentName
            email = vtEmail.isEmpty ? vtPID : vtEmail
        }
    }

    private var header: some View {
        HokiePageHeader(
            title: "Hokie Advisor",
            eyebrow: mode == .signIn ? "Welcome back" : "New Hokie setup",
            subtitle: mode == .signIn ? "Sign in to your academic cockpit." : "Create your account and build your advising profile.",
            symbol: "graduationcap.fill",
            accent: .vtOrange,
            stat: HokieHeaderStat(
                value: mode == .signIn ? "Login" : "Signup",
                label: "VT students",
                icon: mode == .signIn ? "person.badge.key.fill" : "person.badge.plus"
            )
        )
    }

    private var authCard: some View {
        VStack(spacing: 18) {
            HokieSegmentedControl(
                selection: $mode,
                options: AuthMode.allCases.map { (value: $0, title: $0.rawValue) },
                accent: .vtBurgundy
            )
            .onChange(of: mode) { _, _ in
                errorMessage = ""
                infoMessage = ""
            }

            VStack(spacing: 12) {
                if mode == .signUp {
                    TextField("Full name", text: $fullName)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .authFieldStyle()
                }

                TextField("VT email or PID", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .submitLabel(.next)
                    .authFieldStyle()

                SecureField("Password", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .submitLabel(mode == .signIn ? .go : .next)
                    .authFieldStyle()
                    .onSubmit { submitIfPossible() }

                if mode == .signUp {
                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .authFieldStyle()
                        .onSubmit { submitIfPossible() }
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !infoMessage.isEmpty {
                Text(infoMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button { submitIfPossible() } label: {
                HStack(spacing: 8) {
                    if isLoading { ProgressView().tint(.white) }
                    Text(buttonTitle)
                        .font(.body.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(canSubmit ? Color.vtBurgundy : Color.primary.opacity(0.06))
                .foregroundStyle(canSubmit ? .white : Color(.tertiaryLabel))
                .clipShape(Capsule())
            }
            .disabled(!canSubmit)
            .id(submitButtonID)

            Text(mode == .signIn
                 ? "Use the email and password you created for Hokie Advisor."
                 : "New accounts can finish setup after signing up.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .glassSurface(cornerRadius: 28)
    }

    private var buttonTitle: String {
        if isLoading { return mode == .signIn ? "Signing In" : "Creating Account" }
        return mode.rawValue
    }

    private func scrollSubmitIntoView(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                proxy.scrollTo(submitButtonID, anchor: .bottom)
            }
        }
    }

    private func submitIfPossible() {
        guard canSubmit else { return }
        Task { await submit() }
    }

    @MainActor
    private func submit() async {
        guard SupabaseConfig.isConfigured else {
            errorMessage = "Account login is not configured for this build."
            return
        }

        errorMessage = ""
        infoMessage = ""
        isLoading = true
        defer { isLoading = false }

        do {
            switch mode {
            case .signIn:
                _ = try await SupabaseAuthService.shared.signIn(email: normalizedEmail, password: password)
                let needsSignupSetup = pendingSignupEmail == normalizedEmail
                storeAccountBasics(name: studentName, completeOnboarding: !needsSignupSetup)
                if needsSignupSetup {
                    pendingSignupEmail = ""
                }
            case .signUp:
                let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                let session = try await SupabaseAuthService.shared.signUp(
                    email: normalizedEmail,
                    password: password,
                    fullName: name,
                    vtPID: normalizedPID,
                    major: appState.major,
                    graduationYear: "",
                    appearanceMode: "system"
                )

                guard session != nil else {
                    pendingSignupEmail = normalizedEmail
                    storeAccountBasics(name: name, completeOnboarding: false)
                    infoMessage = "Check your email to confirm your account, then sign in."
                    mode = .signIn
                    return
                }

                pendingSignupEmail = ""
                storeAccountBasics(name: name, completeOnboarding: false)
            }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                authSessionActive = true
                isAuthenticated = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func storeAccountBasics(name: String, completeOnboarding: Bool) {
        studentName = name
        vtEmail = normalizedEmail
        vtPID = normalizedPID
        onboardingComplete = completeOnboarding
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .font(.body)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .glassCapsule(strokeOpacity: 0.08)
    }
}

#Preview {
    LoginView(isAuthenticated: .constant(false))
        .environmentObject(AppState())
}
