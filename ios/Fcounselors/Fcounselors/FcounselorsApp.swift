import SwiftUI

@main
struct FcounselorsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.preferredColorScheme)
        }
    }
}
