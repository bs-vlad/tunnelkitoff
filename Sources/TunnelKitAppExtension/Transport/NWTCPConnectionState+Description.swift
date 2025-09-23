
import Foundation
import NetworkExtension

extension NWTCPConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cancelled: return "cancelled"
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .disconnected: return "disconnected"
        case .invalid: return "invalid"
        case .waiting: return "waiting"
        @unknown default: return "???"
        }
    }
}
