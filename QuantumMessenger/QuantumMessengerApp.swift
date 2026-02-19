import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
@main
struct QuantumMessengerApp: App {
    @State private var appState = AppState()

    init() {
        // One-time migration: move any keys previously stored in UserDefaults
        // into the real iOS Keychain. Safe to call on every launch — it is a no-op
        // once migration has already occurred.
        KeychainService.migrateFromUserDefaultsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .alert("Error", isPresented: Binding(
                    get: { appState.showError },
                    set: { appState.showError = $0 }
                )) {
                    Button("OK") { appState.showError = false }
                } message: {
                    Text(appState.errorMessage ?? "An unknown error occurred.")
                }
        }
    }
}
