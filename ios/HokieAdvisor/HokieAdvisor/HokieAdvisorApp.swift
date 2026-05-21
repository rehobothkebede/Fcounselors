import SwiftUI
import UIKit

// UIViewRepresentable that sets overrideUserInterfaceStyle on its window.
// updateUIView is called after the view is attached to a window, so we
// defer one run-loop tick with async to guarantee window != nil.
struct WindowAppearanceSetter: UIViewRepresentable {
    let mode: String

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isHidden = true
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let style: UIUserInterfaceStyle = switch mode {
            case "dark":  .dark
            case "light": .light
            default:      .unspecified
        }
        DispatchQueue.main.async {
            uiView.window?.overrideUserInterfaceStyle = style
        }
    }
}

@main
struct HokieAdvisorApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("appPasswordHash") private var appPasswordHash = ""
    @State private var isAuthenticated = false

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
            .background(WindowAppearanceSetter(mode: appearanceMode))
            .animation(.easeInOut(duration: 0.35), value: onboardingComplete)
            .animation(.easeInOut(duration: 0.35), value: isAuthenticated)
        }
    }
}
