

import Foundation
import TunnelKitOpenVPNCore

/// The errors causing a tunnel disconnection.
public enum TunnelKitOpenVPNError: String, Error {

    /// Socket endpoint could not be resolved.
    case dnsFailure

    /// No more endpoints available to try.
    case exhaustedEndpoints

    /// Socket failed to reach active state.
    case socketActivity

    /// Credentials authentication failed.
    case authentication

    /// TLS could not be initialized (e.g. malformed CA or client PEMs).
    case tlsInitialization

    /// TLS server verification failed.
    case tlsServerVerification

    /// TLS handshake failed.
    case tlsHandshake

    /// The encryption logic could not be initialized (e.g. PRNG, algorithms).
    case encryptionInitialization

    /// Data encryption/decryption failed.
    case encryptionData

    /// The LZO engine failed.
    case lzo

    /// Server uses an unsupported compression algorithm.
    case serverCompression

    /// Tunnel timed out.
    case timeout

    /// An error occurred at the link level.
    case linkError

    /// Network routing information is missing or incomplete.
    case routing

    /// The current network changed (e.g. switched from WiFi to data connection).
    case networkChanged

    /// Default gateway could not be attained.
    case gatewayUnattainable

    /// Remove server has shut down.
    case serverShutdown

    /// The server replied in an unexpected way.
    case unexpectedReply
}
