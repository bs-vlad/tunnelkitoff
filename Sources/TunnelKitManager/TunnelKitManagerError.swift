
import Foundation

/// Errors returned by Core library.
public enum TunnelKitManagerError: Error {
    case keychain(_ error: KeychainError)
}
