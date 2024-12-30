
import Foundation

/// Errors returned by Core library.
public enum TunnelKitCoreError: Error {
    case secureRandom(_ error: SecureRandomError)

    case dnsResolver(_ error: DNSError)
}
