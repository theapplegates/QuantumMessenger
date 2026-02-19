import SwiftUI
import CryptoKit

@available(iOS 26.0, macOS 26.0, *)
struct ComposeView: View {
    @Environment(AppState.self) private var appState
    @State private var messageText = ""
    @State private var selectedContact: Contact?
    @State private var encryptedOutput: String?
    @State private var showContactPicker = false
    @State private var showAddContact = false
    @State private var copiedOutput = false
    @State private var signMessage = true

    // Add Contact fields
    @State private var newContactName = ""
    @State private var newContactKey = ""
    @State private var newContactSigningKey = ""

    var body: some View {
        NavigationStack {
            Form {
                // Recipient Section
                Section {
                    if let contact = selectedContact {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(contact.name)
                                    .font(.headline)
                                Text("Key: \(contact.keyFingerprint)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fontDesign(.monospaced)
                            }
                            Spacer()
                            Button("Change") {
                                showContactPicker = true
                            }
                            .font(.caption)
                        }
                    } else {
                        Button {
                            if appState.contacts.isEmpty {
                                showAddContact = true
                            } else {
                                showContactPicker = true
                            }
                        } label: {
                            Label("Select Recipient", systemImage: "person.circle")
                        }
                    }
                } header: {
                    Text("Recipient")
                }

                // Message Section
                Section {
                    TextEditor(text: $messageText)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if messageText.isEmpty {
                                Text("Type your message here...")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Message")
                }

                // Signing toggle
                Section {
                    Toggle(isOn: $signMessage) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign with ML-DSA-65")
                                    .font(.body)
                                Text(appState.hasSigningKeyPair
                                    ? "Adds post-quantum signature for authenticity"
                                    : "No signing key — generate one in Keys tab")
                                    .font(.caption)
                                    .foregroundStyle(appState.hasSigningKeyPair ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                            }
                        } icon: {
                            Image(systemName: "signature")
                        }
                    }
                    .disabled(!appState.hasSigningKeyPair)
                } header: {
                    Text("Security Options")
                }

                // Encrypt Button
                Section {
                    Button {
                        encryptMessage()
                    } label: {
                        HStack {
                            Spacer()
                            Label(
                                signMessage && appState.hasSigningKeyPair
                                    ? "Encrypt & Sign"
                                    : "Encrypt Message",
                                systemImage: signMessage && appState.hasSigningKeyPair
                                    ? "lock.and.key.fill"
                                    : "lock.fill"
                            )
                            .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(selectedContact == nil || messageText.isEmpty || !appState.hasKeyPair)
                }

                // Encrypted Output
                if let output = encryptedOutput {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(.green)
                                Text("Encrypted Successfully")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                            }

                            HStack(spacing: 8) {
                                Text("XWing · AES-GCM-256")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if signMessage && appState.hasSigningKeyPair {
                                    Label("Signed", systemImage: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }

                            Text(String(output.prefix(200)) + "...")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(6)

                            Button {
                                UIPasteboard.general.string = output
                                copiedOutput = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedOutput = false
                                }
                            } label: {
                                Label(
                                    copiedOutput ? "Copied!" : "Copy Encrypted Message",
                                    systemImage: copiedOutput ? "checkmark.circle.fill" : "doc.on.doc"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(copiedOutput ? .green : .blue)
                        }
                    } header: {
                        Text("Encrypted Output")
                    }
                }
            }
            .navigationTitle("Compose")
            .sheet(isPresented: $showContactPicker) {
                contactPickerSheet
            }
            .sheet(isPresented: $showAddContact) {
                addContactSheet
            }
        }
    }

    // MARK: - Sheets

    private var contactPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(appState.contacts) { contact in
                    Button {
                        selectedContact = contact
                        showContactPicker = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(contact.name)
                                .font(.headline)
                            Text("Key: \(contact.keyFingerprint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontDesign(.monospaced)
                        }
                    }
                }

                Button {
                    showContactPicker = false
                    showAddContact = true
                } label: {
                    Label("Add New Contact", systemImage: "plus.circle")
                }
            }
            .navigationTitle("Select Recipient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showContactPicker = false }
                }
            }
        }
    }

    private var addContactSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Contact Name", text: $newContactName)
                } header: {
                    Text("Name")
                }

                Section {
                    TextEditor(text: $newContactKey)
                        .frame(minHeight: 80)
                        .fontDesign(.monospaced)
                        .font(.caption)
                } header: {
                    Text("X-Wing Public Key (Base64)")
                } footer: {
                    Text("Paste the recipient's X-Wing encryption public key in Base64 format.")
                }

                Section {
                    TextEditor(text: $newContactSigningKey)
                        .frame(minHeight: 60)
                        .fontDesign(.monospaced)
                        .font(.caption)
                } header: {
                    Text("ML-DSA-65 Signing Key (Base64, Optional)")
                } footer: {
                    Text("Paste the recipient's ML-DSA-65 signing public key to enable signature verification.")
                }

                Section {
                    Button("Add Contact") {
                        appState.addContact(
                            name: newContactName,
                            publicKeyBase64: newContactKey,
                            signingPublicKeyBase64: newContactSigningKey.isEmpty ? nil : newContactSigningKey
                        )
                        if !appState.showError {
                            selectedContact = appState.contacts.last
                            newContactName = ""
                            newContactKey = ""
                            newContactSigningKey = ""
                            showAddContact = false
                        }
                    }
                    .disabled(newContactName.isEmpty || newContactKey.isEmpty)
                }
            }
            .navigationTitle("Add Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newContactName = ""
                        newContactKey = ""
                        newContactSigningKey = ""
                        showAddContact = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func encryptMessage() {
        guard let contact = selectedContact else { return }
        let shouldSign = signMessage && appState.hasSigningKeyPair
        guard let envelope = appState.encryptMessage(to: contact, plaintext: messageText, withSignature: shouldSign) else {
            return
        }
        if let base64 = try? envelope.toBase64String() {
            encryptedOutput = base64
        }
    }
}
