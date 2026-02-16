import SwiftUI
import CryptoKit

@available(iOS 26.0, macOS 26.0, *)
struct InboxView: View {
    @Environment(AppState.self) private var appState
    @State private var showReceiveSheet = false
    @State private var incomingSenderName = ""
    @State private var incomingBase64 = ""

    var body: some View {
        NavigationStack {
            Group {
                if appState.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showReceiveSheet = true
                    } label: {
                        Image(systemName: "envelope.badge.fill")
                    }
                }
            }
            .sheet(isPresented: $showReceiveSheet) {
                receiveMessageSheet
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Messages", systemImage: "envelope.open")
        } description: {
            Text("Encrypted messages you receive will appear here. Tap the envelope icon to paste an incoming message.")
        }
    }

    private var messageList: some View {
        List {
            ForEach(appState.messages) { message in
                MessageRow(message: message) {
                    appState.decryptMessage(message)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    appState.deleteMessage(appState.messages[index])
                }
            }
        }
    }

    private var receiveMessageSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sender Name", text: $incomingSenderName)
                } header: {
                    Text("From")
                }

                Section {
                    TextEditor(text: $incomingBase64)
                        .frame(minHeight: 120)
                        .fontDesign(.monospaced)
                        .font(.caption)
                } header: {
                    Text("Encrypted Message (Base64)")
                } footer: {
                    Text("Paste the Base64-encoded encrypted envelope you received.")
                }

                Section {
                    Button {
                        appState.receiveMessage(
                            senderName: incomingSenderName,
                            base64Envelope: incomingBase64
                        )
                        if !appState.showError {
                            incomingSenderName = ""
                            incomingBase64 = ""
                            showReceiveSheet = false
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Import Message", systemImage: "envelope.arrow.triangle.branch")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(incomingSenderName.isEmpty || incomingBase64.isEmpty)
                }
            }
            .navigationTitle("Receive Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        incomingSenderName = ""
                        incomingBase64 = ""
                        showReceiveSheet = false
                    }
                }
            }
        }
    }
}

// MARK: - Message Row

@available(iOS 26.0, macOS 26.0, *)
struct MessageRow: View {
    let message: EncryptedMessage
    let onDecrypt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: message.isDecrypted ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(message.isDecrypted ? .green : .orange)
                Text(message.senderName)
                    .font(.headline)
                Spacer()
                Text(message.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Content
            if let decrypted = message.decryptedContent {
                Text(decrypted)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.ciphertextPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        onDecrypt()
                    } label: {
                        Label("Decrypt", systemImage: "key.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
