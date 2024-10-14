
import Foundation

/// Status of a `VPN`.
public enum VPNStatus: String {

    /// VPN is connected.
    case connected

    /// VPN is attempting a connection.
    case connecting

    /// VPN is disconnected.
    case disconnected

    /// VPN is completing a disconnection.
    case disconnecting
}
