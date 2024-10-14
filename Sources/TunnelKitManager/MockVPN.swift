
import Foundation
import NetworkExtension

/// Simulates a VPN provider.
public class MockVPN: VPN {
    private var tunnelBundleIdentifier: String?

    private var isEnabled: Bool {
        didSet {
            notifyReinstall(isEnabled)
        }
    }

    private var vpnStatus: VPNStatus {
        didSet {
            notifyStatus(vpnStatus)
        }
    }

    private let delayNanoseconds: UInt64

    public init(delay: Int = 1) {
        delayNanoseconds = DispatchTimeInterval.seconds(delay).nanoseconds
        isEnabled = false
        vpnStatus = .disconnected
    }

    // MARK: VPN

    public func prepare() {
    }

    public func install(
        _ tunnelBundleIdentifier: String,
        configuration: NetworkExtensionConfiguration,
        extra: NetworkExtensionExtra?
    ) {
        self.tunnelBundleIdentifier = tunnelBundleIdentifier
        isEnabled = true
        vpnStatus = .disconnected
    }

    public func reconnect(after: DispatchTimeInterval) async throws {
        if vpnStatus == .connected {
            vpnStatus = .disconnecting
            await delay()
        }
        vpnStatus = .connecting
        await delay()
        vpnStatus = .connected
    }

    public func reconnect(
        _ tunnelBundleIdentifier: String,
        configuration: NetworkExtensionConfiguration,
        extra: NetworkExtensionExtra?,
        after: DispatchTimeInterval
    ) async throws {
        self.tunnelBundleIdentifier = tunnelBundleIdentifier
        isEnabled = true
        if vpnStatus == .connected {
            vpnStatus = .disconnecting
            await delay()
        }
        vpnStatus = .connecting
        await delay()
        vpnStatus = .connected
    }

    public func disconnect() async {
        guard vpnStatus != .disconnected else {
            return
        }
        vpnStatus = .disconnecting
        await delay()
        vpnStatus = .disconnected
        isEnabled = false
    }

    public func uninstall() async {
        vpnStatus = .disconnected
        isEnabled = false
    }

    // MARK: Helpers

    private func notifyReinstall(_ isEnabled: Bool) {
        var notification = Notification(name: VPNNotification.didReinstall)
        notification.vpnBundleIdentifier = tunnelBundleIdentifier
        notification.vpnIsEnabled = isEnabled
        NotificationCenter.default.post(notification)
    }

    private func notifyStatus(_ status: VPNStatus) {
        var notification = Notification(name: VPNNotification.didChangeStatus)
        notification.vpnBundleIdentifier = tunnelBundleIdentifier
        notification.vpnIsEnabled = isEnabled
        notification.vpnStatus = status
        NotificationCenter.default.post(notification)
    }

    private func delay() async {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}
