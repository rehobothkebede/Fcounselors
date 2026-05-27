import SwiftUI
import CryptoKit

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("studentName") private var storedName = ""
    @AppStorage("vtEmail") private var storedEmail = ""
    @AppStorage("vtPID") private var storedPID = ""
    @AppStorage("appPasswordHash") private var storedPasswordHash = ""
    @AppStorage("howHeardAboutUs") private var storedHowHeard = ""
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("graduationYear") private var storedGraduationYear = ""

    @State private var step = 0
    @State private var nameInput = ""
    @State private var emailInput = ""
    @State private var emailError = ""
    @State private var passwordInput = ""
    @State private var confirmInput = ""
    @State private var passwordError = ""
    @State private var isCreatingAccount = false
    @State private var howHeardSelection = ""
    @State private var showTranscript = false

    private let howHeardOptions: [(String, String)] = [
        ("person.2.fill", "Word of mouth"),
        ("photo.on.rectangle.angled", "Social media"),
        ("person.fill.checkmark", "Professor / TA"),
        ("building.columns.fill", "CS Department"),
        ("magnifyingglass", "Online search"),
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if step > 0 && step <= 6 {
                    progressHeader
                }

                ZStack {
                    if step == 0 { welcomeStep.transition(forStep: step) }
                    if step == 1 { nameStep.transition(forStep: step) }
                    if step == 2 { emailStep.transition(forStep: step) }
                    if step == 3 { passwordStep.transition(forStep: step) }
                    if step == 4 { howHeardStep.transition(forStep: step) }
                    if step == 5 { appearanceStep.transition(forStep: step) }
                    if step == 6 { transcriptStep.transition(forStep: step) }
                    if step == 7 { doneStep.transition(forStep: step) }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
            }
        }
        .swipeDownToDismissKeyboard()
        .sheet(isPresented: $showTranscript) {
            TranscriptView().environmentObject(appState)
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(1...6, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.vtBurgundy : Color(.tertiarySystemFill))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .padding(.horizontal, 28)

            Text("Step \(step) of 6")
                .font(.caption2.bold()).foregroundStyle(.tertiary)
        }
        .padding(.top, 60)
        .padding(.bottom, 4)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 32) {
                ZStack {
                    Circle().fill(Color.vtBurgundy).frame(width: 120, height: 120)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 48, weight: .bold)).foregroundStyle(.white)
                }

                VStack(spacing: 10) {
                    Text("Hokie Advisor")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Your personal Virginia Tech\nacademic advisor")
                        .font(.title3).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }

                VStack(spacing: 10) {
                    featurePill("doc.text.fill", color: .vtBurgundy, text: "Transcript-powered course planning")
                    featurePill("brain.head.profile", color: .blue, text: "AI advisor, always available")
                    featurePill("checkmark.seal.fill", color: .green, text: "Degree audit at a glance")
                }
                .padding(.horizontal, 12)
            }
            Spacer()
            bigButton("Get Started") { advance() }
                .padding(.horizontal, 32).padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 1: Name

    private var nameStep: some View {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        return stepShell(icon: "person.fill", iconColor: .vtBurgundy,
                  title: "What's your name?",
                  subtitle: "We'll use this to personalise your experience.",
                  canProceed: !trimmed.isEmpty,
                  onContinue: {
                      storedName = trimmed
                      advance()
                  }) {
            TextField("Full name", text: $nameInput)
                .font(.title3)
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
                .submitLabel(.continue)
                .onSubmit { if !trimmed.isEmpty { storedName = trimmed; advance() } }
        }
    }

    // MARK: - Step 2: Email (PID-only input)

    private var emailStep: some View {
        let pid = emailInput.lowercased().trimmingCharacters(in: .whitespaces)
        let valid = isValidPID

        return stepShell(icon: "envelope.fill", iconColor: .blue,
                  title: "Your VT email",
                  subtitle: "Enter your Virginia Tech PID — we'll add @vt.edu for you.",
                  canProceed: valid,
                  onContinue: {
                      let p = emailInput.lowercased().trimmingCharacters(in: .whitespaces)
                      guard !p.isEmpty && p.count >= 2 && !p.contains("@") else {
                          emailError = "Please enter a valid VT PID."; return
                      }
                      storedEmail = "\(p)@vt.edu"
                      storedPID = p
                      advance()
                  }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 0) {
                    TextField("yourpid", text: $emailInput)
                        .font(.title3)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.leading, 24).padding(.vertical, 16)
                        .onChange(of: emailInput) { _, _ in emailError = "" }
                    Text("@vt.edu")
                        .font(.title3).foregroundStyle(.secondary)
                        .padding(.trailing, 24)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())

                if !emailError.isEmpty {
                    Text(emailError).font(.caption).foregroundStyle(.red).padding(.leading, 12)
                }
                if valid && !pid.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(pid)@vt.edu").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: valid)
        }
    }

    private var isValidPID: Bool {
        let pid = emailInput.lowercased().trimmingCharacters(in: .whitespaces)
        return !pid.isEmpty && pid.count >= 2 && !pid.contains("@") && !pid.contains(" ")
    }

    // MARK: - Step 3: Password

    private var passwordStep: some View {
        let canProceed = passwordInput.count >= 6 && confirmInput == passwordInput && !isCreatingAccount
        return stepShell(icon: "lock.fill", iconColor: .orange,
                  title: "Secure your account",
                  subtitle: SupabaseConfig.isConfigured
                    ? "Create your Hokie Advisor account."
                    : "Create a password to protect your data. Stored securely on your device.",
                  canProceed: canProceed,
                  onContinue: {
                      Task { await createAccountAndAdvance() }
                  }) {
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Password (min. 6 characters)", text: $passwordInput)
                    .font(.title3)
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())

                SecureField("Confirm password", text: $confirmInput)
                    .font(.title3)
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())

                if !passwordError.isEmpty {
                    Text(passwordError).font(.caption).foregroundStyle(.red).padding(.leading, 12)
                }
                if isCreatingAccount {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Creating account...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 12)
                }
            }
        }
    }

    // MARK: - Step 4: How Heard

    private var howHeardStep: some View {
        stepShell(icon: "megaphone.fill", iconColor: .purple,
                  title: "How did you hear about us?",
                  subtitle: "Help us understand how students are finding Hokie Advisor.",
                  canProceed: !howHeardSelection.isEmpty,
                  onContinue: {
                      storedHowHeard = howHeardSelection
                      advance()
                  }) {
            VStack(spacing: 8) {
                ForEach(howHeardOptions, id: \.1) { icon, label in
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            howHeardSelection = label
                        }
                    } label: {
                        HStack(spacing: 14) {
                            let selected = howHeardSelection == label
                            Image(systemName: icon)
                                .font(.body.bold())
                                .foregroundStyle(selected ? .white : Color.vtBurgundy)
                                .frame(width: 38, height: 38)
                                .background(selected ? Color.vtBurgundy : Color.vtBurgundy.opacity(0.1))
                                .clipShape(Circle())
                            Text(label).font(.subheadline.bold()).foregroundStyle(.primary)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vtBurgundy)
                            }
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(howHeardSelection == label ? Color.vtBurgundy : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Step 5: Appearance

    private let appearanceOptions: [(icon: String, label: String, tag: String)] = [
        ("circle.lefthalf.filled", "Use system setting", "system"),
        ("sun.max.fill",           "Light",              "light"),
        ("moon.fill",              "Dark",               "dark"),
    ]

    private var appearanceStep: some View {
        stepShell(
            icon: "paintbrush.fill", iconColor: .purple,
            title: "Pick your look",
            subtitle: "Choose how Hokie Advisor appears. \"System\" matches your device setting and can always be changed later in Profile.",
            canProceed: true,
            onContinue: { advance() }
        ) {
            VStack(spacing: 8) {
                ForEach(appearanceOptions, id: \.tag) { opt in
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            appearanceMode = opt.tag
                        }
                    } label: {
                        HStack(spacing: 14) {
                            let selected = appearanceMode == opt.tag
                            Image(systemName: opt.icon)
                                .font(.body.bold())
                                .foregroundStyle(selected ? .white : Color.vtBurgundy)
                                .frame(width: 38, height: 38)
                                .background(selected ? Color.vtBurgundy : Color.vtBurgundy.opacity(0.1))
                                .clipShape(Circle())
                            Text(opt.label).font(.subheadline.bold()).foregroundStyle(.primary)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vtBurgundy)
                            }
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(appearanceMode == opt.tag ? Color.vtBurgundy : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Step 6: Transcript

    private var transcriptStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(appState.hasTranscript ? Color.green.opacity(0.12) : Color.vtBurgundy.opacity(0.1))
                        .frame(width: 110, height: 110)
                    Image(systemName: appState.hasTranscript ? "checkmark.circle.fill" : "doc.text.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(appState.hasTranscript ? Color.green : Color.vtBurgundy)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: appState.hasTranscript)

                VStack(spacing: 12) {
                    Text(appState.hasTranscript ? "Transcript imported!" : "Import your transcript")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(appState.hasTranscript
                         ? "\(appState.transcriptCourses.count) courses · \(Int(appState.totalCredits)) credits loaded."
                         : "Upload your VT transcript so Hokie Advisor can give you personalised recommendations and track your degree.")
                        .font(.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }

                if !appState.hasTranscript {
                    Button { showTranscript = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.doc.fill").font(.body.bold())
                            Text("Import Transcript").font(.body.bold())
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Color.vtBurgundy).foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.horizontal, 28)
            Spacer()
            VStack(spacing: 12) {
                bigButton("Continue") { advance() }
                Button("Skip for now — I'll do this later") { advance() }
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32).padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 7: Done

    private var doneStep: some View {
        let hasTranscript = appState.hasTranscript
        let first = storedName.components(separatedBy: " ").first ?? storedName

        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(hasTranscript ? Color.vtBurgundy : Color.orange.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: hasTranscript ? "checkmark" : "doc.text.fill")
                        .font(.system(size: hasTranscript ? 52 : 44, weight: .bold))
                        .foregroundStyle(hasTranscript ? .white : Color.orange)
                }

                VStack(spacing: 10) {
                    Text(hasTranscript ? "You're all set!" : "Almost there!")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text(hasTranscript
                         ? "Welcome to Hokie Advisor\(first.isEmpty ? "!" : ", \(first)!")"
                         : "Import your transcript to unlock your degree audit, personalized course plan, and the full Hokie Advisor experience.")
                        .font(.title3).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }

                VStack(spacing: 10) {
                    if hasTranscript {
                        completionPill("checkmark.circle.fill", color: .green,
                                       text: "\(appState.transcriptCourses.count) courses · \(Int(appState.totalCredits)) credits")
                    } else {
                        completionPill("arrow.up.doc.fill", color: .orange,
                                       text: "Add your transcript in the Profile tab")
                    }
                    completionPill("brain.head.profile", color: .blue, text: "AI Advisor ready to help")
                    completionPill("wand.and.stars", color: .vtBurgundy, text: "Generate your first course plan")
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, 28)
            Spacer()
            bigButton("Let's Go, Hokies!") { onboardingComplete = true }
                .padding(.horizontal, 32).padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func advance() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
    }

    private func createAccountAndAdvance() async {
        passwordError = ""
        guard passwordInput.count >= 6 else {
            passwordError = "Password must be at least 6 characters."
            return
        }
        guard passwordInput == confirmInput else {
            passwordError = "Passwords don't match."
            return
        }

        storedPasswordHash = hashPassword(passwordInput)
        guard SupabaseConfig.isConfigured else {
            advance()
            return
        }

        isCreatingAccount = true
        defer { isCreatingAccount = false }

        do {
            _ = try await SupabaseAuthService.shared.signUp(
                email: storedEmail,
                password: passwordInput,
                fullName: storedName,
                vtPID: storedPID,
                major: appState.major,
                graduationYear: storedGraduationYear,
                appearanceMode: appearanceMode
            )
            advance()
        } catch SupabaseAuthError.missingSession {
            // Email confirmation can intentionally suppress a session.
            advance()
        } catch {
            passwordError = error.localizedDescription
        }
    }

    private func hashPassword(_ pw: String) -> String {
        let digest = SHA256.hash(data: Data(pw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @ViewBuilder
    private func stepShell<Content: View>(
        icon: String, iconColor: Color,
        title: String, subtitle: String,
        canProceed: Bool,
        onContinue: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 60, height: 60).background(iconColor).clipShape(Circle())
                        Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(subtitle).font(.body).foregroundStyle(.secondary).lineSpacing(4)
                    }
                    content()
                }
                .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            bigButton("Continue", enabled: canProceed, action: onContinue)
                .padding(.horizontal, 32).padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bigButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.bold())
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(enabled ? Color.vtBurgundy : Color(.tertiarySystemBackground))
                .foregroundStyle(enabled ? .white : Color(.tertiaryLabel))
                .clipShape(Capsule())
        }
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    private func featurePill(_ icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body.bold()).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(color).clipShape(Circle())
            Text(text).font(.subheadline.bold())
            Spacer()
        }
        .padding(14).background(Color(.secondarySystemBackground)).clipShape(Capsule())
    }

    private func completionPill(_ icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body.bold()).foregroundStyle(color)
            Text(text).font(.subheadline.bold())
            Spacer()
        }
        .padding(14).background(Color(.secondarySystemBackground)).clipShape(Capsule())
    }
}

// MARK: - Transition helper

private extension View {
    func transition(forStep _: Int) -> some View {
        self.transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }
}

#Preview { OnboardingView().environmentObject(AppState()) }
