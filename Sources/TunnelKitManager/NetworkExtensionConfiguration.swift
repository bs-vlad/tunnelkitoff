
import Foundation
import NetworkExtension

/// Extra configuration parameters to attach optionally to a `NetworkExtensionConfiguration`.
public struct NetworkExtensionExtra {

    /// A password reference to the keychain.
    public var passwordReference: Data?

    /// A set of on-demand rules.
    public var onDemandRules: [NEOnDemandRule] = []

    /// Disconnects on sleep if `true`.
    public var disconnectsOnSleep = false

    #if !os(tvOS)
    /// Enables best-effort kill switch.
    public var killSwitch = false
    #endif

    /// Extra user configuration data.
    public var userData: [String: Any]?

    public init() {
    }
}

/// Configuration object to feed to a `NetworkExtensionProvider`.
public protocol NetworkExtensionConfiguration {

    /// The profile title in device settings.
    var title: String { get }

    /**
     Returns a representation for use with tunnel implementations.
     
     - Parameter bundleIdentifier: The bundle identifier of the tunnel extension.
     - Parameter extra: The optional `Extra` arguments.
     - Returns An object to use with tunnel implementations.
     */
    func asTunnelProtocol(
        withBundleIdentifier bundleIdentifier: String,
        extra: NetworkExtensionExtra?
    ) throws -> NETunnelProviderProtocol
}
