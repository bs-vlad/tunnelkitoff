
import Foundation

/// VPN notifications.
public struct VPNNotification {

    /// The VPN did reinstall.
    public static let didReinstall = Notification.Name("VPNDidReinstall")

    /// The VPN did change its status.
    public static let didChangeStatus = Notification.Name("VPNDidChangeStatus")

    /// The VPN triggered some error.
    public static let didFail = Notification.Name("VPNDidFail")
}

extension Notification {

    /// The VPN bundle identifier.
    public var vpnBundleIdentifier: String? {
        get {
            guard let vpnBundleIdentifier = userInfo?["BundleIdentifier"] as? String else {
                fatalError("Notification has no vpnBundleIdentifier")
            }
            return vpnBundleIdentifier
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["BundleIdentifier"] = newValue
            userInfo = newInfo
        }
    }

    /// The current VPN enabled state.
    public var vpnIsEnabled: Bool {
        get {
            guard let vpnIsEnabled = userInfo?["IsEnabled"] as? Bool else {
                fatalError("Notification has no vpnIsEnabled")
            }
            return vpnIsEnabled
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["IsEnabled"] = newValue
            userInfo = newInfo
        }
    }

    /// The current VPN status.
    public var vpnStatus: VPNStatus {
        get {
            guard let vpnStatus = userInfo?["Status"] as? VPNStatus else {
                fatalError("Notification has no vpnStatus")
            }
            return vpnStatus
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["Status"] = newValue
            userInfo = newInfo
        }
    }

    /// The triggered VPN error.
    public var vpnError: Error {
        get {
            guard let vpnError = userInfo?["Error"] as? Error else {
                fatalError("Notification has no vpnError")
            }
            return vpnError
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["Error"] = newValue
            userInfo = newInfo
        }
    }

    /// The current VPN connection date.
    public var connectionDate: Date? {
        get {
            guard let date = userInfo?["ConnectionDate"] as? Date else {
                fatalError("Notification has no connectionDate")
            }
            return date
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["ConnectionDate"] = newValue
            userInfo = newInfo
        }
    }
}
