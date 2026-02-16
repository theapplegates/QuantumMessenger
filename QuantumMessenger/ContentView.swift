import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Inbox", systemImage: "envelope.fill", value: 0) {
                InboxView()
            }
            .badge(badgeCount)

            Tab("Compose", systemImage: "square.and.pencil", value: 1) {
                ComposeView()
            }

            Tab("Keys", systemImage: "key.fill", value: 2) {
                KeyManagementView()
            }
        }
    }

    @Environment(AppState.self) private var appState

    private var badgeCount: Int {
        appState.messages.filter { !$0.isDecrypted }.count
    }
}
