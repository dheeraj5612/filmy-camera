import Foundation
import Security

protocol PhotoQuotaPersistence {
    func load() throws -> DailyPhotoQuota?
    func save(_ quota: DailyPhotoQuota) throws
}

struct KeychainPhotoQuotaPersistence: PhotoQuotaPersistence {
    enum Failure: Error { case keychain(OSStatus), invalidRecord }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.dheeraj.filmycamera.daily-photo-quota.v1",
         kSecAttrAccount as String: "device"]
    }

    func load() throws -> DailyPhotoQuota? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = result as? Data,
              let quota = try? JSONDecoder().decode(DailyPhotoQuota.self, from: data), quota.isValid else {
            throw Failure.invalidRecord
        }
        return quota
    }

    func save(_ quota: DailyPhotoQuota) throws {
        let data = try JSONEncoder().encode(quota)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(request as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Failure.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw Failure.keychain(status)
        }
    }
}

/// Used by unit tests only; test state never touches the device's real budget.
final class MemoryPhotoQuotaPersistence: PhotoQuotaPersistence {
    var quota: DailyPhotoQuota?
    func load() throws -> DailyPhotoQuota? { quota }
    func save(_ quota: DailyPhotoQuota) throws { self.quota = quota }
}
