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

    private let tunnelQueue = DispatchQueue(label: WireGuardTunnelProvider.description(), qos: .utility)

    private lazy var adapter: WireGuardAdapter = {
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

        // BEGIN: TunnelKit

        guard let tunnelProviderProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            fatalError("Not a NETunnelProviderProtocol")
        }
        guard let providerConfiguration = tunnelProviderProtocol.providerConfiguration else {
            fatalError("Missing providerConfiguration")
        }

        let tunnelConfiguration: TunnelConfiguration
        do {
            cfg = try fromDictionary(WireGuard.ProviderConfiguration.self, providerConfiguration)
            tunnelConfiguration = cfg.configuration.tunnelConfiguration
        } catch {
            completionHandler(TunnelKitWireGuardError.savedProtocolConfigurationIsInvalid)
            return
        }

        configureLogging()

        // END: TunnelKit

        // Handle DNS for split tunneling
        if let splitTunneling = cfg.splitTunneling, splitTunneling.policy == .include {
            // Only use DNS if VPN is handling all traffic or DNS server is in allowed IPs
            let dnsServers = tunnelConfiguration.interface.dns
            let shouldUseDNS = dnsServers.contains { server in
                // Extract the IP string from DNSServer
                let serverIP = server.stringRepresentation
                return splitTunneling.routes.contains { cidr in
                    isIPAddress(serverIP, includedIn: cidr)
                }
            }
            
            if !shouldUseDNS {
                tunnelConfiguration.interface.dns = []
            }
        }

        // Start the tunnel
        adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] adapterError in
            guard let self else {
                completionHandler(nil)
                return
            }

            guard let adapterError = adapterError else {
                let interfaceName = self.adapter.interfaceName ?? "unknown"

                log.info("Tunnel interface is \(interfaceName)")
                self.tunnelQueue.async {
                    self.tunnelIsStarted = true
                    self.refreshDataCount()
                }
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
                log.error("DNS resolution failed for the following hostnames: \(hostnamesWithDnsResolutionFailure)")
                self.cfg._appexSetLastError(.dnsResolutionFailure)
                completionHandler(TunnelKitWireGuardError.dnsResolutionFailure)

            case .setNetworkSettings(let error):
                log.error("Starting tunnel failed with setTunnelNetworkSettings returning \(error.localizedDescription)")
                self.cfg._appexSetLastError(.couldNotSetNetworkSettings)
                completionHandler(TunnelKitWireGuardError.couldNotSetNetworkSettings)

            case .startWireGuardBackend(let errorCode):
                log.error("Starting tunnel failed with wgTurnOn returning \(errorCode)")
                self.cfg._appexSetLastError(.couldNotStartBackend)
                completionHandler(TunnelKitWireGuardError.couldNotStartBackend)

            case .invalidState:
                // Must never happen
                fatalError()
            }
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("Stopping tunnel")

        adapter.stop { [weak self] error in

            // BEGIN: TunnelKit

            guard let self else {
                completionHandler()
                return
            }
            self.tunnelQueue.async {
                self.cfg._appexSetLastError(nil)
                self.tunnelIsStarted = false
                if let error = error {
                    log.error("Failed to stop WireGuard adapter: \(error.localizedDescription)")
                }
                completionHandler()
            }

            // END: TunnelKit

            #if os(macOS)
            exit(0)
            #endif
        }
    }

    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let completionHandler = completionHandler else {
            return
        }

        if messageData.count == 1 && messageData[0] == 0 {
            adapter.getRuntimeConfiguration { settings in
                var data: Data?
                if let settings = settings {
                    data = settings.data(using: .utf8)!
                }
                completionHandler(data)
            }
        } else {
            completionHandler(nil)
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
            return
        }

        tunnelQueue.schedule(after: DispatchTimeInterval.milliseconds(dataCountInterval)) { [weak self] in
            self?.refreshDataCount()
        }

        guard tunnelIsStarted else {
            cfg._appexSetDataCount(nil)
            return
        }
        fetchDataCount { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success(let dataCount):
                self.cfg._appexSetDataCount(dataCount)
            case .failure(let error):
                log.error("Failed to refresh data count \(error.localizedDescription)")
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

        if cfg.shouldDebug {
            let console = ConsoleDestination()
            console.useNSLog = true
            console.minLevel = logLevel
            console.format = logFormat
            log.addDestination(console)
        }

        let file = FileDestination(logFileURL: cfg._appexDebugLogURL)
        file.minLevel = logLevel
        file.format = logFormat
        file.logFileMaxSize = 20000
        log.addDestination(file)

        // store path for clients
        cfg._appexSetDebugLogPath()
    }

    func fetchDataCount(completiondHandler: @escaping (Result<DataCount, Error>) -> Void) {
        adapter.getRuntimeConfiguration { configurationString in
            if let configurationString = configurationString,
               let wireGuardDataCount = DataCount.from(wireGuardString: configurationString) {
                completiondHandler(.success(wireGuardDataCount))
            } else {
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
        return false
    }
    
    // Parse CIDR notation (e.g., "192.168.1.0/24")
    let cidrComponents = cidr.split(separator: "/")
    guard cidrComponents.count == 2 else {
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
        return false
    }
    
    // Convert IP addresses to UInt32 for easier comparison
    let ipValue = (UInt32(ipByte1) << 24) | (UInt32(ipByte2) << 16) | (UInt32(ipByte3) << 8) | UInt32(ipByte4)
    let networkValue = (UInt32(netByte1) << 24) | (UInt32(netByte2) << 16) | (UInt32(netByte3) << 8) | UInt32(netByte4)
    
    // Create a mask based on the prefix length
    let mask: UInt32 = prefixLength == 0 ? 0 : ~((1 << (32 - prefixLength)) - 1)
    
    // Check if the IP address is in the network range
    return (ipValue & mask) == (networkValue & mask)
}
