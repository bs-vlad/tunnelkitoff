
import Foundation

/// Encapsulates a proxy setting.
public struct Proxy: Codable, Equatable, RawRepresentable, CustomStringConvertible {

    /// The proxy address.
    public let address: String

    /// The proxy port.
    public let port: UInt16

    public init(_ address: String, _ port: UInt16) {
        self.address = address
        self.port = port
    }

    // MARK: RawRepresentable

    public var rawValue: String {
        return "\(address):\(port)"
    }

    public init?(rawValue: String) {
        let comps = rawValue.components(separatedBy: ":")
        guard comps.count == 2, let port = UInt16(comps[1]) else {
            return nil
        }
        self.init(comps[0], port)
    }

    // MARK: CustomStringConvertible

    public var description: String {
        return rawValue
    }
}
