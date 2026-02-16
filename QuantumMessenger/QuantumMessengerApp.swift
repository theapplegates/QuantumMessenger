import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
@main
struct QuantumMessengerApp: App {
    @State private var appState = AppState()

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
