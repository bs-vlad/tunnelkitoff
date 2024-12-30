

import Foundation

/// Represents a specific I/O interface meant to work at the tunnel layer (e.g. VPN).
public protocol TunnelInterface: IOInterface {

    /// When `true`, interface survives sessions.
    var isPersistent: Bool { get }
}
