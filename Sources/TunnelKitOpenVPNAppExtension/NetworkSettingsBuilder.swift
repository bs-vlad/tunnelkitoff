import Foundation
import NetworkExtension
import TunnelKitCore
import TunnelKitOpenVPNCore
import SwiftyBeaver
import TunnelKitLogging

private let log = TKLogger.shared

struct NetworkSettingsBuilder {
    let remoteAddress: String

    let localOptions: OpenVPN.Configuration

    let remoteOptions: OpenVPN.Configuration

    init(remoteAddress: String, localOptions: OpenVPN.Configuration, remoteOptions: OpenVPN.Configuration) {
        self.remoteAddress = remoteAddress
        self.localOptions = localOptions
        self.remoteOptions = remoteOptions
        log.info("NetworkSettingsBuilder initialized with remote address: \(remoteAddress.maskedDescription)")
        log.debug("Local options has \(localOptions.routes4?.count ?? 0) IPv4 routes and \(localOptions.routes6?.count ?? 0) IPv6 routes")
        log.debug("Remote options has \(remoteOptions.routes4?.count ?? 0) IPv4 routes and \(remoteOptions.routes6?.count ?? 0) IPv6 routes")
    }

    func build() -> NEPacketTunnelNetworkSettings {
        log.info("Building network settings for tunnel")
        let ipv4Settings = computedIPv4Settings
        let ipv6Settings = computedIPv6Settings
        let dnsSettings = computedDNSSettings
        let proxySettings = computedProxySettings

        // add direct routes to DNS servers
        if !isGateway {
            log.debug("Adding direct routes to DNS servers (not in gateway mode)")
            for server in dnsSettings?.servers ?? [] {
                if server.contains(":") {
                    log.debug("Adding direct IPv6 route to DNS server: \(server.maskedDescription)")
                    ipv6Settings?.includedRoutes?.insert(NEIPv6Route(destinationAddress: server, networkPrefixLength: 128), at: 0)
                } else {
                    log.debug("Adding direct IPv4 route to DNS server: \(server.maskedDescription)")
                    ipv4Settings?.includedRoutes?.insert(NEIPv4Route(destinationAddress: server, subnetMask: "255.255.255.255"), at: 0)
                }
            }
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteAddress)
        settings.ipv4Settings = ipv4Settings
        settings.ipv6Settings = ipv6Settings
        settings.dnsSettings = dnsSettings
        settings.proxySettings = proxySettings
        if let mtu = localOptions.mtu, mtu > 0 {
            log.debug("Setting MTU to \(mtu)")
            settings.mtu = NSNumber(value: mtu)
        } else {
            log.debug("No MTU set in configuration")
        }
        log.info("Network settings built successfully")
        log.debug("IPv4 settings: \(ipv4Settings != nil ? "configured" : "not configured")")
        log.debug("IPv6 settings: \(ipv6Settings != nil ? "configured" : "not configured")")
        log.debug("DNS settings: \(dnsSettings != nil ? "configured" : "not configured")")
        log.debug("Proxy settings: \(proxySettings != nil ? "configured" : "not configured")")
        return settings
    }
}

extension NetworkSettingsBuilder {
    private var pullRoutes: Bool {
        !(localOptions.noPullMask?.contains(.routes) ?? false)
    }

    private var pullDNS: Bool {
        !(localOptions.noPullMask?.contains(.dns) ?? false)
    }

    private var pullProxy: Bool {
        !(localOptions.noPullMask?.contains(.proxy) ?? false)
    }
}

extension NetworkSettingsBuilder {
    var isGateway: Bool {
        isIPv4Gateway || isIPv6Gateway
    }

    private var routingPolicies: [OpenVPN.RoutingPolicy]? {
        pullRoutes ? (remoteOptions.routingPolicies ?? localOptions.routingPolicies) : localOptions.routingPolicies
    }

    private var isIPv4Gateway: Bool {
        routingPolicies?.contains(.IPv4) ?? false
    }

    private var isIPv6Gateway: Bool {
        routingPolicies?.contains(.IPv6) ?? false
    }

    private var allRoutes4: [IPv4Settings.Route] {
        var routes = localOptions.routes4 ?? []
        if pullRoutes, let remoteRoutes = remoteOptions.routes4 {
            routes.append(contentsOf: remoteRoutes)
        }
        return routes
    }

    private var allRoutes6: [IPv6Settings.Route] {
        var routes = localOptions.routes6 ?? []
        if pullRoutes, let remoteRoutes = remoteOptions.routes6 {
            routes.append(contentsOf: remoteRoutes)
        }
        return routes
    }

    private var allDNSServers: [String] {
        var servers = localOptions.dnsServers ?? []
        if pullDNS, let remoteServers = remoteOptions.dnsServers {
            servers.append(contentsOf: remoteServers)
        }
        return servers
    }

    private var dnsDomain: String? {
        var domain = localOptions.dnsDomain
        if pullDNS, let remoteDomain = remoteOptions.dnsDomain {
            domain = remoteDomain
        }
        return domain
    }

    private var allDNSSearchDomains: [String] {
        var searchDomains = localOptions.searchDomains ?? []
        if pullDNS, let remoteSearchDomains = remoteOptions.searchDomains {
            searchDomains.append(contentsOf: remoteSearchDomains)
        }
        return searchDomains
    }

    private var allProxyBypassDomains: [String] {
        var bypass = localOptions.proxyBypassDomains ?? []
        if pullProxy, let remoteBypass = remoteOptions.proxyBypassDomains {
            bypass.append(contentsOf: remoteBypass)
        }
        return bypass
    }
}

extension NetworkSettingsBuilder {

    // IPv4/6 address/mask MUST come from server options
    // routes, instead, can both come from server and local options

    private var computedIPv4Settings: NEIPv4Settings? {
        guard let ipv4 = remoteOptions.ipv4 else {
            log.warning("No IPv4 settings found in remote options")
            return nil
        }
        log.debug("Creating IPv4 settings with address: \(ipv4.address.maskedDescription) and mask: \(ipv4.addressMask)")
        let ipv4Settings = NEIPv4Settings(addresses: [ipv4.address], subnetMasks: [ipv4.addressMask])
        var neRoutes: [NEIPv4Route] = []
        var neExcludedRoutes: [NEIPv4Route] = []

        switch localOptions.splitTunneling?.policy {
        case .include:
            log.info("Split tunneling mode: Include (only routing specified CIDRs through VPN)")
            // Include mode - only route specified CIDRs through VPN
            // Ignore server-pushed redirect-gateway and use local routes
            for cidr in localOptions.splitTunneling?.routes ?? [] {
                if let route = createIPv4Route(fromCIDR: cidr, defaultGateway: ipv4.defaultGateway) {
                    neRoutes.append(route)
                    log.info("SplitTunnel.Include.IPv4: Adding route \(route.destinationAddress)/\(route.destinationSubnetMask)")
                } else {
                    log.warning("Failed to create IPv4 route from CIDR: \(cidr)")
                }
            }
            
        case .exclude:
            log.info("Split tunneling mode: Exclude (routing all traffic except specified CIDRs through VPN)")
            // Exclude mode - route all traffic through VPN except specified CIDRs
            // Set default gateway and exclude specified routes
            let defaultRoute = NEIPv4Route.default()
            defaultRoute.gatewayAddress = ipv4.defaultGateway
            neRoutes.append(defaultRoute)
            log.info("SplitTunnel.Exclude.IPv4: Setting default gateway to \(ipv4.defaultGateway)")
            
            for cidr in localOptions.splitTunneling?.routes ?? [] {
                if let route = createIPv4Route(fromCIDR: cidr, useNetGateway: true) {
                    neExcludedRoutes.append(route)
                    log.info("SplitTunnel.Exclude.IPv4: Excluding route \(route.destinationAddress)/\(route.destinationSubnetMask)")
                } else {
                    log.warning("Failed to create excluded IPv4 route from CIDR: \(cidr)")
                }
            }
            
        default:
            log.info("Standard routing (no split tunneling)")
            // No split tunneling - use standard routing logic
            if isIPv4Gateway {
                let defaultRoute = NEIPv4Route.default()
                defaultRoute.gatewayAddress = ipv4.defaultGateway
                neRoutes.append(defaultRoute)
                log.info("Routing.IPv4: Setting default gateway to \(ipv4.defaultGateway)")
            } else {
                log.debug("IPv4 gateway not enabled")
            }

            for r in allRoutes4 {
                let ipv4Route = NEIPv4Route(destinationAddress: r.destination, subnetMask: r.mask)
                let gw = r.gateway ?? ipv4.defaultGateway
                ipv4Route.gatewayAddress = gw
                neRoutes.append(ipv4Route)
                log.info("Routing.IPv4: Adding route \(r.destination)/\(r.mask) -> \(gw)")
            }
        }

        log.debug("IPv4 settings include \(neRoutes.count) routes and \(neExcludedRoutes.count) excluded routes")
        ipv4Settings.includedRoutes = neRoutes
        ipv4Settings.excludedRoutes = neExcludedRoutes
        return ipv4Settings
    }

    private var computedIPv6Settings: NEIPv6Settings? {
        guard let ipv6 = remoteOptions.ipv6 else {
            return nil
        }
        let ipv6Settings = NEIPv6Settings(addresses: [ipv6.address], networkPrefixLengths: [ipv6.addressPrefixLength as NSNumber])
        var neRoutes: [NEIPv6Route] = []
        var neExcludedRoutes: [NEIPv6Route] = []

        // We only handle IPv4 for split tunneling, use standard routing for IPv6
        if isIPv6Gateway {
            let defaultRoute = NEIPv6Route.default()
            defaultRoute.gatewayAddress = ipv6.defaultGateway
            neRoutes.append(defaultRoute)
            log.info("Routing.IPv6: Setting default gateway to \(ipv6.defaultGateway)")
        }

        for r in allRoutes6 {
            let ipv6Route = NEIPv6Route(destinationAddress: r.destination, networkPrefixLength: r.prefixLength as NSNumber)
            let gw = r.gateway ?? ipv6.defaultGateway
            ipv6Route.gatewayAddress = gw
            neRoutes.append(ipv6Route)
            log.info("Routing.IPv6: Adding route \(r.destination)/\(r.prefixLength) -> \(gw)")
        }

        ipv6Settings.includedRoutes = neRoutes
        ipv6Settings.excludedRoutes = neExcludedRoutes
        return ipv6Settings
    }

    var hasGateway: Bool {
        var hasGateway = false
        if isIPv4Gateway && remoteOptions.ipv4 != nil {
            hasGateway = true
            log.debug("IPv4 gateway is available")
        }
        if isIPv6Gateway && remoteOptions.ipv6 != nil {
            hasGateway = true
            log.debug("IPv6 gateway is available")
        }
        log.info("hasGateway check result: \(hasGateway)")
        return hasGateway
    }
}

extension NetworkSettingsBuilder {
    private var computedDNSSettings: NEDNSSettings? {
        guard localOptions.isDNSEnabled ?? true else {
            log.info("DNS is disabled in configuration")
            return nil
        }
        var dnsSettings: NEDNSSettings?
        switch localOptions.dnsProtocol {
        case .https:
            let dnsServers = localOptions.dnsServers ?? []
            guard let serverURL = localOptions.dnsHTTPSURL else {
                log.warning("DNS over HTTPS enabled but no server URL provided")
                break
            }
            let specific = NEDNSOverHTTPSSettings(servers: dnsServers)
            specific.serverURL = serverURL
            dnsSettings = specific
            log.info("DNS over HTTPS: Using servers \(dnsServers)")
            log.info("\tHTTPS URL: \(serverURL)")

        case .tls:
            let dnsServers = localOptions.dnsServers ?? []
            guard let serverName = localOptions.dnsTLSServerName else {
                log.warning("DNS over TLS enabled but no server name provided")
                break
            }
            let specific = NEDNSOverTLSSettings(servers: dnsServers)
            specific.serverName = serverName
            dnsSettings = specific
            log.info("DNS over TLS: Using servers \(dnsServers)")
            log.info("\tTLS server name: \(serverName)")

        default:
            log.debug("Using standard DNS settings")
            break
        }

        // fall back
        if dnsSettings == nil {
            let dnsServers = allDNSServers
            if !dnsServers.isEmpty {
                log.info("DNS: Using servers \(dnsServers)")
                dnsSettings = NEDNSSettings(servers: dnsServers)
            } else {
                if isGateway {
                    log.warning("DNS: No settings provided, using system defaults")
                } else {
                    log.warning("DNS: No settings provided, using current network settings")
                }
            }
        }

        // "hack" for split DNS (i.e. use VPN only for DNS)
        if !isGateway {
            log.debug("Configuring split DNS (VPN for DNS only)")
            dnsSettings?.matchDomains = [""]
        }

        if let domain = dnsDomain {
            log.info("DNS: Using domain: \(domain)")
            dnsSettings?.domainName = domain
        }

        let searchDomains = allDNSSearchDomains
        if !searchDomains.isEmpty {
            log.info("DNS: Using search domains: \(searchDomains)")
            dnsSettings?.searchDomains = searchDomains
            if !isGateway {
                log.debug("Setting DNS match domains to search domains for split DNS")
                dnsSettings?.matchDomains = dnsSettings?.searchDomains
            }
        }

        return dnsSettings
    }
}

extension NetworkSettingsBuilder {
    private var computedProxySettings: NEProxySettings? {
        guard localOptions.isProxyEnabled ?? true else {
            return nil
        }
        var proxySettings: NEProxySettings?
        if let httpsProxy = pullProxy ? (remoteOptions.httpsProxy ?? localOptions.httpsProxy) : localOptions.httpsProxy {
            proxySettings = NEProxySettings()
            proxySettings?.httpsServer = httpsProxy.neProxy()
            proxySettings?.httpsEnabled = true
            log.info("Routing: Setting HTTPS proxy \(httpsProxy.address):\(httpsProxy.port)")
        }
        if let httpProxy = pullProxy ? (remoteOptions.httpProxy ?? localOptions.httpProxy) : localOptions.httpProxy {
            if proxySettings == nil {
                proxySettings = NEProxySettings()
            }
            proxySettings?.httpServer = httpProxy.neProxy()
            proxySettings?.httpEnabled = true
            log.info("Routing: Setting HTTP proxy \(httpProxy.address):\(httpProxy.port)")
        }
        if let pacURL = pullProxy ? (remoteOptions.proxyAutoConfigurationURL ?? localOptions.proxyAutoConfigurationURL) : localOptions.proxyAutoConfigurationURL {
            if proxySettings == nil {
                proxySettings = NEProxySettings()
            }
            proxySettings?.proxyAutoConfigurationURL = pacURL
            proxySettings?.autoProxyConfigurationEnabled = true
            log.info("Routing: Setting PAC \(pacURL)")
        }

        // only set if there is a proxy (proxySettings set to non-nil above)
        if proxySettings != nil {
            let bypass = allProxyBypassDomains
            if !bypass.isEmpty {
                proxySettings?.exceptionList = bypass
                log.info("Routing: Setting proxy by-pass list: \(bypass)")
            }
        }
        return proxySettings
    }
}

private extension Proxy {
    func neProxy() -> NEProxyServer {
        return NEProxyServer(address: address, port: Int(port))
    }
}

extension NetworkSettingsBuilder {
    
    // MARK: - Helper methods for split tunneling
    
    /// Creates an IPv4 route from a CIDR notation string.
    /// - Parameters:
    ///   - cidr: The CIDR notation string (e.g., "192.168.1.0/24")
    ///   - defaultGateway: The default gateway to use for the route
    ///   - useNetGateway: If true, uses the network gateway instead of VPN gateway
    /// - Returns: An NEIPv4Route if parsing is successful, otherwise nil
    private func createIPv4Route(fromCIDR cidr: String, defaultGateway: String? = nil, useNetGateway: Bool = false) -> NEIPv4Route? {
        let components = cidr.components(separatedBy: "/")
        guard components.count == 2,
              let prefixLength = Int(components[1]),
              prefixLength >= 0 && prefixLength <= 32 else {
            log.warning("Invalid CIDR format: \(cidr)")
            return nil
        }
        
        let ipAddress = components[0]
        let subnetMask = createSubnetMask(prefixLength: prefixLength)
        
        let route = NEIPv4Route(destinationAddress: ipAddress, subnetMask: subnetMask)
        
        // For excluded routes in split tunneling, we want to use the system's default gateway
        if !useNetGateway, let gateway = defaultGateway {
            route.gatewayAddress = gateway
        }
        
        return route
    }
    
    /// Creates an IPv6 route from a CIDR notation string.
    /// - Parameters:
    ///   - cidr: The CIDR notation string (e.g., "2001:db8::/32")
    ///   - defaultGateway: The default gateway to use for the route
    ///   - useNetGateway: If true, uses the network gateway instead of VPN gateway
    /// - Returns: An NEIPv6Route if parsing is successful, otherwise nil
    private func createIPv6Route(fromCIDR cidr: String, defaultGateway: String? = nil, useNetGateway: Bool = false) -> NEIPv6Route? {
        let components = cidr.components(separatedBy: "/")
        guard components.count == 2,
              let prefixLength = Int(components[1]),
              prefixLength >= 0 && prefixLength <= 128 else {
            log.warning("Invalid IPv6 CIDR format: \(cidr)")
            return nil
        }
        
        let ipAddress = components[0]
        let route = NEIPv6Route(destinationAddress: ipAddress, networkPrefixLength: NSNumber(value: prefixLength))
        
        if !useNetGateway, let gateway = defaultGateway {
            route.gatewayAddress = gateway
        }
        
        return route
    }
    
    /// Creates a subnet mask string from a prefix length.
    /// - Parameter prefixLength: The prefix length (0-32)
    /// - Returns: A dotted-decimal subnet mask string (e.g., "255.255.255.0" for prefix length 24)
    private func createSubnetMask(prefixLength: Int) -> String {
        let fullMask = 0xffffffff
        let shiftedMask = prefixLength > 0 ? fullMask << (32 - prefixLength) : 0
        
        let octet1 = (shiftedMask >> 24) & 0xff
        let octet2 = (shiftedMask >> 16) & 0xff
        let octet3 = (shiftedMask >> 8) & 0xff
        let octet4 = shiftedMask & 0xff
        
        return "\(octet1).\(octet2).\(octet3).\(octet4)"
    }
}
