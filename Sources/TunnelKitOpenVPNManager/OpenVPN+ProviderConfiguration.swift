import Foundation
import TunnelKitManager
import TunnelKitOpenVPNCore
import NetworkExtension
import TunnelKitLogging
import TunnelKitCore

import __TunnelKitUtils

private let log = TKLogger.shared

extension OpenVPN {

    /// Specific configuration for OpenVPN.
    public struct ProviderConfiguration: Codable {
        fileprivate enum Keys: String {
            case logPath = "OpenVPN.LogPath"

            case dataCount = "OpenVPN.DataCount"

            case serverConfiguration = "OpenVPN.ServerConfiguration"

            case lastError = "OpenVPN.LastError"
        }

        /// Optional version identifier about the client pushed to server in peer-info as `IV_UI_VER`.
        public var versionIdentifier: String?

        /// The configuration title.
        public let title: String

        /// The access group for shared data.
        public let appGroup: String

        /// The client configuration.
        public let configuration: OpenVPN.Configuration

        /// The optional username.
        public var username: String?

        /// Enables debugging.
        public var shouldDebug = false

        /// Debug log path.
        public var debugLogPath: String?

        /// Optional debug log format (SwiftyBeaver format).
        public var debugLogFormat: String?

        /// Mask private data in debug log (default is `true`).
        public var masksPrivateData = true

        public init(_ title: String, appGroup: String, configuration: OpenVPN.Configuration) {
            self.title = title
            self.appGroup = appGroup
            self.configuration = configuration
            
            log.info("Created OpenVPN provider configuration with title: \(title)")
            log.debug("Using app group: \(appGroup)")
            log.debug("OpenVPN configuration has \(configuration.remotes?.count ?? 0) remotes")
        }

        public func print() {
            if let versionIdentifier = versionIdentifier {
                log.info("Tunnel version: \(versionIdentifier)")
            }
            log.info("Debug: \(shouldDebug)")
            log.info("Masks private data: \(masksPrivateData)")
            log.info("Local options:")
            configuration.print(isLocal: true)
        }
    }
}

// MARK: NetworkExtensionConfiguration

extension OpenVPN.ProviderConfiguration: NetworkExtensionConfiguration {

    public func asTunnelProtocol(
        withBundleIdentifier tunnelBundleIdentifier: String,
        extra: NetworkExtensionExtra?
    ) throws -> NETunnelProviderProtocol {
        guard let firstRemote = configuration.remotes?.first else {
            log.error("No remotes set in configuration")
            preconditionFailure("No remotes set")
        }

        log.debug("Creating NETunnelProviderProtocol with bundle ID: \(tunnelBundleIdentifier)")
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = tunnelBundleIdentifier
        protocolConfiguration.serverAddress = "\(firstRemote.address):\(firstRemote.proto.port)"
        log.debug("Server address set to: \(firstRemote.address.maskedDescription):\(firstRemote.proto.port)")
        
        if let username = username {
            log.debug("Setting username: \(username.maskedDescription)")
            protocolConfiguration.username = username
            
            if let passwordReference = extra?.passwordReference {
                log.debug("Password reference available")
                protocolConfiguration.passwordReference = passwordReference
            } else {
                log.warning("No password reference provided for username")
            }
        } else {
            log.debug("No username set")
        }
        
        let disconnectOnSleep = extra?.disconnectsOnSleep ?? false
        log.debug("Setting disconnectOnSleep: \(disconnectOnSleep)")
        protocolConfiguration.disconnectOnSleep = disconnectOnSleep
        
        log.debug("Converting provider configuration to dictionary")
        protocolConfiguration.providerConfiguration = try asDictionary()
        
        #if !os(tvOS)
        let killSwitch = extra?.killSwitch ?? false
        log.debug("Setting includeAllNetworks (kill switch): \(killSwitch)")
        protocolConfiguration.includeAllNetworks = killSwitch
        #endif
        
        log.info("NETunnelProviderProtocol created successfully")
        return protocolConfiguration
    }
}

// MARK: Shared data

extension OpenVPN.ProviderConfiguration {

    /**
     The most recent (received, sent) count in bytes.
     */
    public var dataCount: DataCount? {
        let count = defaults?.openVPNDataCount
            //log.verbose("Retrieved data count: \(count?r ?? "nil")")
        return count
    }

    /**
     The server configuration pulled by the VPN.
     */
    public var serverConfiguration: OpenVPN.Configuration? {
        log.verbose("Retrieving server configuration from defaults")
        return defaults?.openVPNServerConfiguration
    }

    /**
     The last error reported by the tunnel, if any.
     */
    public var lastError: TunnelKitOpenVPNError? {
        let error = defaults?.openVPNLastError
        if let error = error {
            log.debug("Retrieved last error: \(error.rawValue)")
        }
        return error
    }

    /**
     The URL of the latest debug log.
     */
    public var urlForDebugLog: URL? {
        let url = defaults?.openVPNURLForDebugLog(appGroup: appGroup)
        log.verbose("Debug log URL: \(url?.path ?? "nil")")
        return url
    }

    private var defaults: UserDefaults? {
        log.verbose("Accessing UserDefaults for app group: \(appGroup)")
        return UserDefaults(suiteName: appGroup)
    }
}

extension OpenVPN.ProviderConfiguration {
    public func _appexSetDataCount(_ newValue: DataCount?) {
      //  log.verbose("Setting data count: \(newValue?.description ?? "nil")")
        defaults?.openVPNDataCount = newValue
    }

    public func _appexSetServerConfiguration(_ newValue: OpenVPN.Configuration?) {
        if newValue != nil {
            log.debug("Setting server configuration")
        } else {
            log.debug("Clearing server configuration")
        }
        defaults?.openVPNServerConfiguration = newValue
    }

    public func _appexSetLastError(_ newValue: TunnelKitOpenVPNError?) {
        if let error = newValue {
            log.debug("Setting last error: \(error.rawValue)")
        } else {
            log.debug("Clearing last error")
        }
        defaults?.openVPNLastError = newValue
    }

    public var _appexDebugLogURL: URL? {
        guard let path = debugLogPath else {
            log.warning("No debug log path set")
            return nil
        }
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(path)
        log.debug("Debug log URL: \(url?.path ?? "nil")")
        return url
    }

    public func _appexSetDebugLogPath() {
        if let path = debugLogPath {
            log.debug("Setting debug log path: \(path)")
            defaults?.setValue(debugLogPath, forKey: OpenVPN.ProviderConfiguration.Keys.logPath.rawValue)
        } else {
            log.warning("No debug log path to set")
        }
    }
}

extension UserDefaults {
    public func openVPNURLForDebugLog(appGroup: String) -> URL? {
        guard let path = string(forKey: OpenVPN.ProviderConfiguration.Keys.logPath.rawValue) else {
            log.warning("No log path found in UserDefaults")
            return nil
        }
        
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(path)
            
        if url == nil {
            log.warning("Failed to create URL for log path: \(path)")
        }
        
        return url
    }

    public fileprivate(set) var openVPNDataCount: DataCount? {
        get {
            guard let rawValue = openVPNDataCountArray else {
                log.verbose("No data count in UserDefaults")
                return nil
            }
            guard rawValue.count == 2 else {
                log.warning("Invalid data count array in UserDefaults (expected 2 elements, got \(rawValue.count))")
                return nil
            }
            return DataCount(rawValue[0], rawValue[1])
        }
        set {
            guard let newValue = newValue else {
                log.verbose("Removing data count from UserDefaults")
                openVPNRemoveDataCountArray()
                return
            }
            log.verbose("Setting data count in UserDefaults: received=\(newValue.received), sent=\(newValue.sent)")
            openVPNDataCountArray = [newValue.received, newValue.sent]
        }
    }

    @objc private var openVPNDataCountArray: [UInt]? {
        get {
            return array(forKey: OpenVPN.ProviderConfiguration.Keys.dataCount.rawValue) as? [UInt]
        }
        set {
            set(newValue, forKey: OpenVPN.ProviderConfiguration.Keys.dataCount.rawValue)
        }
    }

    private func openVPNRemoveDataCountArray() {
        removeObject(forKey: OpenVPN.ProviderConfiguration.Keys.dataCount.rawValue)
    }

    public fileprivate(set) var openVPNServerConfiguration: OpenVPN.Configuration? {
        get {
            guard let raw = data(forKey: OpenVPN.ProviderConfiguration.Keys.serverConfiguration.rawValue) else {
                log.verbose("No server configuration in UserDefaults")
                return nil
            }
            let decoder = JSONDecoder()
            do {
                let cfg = try decoder.decode(OpenVPN.Configuration.self, from: raw)
                log.debug("Successfully decoded server configuration from UserDefaults")
                return cfg
            } catch {
                log.error("Unable to decode server configuration: \(error)")
                return nil
            }
        }
        set {
            guard let newValue = newValue else {
                log.verbose("Removing server configuration from UserDefaults")
                removeObject(forKey: OpenVPN.ProviderConfiguration.Keys.serverConfiguration.rawValue)
                return
            }
            
            let encoder = JSONEncoder()
            do {
                let raw = try encoder.encode(newValue)
                log.debug("Successfully encoded server configuration to UserDefaults")
                set(raw, forKey: OpenVPN.ProviderConfiguration.Keys.serverConfiguration.rawValue)
            } catch {
                log.error("Unable to encode server configuration: \(error)")
            }
        }
    }

    public fileprivate(set) var openVPNLastError: TunnelKitOpenVPNError? {
        get {
            guard let rawValue = string(forKey: OpenVPN.ProviderConfiguration.Keys.lastError.rawValue) else {
                log.verbose("No last error in UserDefaults")
                return nil
            }
            return TunnelKitOpenVPNError(rawValue: rawValue)
        }
        set {
            guard let newValue = newValue else {
                log.verbose("Removing last error from UserDefaults")
                removeObject(forKey: OpenVPN.ProviderConfiguration.Keys.lastError.rawValue)
                return
            }
            log.debug("Setting last error in UserDefaults: \(newValue.rawValue)")
            set(newValue.rawValue, forKey: OpenVPN.ProviderConfiguration.Keys.lastError.rawValue)
        }
    }
}
