import Foundation
import Security

nonisolated struct KeychainStore: Sendable {
    var service: String

    init(service: String = "com.martvanderzalm.TradeCompanion.bybit.demo") {
        self.service = service
    }

    func saveDemoCredentials(apiKey: String, apiSecret: String) throws {
        try setPassword(apiKey, account: "apiKey")
        try setPassword(apiSecret, account: "apiSecret")
    }

    func loadDemoCredentials() -> BybitCredentials? {
        guard
            let apiKey = password(account: "apiKey"),
            let apiSecret = password(account: "apiSecret")
        else {
            return nil
        }
        let credentials = BybitCredentials(apiKey: apiKey, apiSecret: apiSecret)
        return credentials.isComplete ? credentials : nil
    }

    func hasDemoCredentials() -> Bool {
        loadDemoCredentials() != nil
    }

    func deleteDemoCredentials() throws {
        try deletePassword(account: "apiKey")
        try deletePassword(account: "apiSecret")
    }

    private func setPassword(_ value: String, account: String) throws {
        try deletePassword(account: account)
        let payload = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    private func password(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

nonisolated enum KeychainError: Error {
    case unhandled(OSStatus)
}
