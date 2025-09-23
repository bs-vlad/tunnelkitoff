

import Foundation

/// Encapsulates the IPv6 settings for the tunnel.
public struct IPv6Settings: Codable, Equatable, CustomStringConvertible {

    /// Represents an IPv6 route in the routing table.
    public struct Route: Codable, Hashable, CustomStringConvertible {

        /// The destination host or subnet.
        public let destination: String

        /// The address prefix length.
        public let prefixLength: UInt8

        /// The address of the gateway (falls back to global gateway).
        public let gateway: String?

        public init(_ destination: String, _ prefixLength: UInt8?, _ gateway: String?) {
            self.destination = destination
            self.prefixLength = prefixLength ?? 3
            self.gateway = gateway
        }

        // MARK: CustomStringConvertible

        public var description: String {
            "{\(destination.maskedDescription)/\(prefixLength) \(gateway?.maskedDescription ?? "*")}"
        }
    }

    /// The address.
    public let address: String

    /// The address prefix length.
    public let addressPrefixLength: UInt8

    /// The address of the default gateway.
    public let defaultGateway: String

    public init(address: String, addressPrefixLength: UInt8, defaultGateway: String) {
        self.address = address
        self.addressPrefixLength = addressPrefixLength
        self.defaultGateway = defaultGateway
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "addr \(address)/\(addressPrefixLength) gw \(defaultGateway)"
    }
}
