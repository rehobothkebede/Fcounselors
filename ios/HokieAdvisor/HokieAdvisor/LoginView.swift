import SwiftUI
import CryptoKit

struct LoginView: View {
    @Binding var isAuthenticated: Bool
    @AppStorage("studentName") private var studentName = ""
    @AppStorage("appPasswordHash") private var storedHash = ""

    @State private var passwordInput = ""
    @State private var errorMessage = ""
    @State private var shake = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 36) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.vtBurgundy).frame(width: 88, height: 88)
                        Text(initials).font(.title.bold()).foregroundStyle(.white)
                    }
                    VStack(spacing: 6) {
                        Text("Welcome back")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        if !firstName.isEmpty {
                            Text(firstName)
                                .font(.title3).foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: 12) {
                    SecureField("Password", text: $passwordInput)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24).padding(.vertical, 16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                        .offset(x: shake ? -8 : 0)
                        .animation(shake ? .default.repeatCount(3, autoreverses: true).speed(4) : .default, value: shake)
                        .onSubmit { attempt() }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption).foregroundStyle(.red)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            Button { attempt() } label: {
                Text("Sign In")
                    .font(.body.bold()).frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(!passwordInput.isEmpty ? Color.vtBurgundy : Color(.tertiarySystemBackground))
                    .foregroundStyle(!passwordInput.isEmpty ? .white : Color(.tertiaryLabel))
                    .clipShape(Capsule())
            }
            .disabled(passwordInput.isEmpty)
            .animation(.easeInOut(duration: 0.2), value: passwordInput.isEmpty)
            .padding(.horizontal, 32).padding(.bottom, 48)
        }
        .background(Color(.systemBackground))
        .swipeDownToDismissKeyboard()
    }

    private func attempt() {
        guard hashPassword(passwordInput) == storedHash else {
            withAnimation { errorMessage = "Incorrect password. Try again." }
            passwordInput = ""
            shake = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shake = false }
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isAuthenticated = true
        }
    }

    private func hashPassword(_ pw: String) -> String {
        let digest = SHA256.hash(data: Data(pw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var firstName: String {
        studentName.components(separatedBy: " ").first ?? studentName
    }

    private var initials: String {
        let parts = studentName.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.isEmpty { return "HK" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
    }
}

#Preview {
    LoginView(isAuthenticated: .constant(false))
}
