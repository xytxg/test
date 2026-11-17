import Foundation
import Security

enum SourceSecrets {
    static func read(_ id: String) throws -> [String: JSONValue] {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.xylyra.webox.source", kSecAttrAccount as String: id, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else { throw WeBoxError("无法读取源的私密配置：\(status)") }
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }
    static func write(_ values: [String: JSONValue], id: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.xylyra.webox.source", kSecAttrAccount as String: id]
        if values.isEmpty { SecItemDelete(query as CFDictionary); return }
        let data = try JSONEncoder().encode(values)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw WeBoxError("保存私密配置失败：\(update)") }
        var attributes = query; attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw WeBoxError("保存私密配置失败：\(status)") }
    }
}
