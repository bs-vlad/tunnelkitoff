import Foundation
import WireGuardKit
import NetworkExtension
import TunnelKitLogging

private let log = TKLogger.shared

public protocol WireGuardConfigurationProviding {
    var interface: InterfaceConfiguration { get }

    var peers: [PeerConfiguration] { get }

    var privateKey: String { get }

    var publicKey: String { get }

    var addresses: [String] { get }

    var dnsServers: [String] { get }

    var dnsSearchDomains: [String] { get }

    var dnsHTTPSURL: URL? { get }

    var dnsTLSServerName: String? { get }

    var mtu: UInt16? { get }

    var peersCount: Int { get }

    func publicKey(ofPeer peerIndex: Int) -> String

    func preSharedKey(ofPeer peerIndex: Int) -> String?

    func endpoint(ofPeer peerIndex: Int) -> String?

    func allowedIPs(ofPeer peerIndex: Int) -> [String]

    func keepAlive(ofPeer peerIndex: Int) -> UInt16?
}

extension WireGuard {
    /// Split tunneling policy type
    public enum SplitTunnelingPolicy: String, Codable {
        /// Disable split tunneling (route all traffic through VPN)
        case off
        /// Route only specified networks through the VPN
        case include
        /// Route all traffic through VPN except specified networks (TODO)
        case exclude
    }
    
    /// Split tunneling configuration
    public struct SplitTunneling: Codable, Equatable {
        /// The policy for split tunneling
        public let policy: SplitTunnelingPolicy
        /// The list of CIDRs to include/exclude
        public let routes: [String]
        
        public init(policy: SplitTunnelingPolicy, routes: [String]) {
            self.policy = policy
            self.routes = routes
        }
    }

    public struct ConfigurationBuilder: WireGuardConfigurationProviding {
        private static let defaultGateway4 = IPAddressRange(from: "0.0.0.0/0")!

        private static let defaultGateway6 = IPAddressRange(from: "::/0")!

        public private(set) var interface: InterfaceConfiguration

        public private(set) var peers: [PeerConfiguration]

        public init() {
            self.init(PrivateKey())
        }

        public init(_ base64PrivateKey: String) throws {
            guard let privateKey = PrivateKey(base64Key: base64PrivateKey) else {
                log.error("Invalid private key format: \(base64PrivateKey)")
                throw WireGuard.ConfigurationError.interfaceHasInvalidPrivateKey(base64PrivateKey)
            }
            self.init(privateKey)
        }

        private init(_ privateKey: PrivateKey) {
            interface = InterfaceConfiguration(privateKey: privateKey)
            peers = []
        }

        public init(_ tunnelConfiguration: TunnelConfiguration) {
            interface = tunnelConfiguration.interface
            peers = tunnelConfiguration.peers
        }

        // MARK: WireGuardConfigurationProviding

        public var privateKey: String {
            get {
                interface.privateKey.base64Key
            }
            set {
                guard let key = PrivateKey(base64Key: newValue) else {
                    log.error("Failed to set invalid private key: \(newValue)")
                    return
                }
                interface.privateKey = key
            }
        }

        public var addresses: [String] {
            get {
                interface.addresses.map(\.stringRepresentation)
            }
            set {
                let validAddresses = newValue.compactMap(IPAddressRange.init)
                if validAddresses.count != newValue.count {
                    log.warning("Some addresses were invalid and will be ignored")
                }
                interface.addresses = validAddresses
            }
        }

        public var dnsServers: [String] {
            get {
                interface.dns.map(\.stringRepresentation)
            }
            set {
                interface.dns = newValue.compactMap(DNSServer.init)
            }
        }

        public var dnsSearchDomains: [String] {
            get {
                interface.dnsSearch
            }
            set {
                interface.dnsSearch = newValue
            }
        }

        public var dnsHTTPSURL: URL? {
            get {
                nil // Not supported in this WireGuard version
            }
            set {
                // Not supported in this WireGuard version
            }
        }

        public var dnsTLSServerName: String? {
            get {
                nil // Not supported in this WireGuard version
            }
            set {
                // Not supported in this WireGuard version
            }
        }

        public var mtu: UInt16? {
            get {
                interface.mtu
            }
            set {
                interface.mtu = newValue
            }
        }

        // MARK: Modification

        public mutating func addPeer(_ base64PublicKey: String, endpoint: String, allowedIPs: [String] = []) throws {
            guard let publicKey = PublicKey(base64Key: base64PublicKey) else {
                log.error("Invalid peer public key: \(base64PublicKey)")
                throw WireGuard.ConfigurationError.peerHasInvalidPublicKey(base64PublicKey)
            }
            var peer = PeerConfiguration(publicKey: publicKey)
            
            if let endpointObj = Endpoint(from: endpoint) {
                peer.endpoint = endpointObj
            } else {
                log.warning("Invalid endpoint format: \(endpoint), peer will be added without endpoint")
            }
            
            let validAllowedIPs = allowedIPs.compactMap(IPAddressRange.init)
            if validAllowedIPs.count != allowedIPs.count {
                log.warning("Some allowed IPs were invalid and will be ignored")
            }
            peer.allowedIPs = validAllowedIPs
            peers.append(peer)
        }

        public mutating func setPreSharedKey(_ base64Key: String, ofPeer peerIndex: Int) throws {
            guard peerIndex < peers.count else {
                log.error("Invalid peer index: \(peerIndex)")
                return
            }
            guard let preSharedKey = PreSharedKey(base64Key: base64Key) else {
                log.error("Invalid pre-shared key format: \(base64Key)")
                throw WireGuard.ConfigurationError.peerHasInvalidPreSharedKey(base64Key)
            }
            peers[peerIndex].preSharedKey = preSharedKey
        }

        public mutating func addDefaultGatewayIPv4(toPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.append(Self.defaultGateway4)
        }

        public mutating func addDefaultGatewayIPv6(toPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.append(Self.defaultGateway6)
        }

        public mutating func removeDefaultGatewayIPv4(fromPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.removeAll {
                $0 == Self.defaultGateway4
            }
        }

        public mutating func removeDefaultGatewayIPv6(fromPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.removeAll {
                $0 == Self.defaultGateway6
            }
        }

        public mutating func removeDefaultGateways(fromPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.removeAll {
                $0 == Self.defaultGateway4 || $0 == Self.defaultGateway6
            }
        }

        public mutating func removeAllDefaultGateways() {
            peers.indices.forEach {
                removeDefaultGateways(fromPeer: $0)
            }
        }

        public mutating func addAllowedIP(_ allowedIP: String, toPeer peerIndex: Int) {
            guard peerIndex < peers.count else {
                log.error("Invalid peer index: \(peerIndex)")
                return
            }
            guard let addr = IPAddressRange(from: allowedIP) else {
                log.error("Invalid allowed IP format: \(allowedIP)")
                return
            }
            peers[peerIndex].allowedIPs.append(addr)
        }

        public mutating func removeAllowedIP(_ allowedIP: String, fromPeer peerIndex: Int) {
            guard let addr = IPAddressRange(from: allowedIP) else {
                return
            }
            peers[peerIndex].allowedIPs.removeAll {
                $0 == addr
            }
        }

        public mutating func setKeepAlive(_ keepAlive: UInt16, forPeer peerIndex: Int) {
            guard peerIndex < peers.count else {
                log.error("Invalid peer index: \(peerIndex)")
                return
            }
            peers[peerIndex].persistentKeepAlive = keepAlive
        }

        public func build() -> Configuration {
            // Add validation warnings
            if peers.isEmpty {
                log.warning("Building configuration without any peers")
            }
            if interface.addresses.isEmpty {
                log.warning("Building configuration without any interface addresses")
            }
            
            let tunnelConfiguration = TunnelConfiguration(name: nil, interface: interface, peers: peers)
            return Configuration(tunnelConfiguration: tunnelConfiguration)
        }
    }

    public struct Configuration: Codable, Equatable, WireGuardConfigurationProviding {
        public let tunnelConfiguration: TunnelConfiguration
        public var splitTunneling: SplitTunneling?

        public var interface: InterfaceConfiguration {
            tunnelConfiguration.interface
        }

        public var peers: [PeerConfiguration] {
            tunnelConfiguration.peers
        }

        public init(tunnelConfiguration: TunnelConfiguration) {
            self.tunnelConfiguration = tunnelConfiguration
        }

        public func builder() -> WireGuard.ConfigurationBuilder {
            WireGuard.ConfigurationBuilder(tunnelConfiguration)
        }

        // MARK: WireGuardConfigurationProviding

        public var privateKey: String {
            interface.privateKey.base64Key
        }

        public var publicKey: String {
            interface.privateKey.publicKey.base64Key
        }

        public var addresses: [String] {
            interface.addresses.map(\.stringRepresentation)
        }

        public var dnsServers: [String] {
            interface.dns.map(\.stringRepresentation)
        }

        public var dnsSearchDomains: [String] {
            interface.dnsSearch
        }

        public var dnsHTTPSURL: URL? {
            nil // Not supported in this WireGuard version
        }

        public var dnsTLSServerName: String? {
            nil // Not supported in this WireGuard version
        }

        public var mtu: UInt16? {
            interface.mtu
        }

        // MARK: Codable

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let wg = try container.decode(String.self)
            do {
                let cfg = try TunnelConfiguration(fromWgQuickConfig: wg, called: nil)
                self.init(tunnelConfiguration: cfg)
            } catch {
                log.error("Failed to decode WireGuard configuration: \(error)")
                throw error
            }
        }

        public func encode(to encoder: Encoder) throws {
            do {
                let wg = tunnelConfiguration.asWgQuickConfig()
                var container = encoder.singleValueContainer()
                try container.encode(wg)
            } catch {
                log.error("Failed to encode WireGuard configuration: \(error)")
                throw error
            }
        }
    }
}

extension WireGuardConfigurationProviding {
    public var publicKey: String {
        interface.privateKey.publicKey.base64Key
    }

    public var peersCount: Int {
        peers.count
    }

    public func publicKey(ofPeer peerIndex: Int) -> String {
        peers[peerIndex].publicKey.base64Key
    }

    public func preSharedKey(ofPeer peerIndex: Int) -> String? {
        peers[peerIndex].preSharedKey?.base64Key
    }

    public func endpoint(ofPeer peerIndex: Int) -> String? {
        peers[peerIndex].endpoint?.stringRepresentation
    }

    public func allowedIPs(ofPeer peerIndex: Int) -> [String] {
        peers[peerIndex].allowedIPs.map(\.stringRepresentation)
    }

    public func keepAlive(ofPeer peerIndex: Int) -> UInt16? {
        peers[peerIndex].persistentKeepAlive
    }
}
