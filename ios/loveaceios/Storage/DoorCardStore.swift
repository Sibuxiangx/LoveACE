import Foundation
import Security

final class DoorCardStore: Sendable {
    private static let serviceName = "tech.loveace.loveaceios.doorcard"

    func saveCredentials(appUserId: String, credentials: DoorCardCredentials) {
        if let data = try? JSONEncoder().encode(credentials) {
            setKeychainData(data, forKey: "\(appUserId)_dc_creds")
        }
    }

    func loadCredentials(appUserId: String) -> DoorCardCredentials? {
        guard let data = getKeychainData(forKey: "\(appUserId)_dc_creds") else { return nil }
        return try? JSONDecoder().decode(DoorCardCredentials.self, from: data)
    }

    func saveUserInfo(appUserId: String, userInfo: DoorCardUserInfo) {
        if let data = try? JSONEncoder().encode(userInfo) {
            setKeychainData(data, forKey: "\(appUserId)_dc_user")
        }
    }

    func loadUserInfo(appUserId: String) -> DoorCardUserInfo? {
        guard let data = getKeychainData(forKey: "\(appUserId)_dc_user") else { return nil }
        return try? JSONDecoder().decode(DoorCardUserInfo.self, from: data)
    }

    func isBound(appUserId: String) -> Bool { getKeychainData(forKey: "\(appUserId)_dc_creds") != nil }

    func unbind(appUserId: String) {
        deleteKeychainData(forKey: "\(appUserId)_dc_creds")
        deleteKeychainData(forKey: "\(appUserId)_dc_user")
    }

    private func setKeychainData(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var newItem = query
        newItem[kSecValueData as String] = data
        SecItemAdd(newItem as CFDictionary, nil)
    }

    private func getKeychainData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteKeychainData(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
