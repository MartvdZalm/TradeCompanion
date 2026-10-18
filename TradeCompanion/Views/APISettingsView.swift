import SwiftUI

struct APISettingsView: View {
    var model: TradePlannerViewModel
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var status = ""
    @State private var keysSaved = false

    private let keychain = KeychainStore()

    var body: some View {
        Form {
            Section {
                Text("Create the key from Bybit EU Demo Trading, not from live or testnet. Required permissions: read account/orders and create orders (spot trading). Do not enable withdrawals.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Bybit Demo API") {
                TextField("API key", text: $apiKey)
                    .textContentType(.username)
                SecureField("API secret", text: $apiSecret)
                    .textContentType(.password)
                if keysSaved {
                    Text("A Demo key is stored in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Save to Keychain") {
                    save()
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Delete stored keys", role: .destructive) {
                    deleteKeys()
                }
                Button("Connect to Demo") {
                    Task {
                        await model.connect()
                        status = model.connectionDetail
                    }
                }
            }

            if !status.isEmpty {
                Section("Status") {
                    Text(status)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .onAppear {
            keysSaved = keychain.hasDemoCredentials()
            if keysSaved {
                status = "Keys are stored locally. The secret is not shown again."
            }
        }
    }

    private func save() {
        do {
            try keychain.saveDemoCredentials(
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            apiSecret = ""
            keysSaved = true
            model.refreshCredentialPresence()
            status = "Demo API keys saved to Keychain. They are only used against api-demo.bybit.eu."
        } catch {
            status = "Could not save keys: \(error.localizedDescription)"
        }
    }

    private func deleteKeys() {
        do {
            try keychain.deleteDemoCredentials()
            apiKey = ""
            apiSecret = ""
            keysSaved = false
            model.refreshCredentialPresence()
            status = "Stored Demo keys were removed."
        } catch {
            status = "Could not delete keys: \(error.localizedDescription)"
        }
    }
}
