

import Foundation

/// A socket type between UDP (recommended) and TCP.
public enum SocketType: String {

    /// UDP socket type.
    case udp = "UDP"

    /// TCP socket type.
    case tcp = "TCP"

    /// UDP socket type (IPv4).
    case udp4 = "UDP4"

    /// TCP socket type (IPv4).
    case tcp4 = "TCP4"

    /// UDP socket type (IPv6).
    case udp6 = "UDP6"

    /// TCP socket type (IPv6).
    case tcp6 = "TCP6"
}
