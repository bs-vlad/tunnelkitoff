
import Foundation

/// Encapsulates the IPv4 settings for the tunnel.
public struct IPv4Settings: Codable, Equatable, CustomStringConvertible {

    /// Represents an IPv4 route in the routing table.
    public struct Route: Codable, Hashable, CustomStringConvertible {

        /// The destination host or subnet.
        public let destination: String

        /// The address mask.
        public let mask: String

        /// The address of the gateway (falls back to global gateway).
        public let gateway: String?

        public init(_ destination: String, _ mask: String?, _ gateway: String?) {
            self.destination = destination
            self.mask = mask ?? "255.255.255.255"
            self.gateway = gateway
        }

        // MARK: CustomStringConvertible

        public var description: String {
            "{\(destination)/\(mask) \(gateway?.description ?? "*")}"
        }
    }

    /// The address.
    public let address: String

    /// The address mask.
    public let addressMask: String

    /// The address of the default gateway.
    public let defaultGateway: String

    public init(address: String, addressMask: String, defaultGateway: String) {
        self.address = address
        self.addressMask = addressMask
        self.defaultGateway = defaultGateway
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "addr \(address) netmask \(addressMask) gw \(defaultGateway)"
    }
}
