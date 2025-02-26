import TunnelKitCore
import TunnelKitWireGuardCore
import TunnelKitWireGuardManager
import WireGuardKit
import __TunnelKitUtils
import SwiftyBeaver

import Foundation
import NetworkExtension
import os
import TunnelKitLogging

private let log = TKLogger.shared

open class WireGuardTunnelProvider: NEPacketTunnelProvider {
    private var cfg: WireGuard.ProviderConfiguration!

    /// The number of milliseconds between data count updates. Set to 0 to disable updates (default).
    public var dataCountInterval = 0

    /// Once the tunnel starts, enable this property to update connection stats
    private var tunnelIsStarted = false
    
    /// Track connection start time for performance metrics
    private var connectionStartTime: Date?
    
    /// Track reconnection attempts
    private var reconnectionAttempts = 0

    private let tunnelQueue = DispatchQueue(label: WireGuardTunnelProvider.description(), qos: .utility)

    private lazy var adapter: WireGuardAdapter = {
        log.debug("Creating WireGuardAdapter")
        return WireGuardAdapter(with: self) { logLevel, message in
            switch logLevel {
            case .verbose:
                log.debug(message)
            case .error:
                log.error(message)
            }
        }
    }()

    open override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("Starting WireGuard tunnel...")
        connectionStartTime = Date()
        reconnectionAttempts = 0
        
        if let options = options, !options.isEmpty {
            log.debug("Start options: \(options)")
        } else {
            log.debug("No start options provided")
        }

        // BEGIN: TunnelKit

        guard let tunnelProviderProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            log.error("Protocol configuration is not NETunnelProviderProtocol")
            fatalError("Not a NETunnelProviderProtocol")
        }
        guard let providerConfiguration = tunnelProviderProtocol.providerConfiguration else {
            log.error("Missing provider configuration")
            fatalError("Missing providerConfiguration")
        }
        log.debug("Provider configuration keys: \(providerConfiguration.keys)")

        let tunnelConfiguration: TunnelConfiguration
        do {
            log.debug("Parsing provider configuration")
            cfg = try fromDictionary(WireGuard.ProviderConfiguration.self, providerConfiguration)
            tunnelConfiguration = cfg.configuration.tunnelConfiguration
            log.info("Successfully parsed provider configuration")
            log.debug("Tunnel configuration: interface=\(tunnelConfiguration.interface.name ?? "unnamed"), peers=\(tunnelConfiguration.peers.count)")
        } catch {
            log.error("Failed to parse protocol configuration: \(error)")
            completionHandler(TunnelKitWireGuardError.savedProtocolConfigurationIsInvalid)
            return
        }

        configureLogging()

        // END: TunnelKit

        // Handle DNS for split tunneling
        if let splitTunneling = cfg.splitTunneling, splitTunneling.policy == .include {
            log.info("Split tunneling enabled with 'include' policy (\(splitTunneling.routes.count) routes)")
            // Only use DNS if VPN is handling all traffic or DNS server is in allowed IPs
            let dnsServers = tunnelConfiguration.interface.dns
            let shouldUseDNS = dnsServers.contains { server in
                // Extract the IP string from DNSServer
                let serverIP = server.stringRepresentation
                let isIncluded = splitTunneling.routes.contains { cidr in
                    isIPAddress(serverIP, includedIn: cidr)
                }
                log.debug("DNS server \(serverIP) is \(isIncluded ? "included" : "not included") in split tunneling routes")
                return isIncluded
            }
            
            if !shouldUseDNS {
                log.warning("DNS servers not in split tunneling include list, clearing DNS settings")
                tunnelConfiguration.interface.dns = []
            } else {
                log.info("Using DNS servers: \(dnsServers.map { $0.stringRepresentation })")
            }
        } else if let splitTunneling = cfg.splitTunneling, splitTunneling.policy == .exclude {
            log.info("Split tunneling enabled with 'exclude' policy (\(splitTunneling.routes.count) routes)")
            log.debug("Excluded routes: \(splitTunneling.routes)")
        } else {
            log.info("Split tunneling not enabled")
        }

        // Start the tunnel
        log.info("Starting WireGuard adapter...")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] adapterError in
            guard let self else {
                log.warning("Self reference lost during adapter start")
                completionHandler(nil)
                return
            }

            guard let adapterError = adapterError else {
                let interfaceName = self.adapter.interfaceName ?? "unknown"
                let startDuration = Date().timeIntervalSince(self.connectionStartTime ?? Date())

                log.info("Tunnel interface is \(interfaceName), startup completed in \(String(format: "%.2f", startDuration))s")
                self.tunnelQueue.async {
                    log.debug("Marking tunnel as started and refreshing data count")
                    self.tunnelIsStarted = true
                    self.refreshDataCount()
                }
                self.cfg._appexSetLastError(nil)
                completionHandler(nil)
                return
            }

            switch adapterError {
            case .cannotLocateTunnelFileDescriptor:
                log.error("Starting tunnel failed: could not determine file descriptor")
                self.cfg._appexSetLastError(.couldNotDetermineFileDescriptor)
                completionHandler(TunnelKitWireGuardError.couldNotDetermineFileDescriptor)

            case .dnsResolution(let dnsErrors):
                let hostnamesWithDnsResolutionFailure = dnsErrors.map(\.address)
                    .joined(separator: ", ")
                log.error("DNS resolution failed for hostnames: \(hostnamesWithDnsResolutionFailure)")
                log.debug("DNS errors details: \(dnsErrors)")
                self.cfg._appexSetLastError(.dnsResolutionFailure)
                completionHandler(TunnelKitWireGuardError.dnsResolutionFailure)

            case .setNetworkSettings(let error):
                log.error("Starting tunnel failed: setTunnelNetworkSettings returned \(error.localizedDescription)")
                log.debug("Network settings error details: \(error)")
                self.cfg._appexSetLastError(.couldNotSetNetworkSettings)
                completionHandler(TunnelKitWireGuardError.couldNotSetNetworkSettings)

            case .startWireGuardBackend(let errorCode):
                log.error("Starting tunnel failed: wgTurnOn returned error code \(errorCode)")
                self.cfg._appexSetLastError(.couldNotStartBackend)
                completionHandler(TunnelKitWireGuardError.couldNotStartBackend)

            case .invalidState:
                // Must never happen
                log.error("Starting tunnel failed: WireGuard adapter in invalid state")
                fatalError("WireGuard adapter in invalid state")
            }
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("Stopping tunnel with reason: \(self.describeStopReason(reason))")

        adapter.stop { [weak self] error in

            // BEGIN: TunnelKit

            guard let self else {
                log.warning("Self reference lost during adapter stop")
                completionHandler()
                return
            }
            self.tunnelQueue.async {
                log.debug("Clearing last error and marking tunnel as stopped")
                self.cfg._appexSetLastError(nil)
                self.tunnelIsStarted = false
                if let error = error {
                    log.error("Failed to stop WireGuard adapter: \(error.localizedDescription)")
                } else {
                    log.info("WireGuard adapter stopped successfully")
                }
                completionHandler()
            }

            // END: TunnelKit

            #if os(macOS)
            log.info("Exiting on macOS")
            exit(0)
            #endif
        }
    }

    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        log.debug("Handling app message of \(messageData.count) bytes")
        guard let completionHandler = completionHandler else {
            log.warning("No completion handler for app message")
            return
        }

        if messageData.count == 1 && messageData[0] == 0 {
            log.debug("Getting runtime configuration")
            adapter.getRuntimeConfiguration { settings in
                var data: Data?
                if let settings = settings {
                    data = settings.data(using: .utf8)!
                    log.debug("Returning runtime configuration (\(data?.count ?? 0) bytes)")
                } else {
                    log.warning("No runtime configuration available")
                }
                completionHandler(data)
            }
        } else {
            log.warning("Unknown app message format")
            completionHandler(nil)
        }
    }
    
    // Helper method to describe stop reasons
    private func describeStopReason(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none:
            return "None"
        case .userInitiated:
            return "User initiated"
        case .providerFailed:
            return "Provider failed"
        case .noNetworkAvailable:
            return "No network available"
        case .unrecoverableNetworkChange:
            return "Unrecoverable network change"
        case .providerDisabled:
            return "Provider disabled"
        case .authenticationCanceled:
            return "Authentication canceled"
        case .configurationFailed:
            return "Configuration failed"
        case .idleTimeout:
            return "Idle timeout"
        case .configurationDisabled:
            return "Configuration disabled"
        case .configurationRemoved:
            return "Configuration removed"
        case .superceded:
            return "Superceded by new configuration"
        case .userLogout:
            return "User logout"
        case .userSwitch:
            return "User switch"
        case .connectionFailed:
            return "Connection failed"
        default:
            return "Unknown reason (\(reason.rawValue))"
        }
    }

    // MARK: Data counter (tunnel queue)

    // XXX: thread-safety here is poor, but we know that:
    //
    // - dataCountInterval is virtually constant, set on tunnel creation
    // - cfg only modifies UserDefaults, which is thread-safe
    // - adapter, used in fetchDataCount, is thread-safe
    //
    private func refreshDataCount() {
        guard dataCountInterval > 0 else {
            log.debug("Data count updates disabled (interval is 0)")
            return
        }

        tunnelQueue.schedule(after: DispatchTimeInterval.milliseconds(dataCountInterval)) { [weak self] in
            self?.refreshDataCount()
        }

        guard tunnelIsStarted else {
            log.debug("Tunnel not started, clearing data count")
            cfg._appexSetDataCount(nil)
            return
        }
        fetchDataCount { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success(let dataCount):
                //log.verbose("Updated data count: \(dataCount)")
                self.cfg._appexSetDataCount(dataCount)
            case .failure(let error):
                log.error("Failed to refresh data count: \(error.localizedDescription)")
            }
        }
    }
}

private extension WireGuardTunnelProvider {
    enum StatsError: Error {
         case parseFailure
    }

    func configureLogging() {
        let logLevel: SwiftyBeaver.Level = (cfg.shouldDebug ? .debug : .info)
        let logFormat = cfg.debugLogFormat ?? "$Dyyyy-MM-dd HH:mm:ss.SSS$d $L $N.$F:$l - $M"
        
        log.info("Configuring WireGuard logging with level: \(logLevel)")

        if cfg.shouldDebug {
            log.debug("Adding console logging destination")
            let console = ConsoleDestination()
            console.useNSLog = true
            console.minLevel = logLevel
            console.format = logFormat
            log.addDestination(console)
        }

        if let logURL = cfg._appexDebugLogURL {
            log.info("Adding file logging destination: \(logURL.path)")
            let file = FileDestination(logFileURL: logURL)
            file.minLevel = logLevel
            file.format = logFormat
            file.logFileMaxSize = 20000
            log.addDestination(file)
        } else {
            log.warning("No debug log URL available")
        }

        // store path for clients
        cfg._appexSetDebugLogPath()
        log.info("Logging configuration complete")
    }

    func fetchDataCount(completiondHandler: @escaping (Result<DataCount, Error>) -> Void) {
        adapter.getRuntimeConfiguration { configurationString in
            if let configurationString = configurationString,
               let wireGuardDataCount = DataCount.from(wireGuardString: configurationString) {
                completiondHandler(.success(wireGuardDataCount))
            } else {
                log.warning("Failed to parse data count from configuration string")
                completiondHandler(.failure(StatsError.parseFailure))
            }
         }
    }
}

private extension String {
    func isIncludedInAny(of cidrs: [String]) -> Bool {
        return cidrs.contains { cidr in
            isIPAddress(self, includedIn: cidr)
        }
    }
} 

// Helper function to check if an IP is within a CIDR range
private func isIPAddress(_ ip: String, includedIn cidr: String) -> Bool {
    // Parse IP address
    let ipComponents = ip.split(separator: ".")
    guard ipComponents.count == 4,
          let ipByte1 = UInt8(ipComponents[0]),
          let ipByte2 = UInt8(ipComponents[1]), 
          let ipByte3 = UInt8(ipComponents[2]),
          let ipByte4 = UInt8(ipComponents[3]) else {
        log.warning("Failed to parse IP address: \(ip)")
        return false
    }
    
    // Parse CIDR notation (e.g., "192.168.1.0/24")
    let cidrComponents = cidr.split(separator: "/")
    guard cidrComponents.count == 2 else {
        log.warning("Invalid CIDR format: \(cidr)")
        return false
    }
    
    let networkComponents = cidrComponents[0].split(separator: ".")
    guard networkComponents.count == 4,
          let netByte1 = UInt8(networkComponents[0]),
          let netByte2 = UInt8(networkComponents[1]),
          let netByte3 = UInt8(networkComponents[2]),
          let netByte4 = UInt8(networkComponents[3]),
          let prefixLength = UInt8(cidrComponents[1]),
          prefixLength <= 32 else {
        log.warning("Failed to parse network address or prefix length from CIDR: \(cidr)")
        return false
    }
    
    // Convert IP addresses to UInt32 for easier comparison
    let ipValue = (UInt32(ipByte1) << 24) | (UInt32(ipByte2) << 16) | (UInt32(ipByte3) << 8) | UInt32(ipByte4)
    let networkValue = (UInt32(netByte1) << 24) | (UInt32(netByte2) << 16) | (UInt32(netByte3) << 8) | UInt32(netByte4)
    
    // Create a mask based on the prefix length
    let mask: UInt32 = prefixLength == 0 ? 0 : ~((1 << (32 - prefixLength)) - 1)
    
    // Check if the IP address is in the network range
    let result = (ipValue & mask) == (networkValue & mask)
    log.verbose("CIDR check: IP \(ip) is \(result ? "in" : "not in") network \(cidr)")
    return result
}
