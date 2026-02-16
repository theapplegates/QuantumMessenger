import SwiftUI
import CryptoKit

@available(iOS 26.0, macOS 26.0, *)
struct KeyManagementView: View {
    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirmation = false
    @State private var selfTestResult: (success: Bool, detail: String)?
    @State private var showSelfTest = false
    @State private var copiedPublicKey = false

    var body: some View {
        NavigationStack {
            List {
                // Key Status Section
                Section {
                    if appState.hasKeyPair {
                        keyInfoSection
                    } else {
                        noKeySection
                    }
                } header: {
                    Label("Your X-Wing Key Pair", systemImage: "key.fill")
                }

                // Key Actions Section
                Section {
                    if appState.hasKeyPair {
                        // Share public key
                        Button {
                            copyPublicKey()
                        } label: {
                            Label(
                                copiedPublicKey ? "Copied!" : "Copy Public Key",
                                systemImage: copiedPublicKey ? "checkmark.circle.fill" : "doc.on.doc"
                            )
                        }

                        // Self-test
                        Button {
                            selfTestResult = appState.runSelfTest()
                            showSelfTest = true
                        } label: {
                            Label("Run Self-Test", systemImage: "checkmark.shield")
                        }

                        // Delete key pair
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Key Pair", systemImage: "trash")
                        }
                    } else {
                        Button {
                            appState.generateNewKeyPair()
                        } label: {
                            Label("Generate Key Pair", systemImage: "key.fill")
                        }
                        .tint(.blue)
                    }
                } header: {
                    Label("Actions", systemImage: "gearshape")
                }

                // Crypto Info Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Algorithm", value: "X-Wing Hybrid KEM")
                        infoRow("Post-Quantum", value: "ML-KEM-768 (FIPS 203)")
                        infoRow("Classical", value: "X25519 (Curve25519)")
                        infoRow("HPKE KDF", value: "HKDF-SHA256")
                        infoRow("HPKE AEAD", value: "AES-GCM-256")
                        infoRow("Public Key Size", value: "1,216 bytes")
                        infoRow("Ciphertext Overhead", value: "1,120 bytes")
                        infoRow("Shared Secret", value: "32 bytes")
                    }
                    .font(.caption)
                } header: {
                    Label("Encryption Details", systemImage: "lock.shield")
                }
            }
            .navigationTitle("Keys")
            .confirmationDialog(
                "Delete Key Pair?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    appState.deleteKeyPair()
                }
            } message: {
                Text("This will permanently delete your private key. You will not be able to decrypt any messages encrypted with this key pair.")
            }
            .alert("Self-Test Result", isPresented: $showSelfTest) {
                Button("OK") { }
            } message: {
                if let result = selfTestResult {
                    Text(result.success ? "PASSED\n\n\(result.detail)" : "FAILED\n\n\(result.detail)")
                }
            }
        }
    }

    // MARK: - Subviews

    private var keyInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                Text("Key Pair Active")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            if let publicKeyBase64 = appState.publicKeyBase64 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Public Key (Base64)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(publicKeyBase64.prefix(48)) + "...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var noKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text("No Key Pair")
                    .font(.headline)
            }
            Text("Generate a key pair to start sending and receiving post-quantum encrypted messages.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Actions

    private func copyPublicKey() {
        guard let key = appState.publicKeyBase64 else { return }
        UIPasteboard.general.string = key
        copiedPublicKey = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedPublicKey = false
        }
    }
}
