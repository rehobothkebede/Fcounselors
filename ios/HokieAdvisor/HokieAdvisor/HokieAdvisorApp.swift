import SwiftUI

@main
struct HokieAdvisorApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("appPasswordHash") private var appPasswordHash = ""
    @State private var isAuthenticated = false

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !onboardingComplete {
                    OnboardingView()
                        .environmentObject(appState)
                } else if !appPasswordHash.isEmpty && !isAuthenticated {
                    LoginView(isAuthenticated: $isAuthenticated)
                } else {
                    ContentView()
                        .environmentObject(appState)
                }
            }
            .preferredColorScheme(preferredColorScheme)
            .animation(.easeInOut(duration: 0.35), value: onboardingComplete)
            .animation(.easeInOut(duration: 0.35), value: isAuthenticated)
        }
    }
}
