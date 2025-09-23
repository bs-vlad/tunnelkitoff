
import Foundation
import NetworkExtension

extension NWUDPSessionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        case .invalid: return "invalid"
        case .preparing: return "preparing"
        case .ready: return "ready"
        case .waiting: return "waiting"
        @unknown default: return "???"
        }
    }
}
