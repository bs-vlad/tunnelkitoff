
import Foundation

/// The protocol used in DNS servers.
public enum DNSProtocol: String, Codable {

    /// The value to fall back to when unset.
    public static let fallback: DNSProtocol = .plain

    /// Standard plaintext DNS (port 53).
    case plain

    /// DNS over HTTPS.
    case https

    /// DNS over TLS (port 853).
    case tls
}
