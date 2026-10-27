import Foundation
import Security
import ShellRSCore

/// The keychain the core keeps passwords in: a generic password per
/// account the core names (the desktop's accounts), under the app's own
/// service.
///
/// Readable once the iPhone has been unlocked after it started, so a sync
/// in the background can read them; never restored to another device from
/// a backup, as ShellRS's own sync carries them there.
final class AppKeychain: Keychain {
    static let appService = "com.shellrs.ios"

    let service: String

    init(service: String = AppKeychain.appService) {
        self.service = service
    }

    func available() -> Bool {
        true
    }

    func get(account: String) throws -> String? {
        var query = item(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        switch status {
        case errSecSuccess:
            guard let data = found as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.Failed(detail: "the item is not text")
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw Self.error(status)
        }
    }

    func set(account: String, value: String) throws {
        let data = Data(value.utf8)
        let change: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(item(account) as CFDictionary, change as CFDictionary)
        if status == errSecItemNotFound {
            let new = item(account).merging(change) { _, new in new }
            status = SecItemAdd(new as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw Self.error(status)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(item(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.error(status)
        }
    }

    private func item(_ account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    /// A keychain that cannot be read now, such as before the first unlock,
    /// is unavailable rather than broken: the core asks again later.
    private static func error(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecInteractionNotAllowed, errSecNotAvailable:
            return .Unavailable
        default:
            let message = SecCopyErrorMessageString(status, nil) as String?
            return .Failed(detail: message ?? "OSStatus \(status)")
        }
    }
}
