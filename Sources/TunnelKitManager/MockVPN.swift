import Foundation
import NetworkExtension

/// Simulates a VPN provider.
public class MockVPN: VPN {
    private var tunnelBundleIdentifier: String?
    private var mockConnectionDate: Date?

    private var isEnabled: Bool {
        didSet {
            notifyReinstall(isEnabled)
        }
    }

    private var vpnStatus: VPNStatus {
        didSet {
            if vpnStatus == .connected && oldValue != .connected {
                mockConnectionDate = Date()
            } else if vpnStatus != .connected {
                mockConnectionDate = nil
            }
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
        mockConnectionDate = nil
    }

    public func reconnect(after: DispatchTimeInterval) async throws {
        vpnStatus = .disconnecting
        await delay()
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
        try await reconnect(after: after)
    }

    public func disconnect() async {
        vpnStatus = .disconnecting
        await delay()
        vpnStatus = .disconnected
        mockConnectionDate = nil
    }

    public func uninstall() async {
        vpnStatus = .disconnecting
        await delay()
        vpnStatus = .disconnected
        mockConnectionDate = nil
        isEnabled = false
    }

    // MARK: Notifications

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
        notification.connectionDate = mockConnectionDate
        NotificationCenter.default.post(notification)
    }

    private func delay() async {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}
