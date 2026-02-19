import SwiftUI
import CryptoKit

// MARK: - KeyManagementView

@available(iOS 26.0, macOS 26.0, *)
struct KeyManagementView: View {
    @Environment(AppState.self) private var appState
    @State private var showKeyDetails = false
    @State private var showDeleteConfirmation = false
    @State private var selfTestResult: (success: Bool, detail: String)?
    @State private var showSelfTest = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Identity card
                    IdentityCard()
                    // Key status
                    if appState.hasAllKeys {
                        KeyStatusCard(
                            onViewDetails: { showKeyDetails = true },
                            onSelfTest: {
                                selfTestResult = appState.runSelfTest()
                                showSelfTest = true
                            },
                            onDelete: { showDeleteConfirmation = true }
                        )
                    } else {
                        GenerateKeyCard()
                    }
                    // Algorithm info
                    AlgorithmInfoCard()
                }
                .padding()
            }
            .navigationTitle("Keys")
            .sheet(isPresented: $showKeyDetails) {
                KeyDetailsSheet()
            }
            .confirmationDialog(
                "Delete Key Pair?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    appState.deleteKeyPair()
                }
            } message: {
                Text("This will permanently delete your private keys. You will not be able to decrypt any messages encrypted with this key pair.")
            }
            .alert("Self-Test Result", isPresented: $showSelfTest) {
                Button("OK") {}
            } message: {
                if let result = selfTestResult {
                    Text(result.success ? "✅ PASSED\n\n\(result.detail)" : "❌ FAILED\n\n\(result.detail)")
                }
            }
        }
    }
}

// MARK: - Identity Card

@available(iOS 26.0, macOS 26.0, *)
private struct IdentityCard: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focusedField: IdentityField?

    enum IdentityField { case name, email }

    var body: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Identity", systemImage: "person.crop.circle")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Your Name", text: $state.userName)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }
            }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("you@example.com", text: $state.userEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            }

            if !appState.userId.isEmpty {
                Text("User ID: \(appState.userId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Generate Key Card

@available(iOS 26.0, macOS 26.0, *)
private struct GenerateKeyCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Key Pair")
                        .font(.headline)
                    Text("Generate a key pair to begin sending and receiving post-quantum encrypted messages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                appState.generateNewKeyPair()
            } label: {
                Label("Generate Key Pair", systemImage: "key.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Key Status Card

@available(iOS 26.0, macOS 26.0, *)
private struct KeyStatusCard: View {
    @Environment(AppState.self) private var appState
    let onViewDetails: () -> Void
    let onSelfTest: () -> Void
    let onDelete: () -> Void

    var keyID: String {
        guard let pk = appState.publicKey else { return "—" }
        let data = CryptoService.exportPublicKey(pk)
        return CryptoService.keyID(for: data)
    }

    var fingerprint: String {
        guard let pk = appState.publicKey else { return "—" }
        let data = CryptoService.exportPublicKey(pk)
        return CryptoService.fingerprint(of: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Success banner
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Key Pair Active")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Key ID: \(keyID)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            // Fingerprint
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Wing Fingerprint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(fingerprint)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            if let created = appState.keyCreatedAt {
                HStack {
                    Label("Created", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(appState.keyCreatedAtFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Action buttons
            VStack(spacing: 8) {
                Button {
                    onViewDetails()
                } label: {
                    Label("View Key Details", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                HStack(spacing: 8) {
                    Button {
                        onSelfTest()
                    } label: {
                        Label("Self-Test", systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Algorithm Info Card

private struct AlgorithmInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Algorithm Details", systemImage: "lock.shield")
                .font(.headline)

            Divider()

            VStack(spacing: 6) {
                infoRow("Encryption KEM", "X-Wing (ML-KEM-768 + X25519)")
                infoRow("Post-Quantum Part", "ML-KEM-768 (FIPS 203)")
                infoRow("Classical Part", "X25519 (Curve25519)")
                infoRow("HPKE KDF", "HKDF-SHA256")
                infoRow("HPKE AEAD", "AES-GCM-256")
                infoRow("Signing", "ML-DSA-65 (FIPS 204)")
                infoRow("Public Key Size", "1,216 bytes")
                infoRow("Signing Key Size", "1,952 bytes")
                infoRow("Fingerprint Hash", "SHA-512 (20 bytes)")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Key Details Sheet

@available(iOS 26.0, macOS 26.0, *)
struct KeyDetailsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: KeyTab = .xwing

    enum KeyTab: String, CaseIterable {
        case xwing = "X-Wing"
        case signing = "ML-DSA-65"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header banner
                    keyPairSuccessBanner

                    // Tab picker
                    Picker("Key Type", selection: $selectedTab) {
                        ForEach(KeyTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if selectedTab == .xwing {
                        xwingKeySection
                    } else {
                        signingKeySection
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Key Pair Details")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Banner

    private var keyPairSuccessBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Key Pair Generated Successfully")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                if let pk = appState.publicKey {
                    let data = CryptoService.exportPublicKey(pk)
                    Text("Key ID: \(CryptoService.keyID(for: data))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    // MARK: - X-Wing Section

    private var xwingKeySection: some View {
        VStack(spacing: 16) {
            // User ID
            userIdField

            if let pk = appState.publicKey {
                let data = CryptoService.exportPublicKey(pk)
                let pgp = CryptoService.pgpPublicKeyBlock(
                    keyData: data,
                    userId: appState.userId,
                    validFrom: appState.keyCreatedAtFormatted
                )
                PGPKeyBlock(
                    title: "Public Key",
                    content: pgp,
                    filename: "xwing-public-\(CryptoService.keyID(for: data)).asc"
                )
            }

            // Warning
            privateKeyWarning

            if let sk = appState.privateKey,
               let data = try? CryptoService.exportPrivateKey(sk),
               let pk = appState.publicKey {
                let pubData = CryptoService.exportPublicKey(pk)
                let pgp = CryptoService.pgpPrivateKeyBlock(
                    keyData: data,
                    userId: appState.userId
                )
                PGPKeyBlock(
                    title: "Private Key",
                    content: pgp,
                    filename: "xwing-private-\(CryptoService.keyID(for: pubData)).asc",
                    isPrivate: true
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Signing Section

    private var signingKeySection: some View {
        VStack(spacing: 16) {
            userIdField

            if let pk = appState.signingPublicKey {
                let data = CryptoService.exportSigningPublicKey(pk)
                let pgp = CryptoService.pgpSigningPublicKeyBlock(
                    keyData: data,
                    userId: appState.userId,
                    validFrom: appState.keyCreatedAtFormatted
                )
                PGPKeyBlock(
                    title: "Signing Public Key",
                    content: pgp,
                    filename: "mldsa65-public-\(CryptoService.keyID(for: data)).asc"
                )
            }

            privateKeyWarning

            if let sk = appState.signingPrivateKey,
               let data = try? CryptoService.exportSigningPrivateKey(sk),
               let pk = appState.signingPublicKey {
                let pubData = CryptoService.exportSigningPublicKey(pk)
                let pgp = CryptoService.pgpSigningPrivateKeyBlock(
                    keyData: data,
                    userId: appState.userId
                )
                PGPKeyBlock(
                    title: "Signing Private Key",
                    content: pgp,
                    filename: "mldsa65-private-\(CryptoService.keyID(for: pubData)).asc",
                    isPrivate: true
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Shared Subviews

    private var userIdField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("User ID")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
            Text(appState.userId)
                .font(.system(.subheadline, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var privateKeyWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Private Key — DO NOT SHARE")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                Text("This is your secret key. Keep it safe and never share it with anyone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - PGP Key Block Component

@available(iOS 26.0, macOS 26.0, *)
struct PGPKeyBlock: View {
    let title: String
    let content: String
    let filename: String
    var isPrivate: Bool = false

    @State private var isCopied = false
    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isPrivate ? .orange : .primary)

            ZStack(alignment: .topTrailing) {
                ScrollView {
                    Text(content)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 200)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))

                // Buttons overlay
                HStack(spacing: 6) {
                    // Share / Download
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))

                    // Copy
                    Button {
                        UIPasteboard.general.string = content
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    } label: {
                        Label(
                            isCopied ? "Copied!" : "Copy",
                            systemImage: isCopied ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .tint(isCopied ? .green : .primary)
                }
                .padding(8)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            let fileURL = writeAscFile(content: content, filename: filename)
            if let url = fileURL {
                ShareSheet(items: [url])
            } else {
                ShareSheet(items: [content])
            }
        }
    }

    private func writeAscFile(content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
