import Foundation
import NetworkExtension
import TunnelKitCore
import TunnelKitManager
import TunnelKitWireGuardCore
import WireGuardKit
import SwiftyBeaver
import __TunnelKitUtils
import TunnelKitLogging

private let log = TKLogger.shared

extension WireGuard {

    /// Specific configuration for WireGuard.
    public struct ProviderConfiguration: Codable {
        fileprivate enum Keys: String {
            case logPath = "WireGuard.LogPath"

            case lastError = "WireGuard.LastError"

            case dataCount = "WireGuard.DataCount"
        }

        public let title: String

        public let appGroup: String

        public let configuration: WireGuard.Configuration

        public var splitTunneling: SplitTunneling?

        public var shouldDebug = false

        public var debugLogPath: String?

        public var debugLogFormat: String?

        public init(_ title: String, appGroup: String, configuration: WireGuard.Configuration) {
            log.info("Creating WireGuard provider configuration: \(title)")
            self.title = title
            self.appGroup = appGroup
            self.configuration = configuration
            self.splitTunneling = configuration.splitTunneling
            log.debug("Configuration initialized with app group: \(appGroup)")
            log.debug("Split tunneling: \(splitTunneling?.policy == .include ? "include" : splitTunneling?.policy == .exclude ? "exclude" : "disabled")")
        }

        private init(_ title: String, appGroup: String, wgQuickConfig: String) throws {
            log.info("Creating WireGuard provider configuration from wgQuick config: \(title)")
            self.title = title
            self.appGroup = appGroup
            
            do {
                log.debug("Parsing wgQuick configuration")
                configuration = try WireGuard.Configuration(wgQuickConfig: wgQuickConfig)
                log.info("Successfully parsed wgQuick configuration")
            } catch {
                log.error("Failed to parse wgQuick configuration: \(error)")
                throw error
            }
        }
    }
}

// MARK: NetworkExtensionConfiguration

extension WireGuard.ProviderConfiguration: NetworkExtensionConfiguration {

    public func asTunnelProtocol(
        withBundleIdentifier tunnelBundleIdentifier: String,
        extra: NetworkExtensionExtra?
    ) throws -> NETunnelProviderProtocol {
        log.info("Creating NETunnelProviderProtocol for WireGuard")
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = tunnelBundleIdentifier
        protocolConfiguration.serverAddress = configuration.endpointRepresentation
        log.debug("Server address: \(configuration.endpointRepresentation.maskedDescription)")
        
        if let passwordReference = extra?.passwordReference {
            log.debug("Password reference provided")
            protocolConfiguration.passwordReference = passwordReference
        }
        
        let disconnectOnSleep = extra?.disconnectsOnSleep ?? false
        log.debug("Disconnect on sleep: \(disconnectOnSleep)")
        protocolConfiguration.disconnectOnSleep = disconnectOnSleep
        
        do {
            log.debug("Converting configuration to dictionary")
            protocolConfiguration.providerConfiguration = try asDictionary()
            log.debug("Provider configuration keys: \(protocolConfiguration.providerConfiguration?.keys.debugDescription ?? "none")")
        } catch {
            log.error("Failed to convert configuration to dictionary: \(error)")
            throw error
        }
        
        #if !os(tvOS)
        let killSwitch = extra?.killSwitch ?? false
        log.debug("Kill switch (includeAllNetworks): \(killSwitch)")
        protocolConfiguration.includeAllNetworks = killSwitch
        #endif
        
        log.info("NETunnelProviderProtocol created successfully")
        return protocolConfiguration
    }
}

// MARK: Shared data

extension WireGuard.ProviderConfiguration {

    /// The most recent (received, sent) count in bytes.
    public var dataCount: DataCount? {
        let count = defaults?.wireGuardDataCount
        if count != nil {
            log.verbose("Retrieved data count from UserDefaults")
        }
        return count
    }

    public var lastError: TunnelKitWireGuardError? {
        let error = defaults?.wireGuardLastError
        if let error = error {
            log.debug("Retrieved last error from UserDefaults: \(error.rawValue)")
        }
        return error
    }

    public var urlForDebugLog: URL? {
        guard let defaults = defaults else {
            log.warning("No UserDefaults instance for app group: \(appGroup)")
            return nil
        }
        
        let url = defaults.wireGuardURLForDebugLog(appGroup: appGroup)
        if let url = url {
            log.verbose("Debug log URL: \(url.path)")
        } else {
            log.warning("No debug log URL found")
        }
        return url
    }

    private var defaults: UserDefaults? {
        log.verbose("Accessing UserDefaults for app group: \(appGroup)")
        return UserDefaults(suiteName: appGroup)
    }

}

extension WireGuard.ProviderConfiguration {
    public func _appexSetDataCount(_ newValue: DataCount?) {
        if newValue != nil {
            log.verbose("Setting data count in UserDefaults")
        } else {
            log.verbose("Clearing data count in UserDefaults")
        }
        defaults?.wireGuardDataCount = newValue
    }

    public func _appexSetLastError(_ newValue: TunnelKitWireGuardError?) {
        if let error = newValue {
            log.info("Setting last error in UserDefaults: \(error.rawValue)")
        } else {
            log.debug("Clearing last error in UserDefaults")
        }
        defaults?.wireGuardLastError = newValue
    }

    public var _appexDebugLogURL: URL? {
        guard let path = debugLogPath else {
            log.warning("No debug log path specified")
            return nil
        }
        
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(path) else {
            log.warning("Failed to create debug log URL for app group: \(appGroup), path: \(path)")
            return nil
        }
        
        log.debug("Debug log URL: \(url.path)")
        return url
    }

    public func _appexSetDebugLogPath() {
        if let path = debugLogPath {
            log.debug("Setting debug log path in UserDefaults: \(path)")
            defaults?.setValue(debugLogPath, forKey: WireGuard.ProviderConfiguration.Keys.logPath.rawValue)
        } else {
            log.warning("No debug log path to set in UserDefaults")
        }
    }
}

extension UserDefaults {
    public func wireGuardURLForDebugLog(appGroup: String) -> URL? {
        guard let path = string(forKey: WireGuard.ProviderConfiguration.Keys.logPath.rawValue) else {
            log.warning("No log path found in UserDefaults for key: \(WireGuard.ProviderConfiguration.Keys.logPath.rawValue)")
            return nil
        }
        
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(path) else {
            log.warning("Failed to create URL for app group: \(appGroup), path: \(path)")
            return nil
        }
        
        log.debug("Created log URL: \(url.path)")
        return url
    }

    public fileprivate(set) var wireGuardLastError: TunnelKitWireGuardError? {
        get {
            guard let rawValue = string(forKey: WireGuard.ProviderConfiguration.Keys.lastError.rawValue) else {
                return nil
            }
            log.verbose("Retrieved last error from UserDefaults: \(rawValue)")
            return TunnelKitWireGuardError(rawValue: rawValue)
        }
        set {
            guard let newValue = newValue else {
                log.verbose("Removing last error from UserDefaults")
                removeObject(forKey: WireGuard.ProviderConfiguration.Keys.lastError.rawValue)
                return
            }
            log.verbose("Setting last error in UserDefaults: \(newValue.rawValue)")
            set(newValue.rawValue, forKey: WireGuard.ProviderConfiguration.Keys.lastError.rawValue)
        }
    }

    public fileprivate(set) var wireGuardDataCount: DataCount? {
        get {
            guard let rawValue = wireGuardDataCountArray else {
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
                wireGuardRemoveDataCountArray()
                return
            }
            log.verbose("Setting data count in UserDefaults: \(newValue.received) received, \(newValue.sent) sent")
            wireGuardDataCountArray = [newValue.received, newValue.sent]
        }
    }

    @objc private var wireGuardDataCountArray: [UInt]? {
        get {
            let array = array(forKey: WireGuard.ProviderConfiguration.Keys.dataCount.rawValue) as? [UInt]
            log.verbose("Retrieved data count array from UserDefaults: \(array != nil ? "\(array!.count) elements" : "nil")")
            return array
        }
        set {
            log.verbose("Setting data count array in UserDefaults: \(newValue != nil ? "\(newValue!.count) elements" : "nil")")
            set(newValue, forKey: WireGuard.ProviderConfiguration.Keys.dataCount.rawValue)
        }
    }
    private func wireGuardRemoveDataCountArray() {
        log.verbose("Removing data count array from UserDefaults")
        removeObject(forKey: WireGuard.ProviderConfiguration.Keys.dataCount.rawValue)
    }
}
