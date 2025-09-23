
import Foundation
import TunnelKitOpenVPNAppExtension

class PacketTunnelProvider: OpenVPNTunnelProvider {
    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        dataCountInterval = 3
        try await super.startTunnel(options: options)
    }
}
