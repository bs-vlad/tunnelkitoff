import Foundation

// Label -> Name
// Description -> Kind
// Service -> Where
// Account -> Account

/// Error raised by `Keychain` methods.
public enum KeychainError: Error {

    /// Unable to add.
    case add

    /// Item not found.
    case notFound

    /// Operation cancelled or unauthorized.
    case userCancelled

//    /// Unexpected item type returned.
//    case typeMismatch
}

/// Wrapper for easy keychain access and modification.
public class Keychain {
    private let accessGroup: String?

    /**
     Creates a keychain.

     - Parameter group: An optional App Group.
     - Precondition: Proper App Group entitlements (if group is non-nil).
     **/
    public init(group: String?) {
        accessGroup = group
    }

    // MARK: Password

    /**
     Sets a password.

     - Parameter password: The password to set.
     - Parameter username: The username to set the password for.
     - Parameter context: The context.
     - Parameter userDefined: Optional user-defined data.
     - Parameter label: An optional label.
     - Returns: The reference to the password.
     - Throws: `TunnelKitManagerError.keychain` if unable to add the password to the keychain.
     **/
    @discardableResult
    public func set(password: String, for username: String, context: String, userDefined: String? = nil, label: String? = nil) throws -> Data {
        do {
            let currentPassword = try self.password(for: username, context: context)
            guard password != currentPassword else {
                return try passwordReference(for: username, context: context)
            }
            removePassword(for: username, context: context)
        } catch let error as TunnelKitManagerError {

            // this is a well-known error from password() or passwordReference(), keep going

            // rethrow cancellation
            if case .keychain(.userCancelled) = error {
                throw error
            }

            // otherwise, no pre-existing password
        } catch {

            // IMPORTANT: rethrow any other unknown error (leave this code explicit)
            throw error
        }

        var query = [String: Any]()
        setScope(query: &query, context: context, userDefined: userDefined)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrLabel as String] = label
        query[kSecAttrAccount as String] = username
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = password.data(using: .utf8)
        query[kSecReturnPersistentRef as String] = true

        var ref: CFTypeRef?
        let status = SecItemAdd(query as CFDictionary, &ref)
        guard status == errSecSuccess, let refData = ref as? Data else {
            throw TunnelKitManagerError.keychain(.add)
        }
        return refData
    }

    /**
     Removes a password.

     - Parameter username: The username to remove the password for.
     - Parameter context: The context.
     - Parameter userDefined: Optional user-defined data.
     - Returns: `true` if the password was successfully removed.
     **/
    @discardableResult public func removePassword(for username: String, context: String, userDefined: String? = nil) -> Bool {
        var query = [String: Any]()
        setScope(query: &query, context: context, userDefined: userDefined)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrAccount as String] = username

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }

    /**
     Gets a password.

     - Parameter username: The username to get the password for.
     - Parameter context: The context.
     - Parameter userDefined: Optional user-defined data.
     - Returns: The password for the input username.
     - Throws: `TunnelKitManagerError.keychain` if unable to find the password in the keychain.
     **/
    public func password(for username: String, context: String, userDefined: String? = nil) throws -> String {
        var query = [String: Any]()
        setScope(query: &query, context: context, userDefined: userDefined)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrAccount as String] = username
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            break

        case errSecUserCanceled:
            throw TunnelKitManagerError.keychain(.userCancelled)

        default:
            throw TunnelKitManagerError.keychain(.notFound)
        }
        guard let data = result as? Data else {
            throw TunnelKitManagerError.keychain(.notFound)
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw TunnelKitManagerError.keychain(.notFound)
        }
        return password
    }

    /**
     Gets a password reference.

     - Parameter username: The username to get the password for.
     - Parameter context: The context.
     - Parameter userDefined: Optional user-defined data.
     - Returns: The password reference for the input username.
     - Throws: `TunnelKitManagerError.keychain` if unable to find the password in the keychain.
     **/
    public func passwordReference(for username: String, context: String, userDefined: String? = nil) throws -> Data {
        var query = [String: Any]()
        setScope(query: &query, context: context, userDefined: userDefined)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrAccount as String] = username
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnPersistentRef as String] = true

        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            break

        case errSecUserCanceled:
            throw TunnelKitManagerError.keychain(.userCancelled)

        default:
            throw TunnelKitManagerError.keychain(.notFound)
        }
        guard let data = result as? Data else {
            throw TunnelKitManagerError.keychain(.notFound)
        }
        return data
    }

    /**
     Gets a password associated with a password reference.

     - Parameter reference: The password reference.
     - Returns: The password for the input reference.
     - Throws: `TunnelKitManagerError.keychain` if unable to find the password in the keychain.
     **/
    public static func password(forReference reference: Data) throws -> String {
        var query = [String: Any]()
        query[kSecValuePersistentRef as String] = reference
        query[kSecReturnData as String] = true

        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            break

        case errSecUserCanceled:
            throw TunnelKitManagerError.keychain(.userCancelled)

        default:
            throw TunnelKitManagerError.keychain(.notFound)
        }
        guard let data = result as? Data else {
            throw TunnelKitManagerError.keychain(.notFound)
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw TunnelKitManagerError.keychain(.notFound)
        }
        return password
    }

    // MARK: Key

    // https://forums.developer.apple.com/thread/13748

    /**
     Adds a public key.

     - Parameter identifier: The unique identifier.
     - Parameter data: The public key data.
     - Returns: The `SecKey` object representing the public key.
     - Throws: `TunnelKitManagerError.keychain` if unable to add the public key to the keychain.
     **/
    public func add(publicKeyWithIdentifier identifier: String, data: Data) throws -> SecKey {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassKey
        query[kSecAttrApplicationTag as String] = identifier
        query[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        query[kSecAttrKeyClass as String] = kSecAttrKeyClassPublic
        query[kSecValueData as String] = data

        // XXX
        query.removeValue(forKey: kSecAttrService as String)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TunnelKitManagerError.keychain(.add)
        }
        return try publicKey(withIdentifier: identifier)
    }

    /**
     Gets a public key.

     - Parameter identifier: The unique identifier.
     - Returns: The `SecKey` object representing the public key.
     - Throws: `TunnelKitManagerError.keychain` if unable to find the public key in the keychain.
     **/
    public func publicKey(withIdentifier identifier: String) throws -> SecKey {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassKey
        query[kSecAttrApplicationTag as String] = identifier
        query[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        query[kSecAttrKeyClass as String] = kSecAttrKeyClassPublic
        query[kSecReturnRef as String] = true

        // XXX
        query.removeValue(forKey: kSecAttrService as String)

        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            break

        case errSecUserCanceled:
            throw TunnelKitManagerError.keychain(.userCancelled)

        default:
            throw TunnelKitManagerError.keychain(.notFound)
        }
//        guard let key = result as? SecKey else {
//            throw TunnelKitManagerError.keychain(.typeMismatch)
//        }
//        return key
        return result as! SecKey
    }

    /**
     Removes a public key.

     - Parameter identifier: The unique identifier.
     - Returns: `true` if the public key was successfully removed.
     **/
    @discardableResult public func remove(publicKeyWithIdentifier identifier: String) -> Bool {
        var query = [String: Any]()
        query[kSecClass as String] = kSecClassKey
        query[kSecAttrApplicationTag as String] = identifier
        query[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        query[kSecAttrKeyClass as String] = kSecAttrKeyClassPublic

        // XXX
        query.removeValue(forKey: kSecAttrService as String)

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }

    // MARK: Helpers

        public func setScope(query: inout [String: Any], context: String, userDefined: String?) {
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
            #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = true
            #endif
        }
        query[kSecAttrService as String] = context
        if let userDefined = userDefined {
            query[kSecAttrGeneric as String] = userDefined
        }
    }
}
