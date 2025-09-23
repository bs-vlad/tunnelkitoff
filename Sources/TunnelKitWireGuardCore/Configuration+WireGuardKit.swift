
import Foundation
import WireGuardKit

extension WireGuard.Configuration {
    public init(wgQuickConfig: String) throws {
        tunnelConfiguration = try TunnelConfiguration(fromWgQuickConfig: wgQuickConfig)
    }

    public func asWgQuickConfig() -> String {
        tunnelConfiguration.asWgQuickConfig()
    }

    public var endpointRepresentation: String {
        let endpoints = tunnelConfiguration.peers.compactMap { $0.endpoint }
        if endpoints.count == 1 {
            return endpoints[0].stringRepresentation
        } else if endpoints.isEmpty {
            return "Unspecified"
        } else {
            return "Multiple endpoints"
        }
    }
}
