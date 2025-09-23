import Foundation

///Optimized

/// VPN notifications.
public enum VPNNotification {
    public static let didReinstall = Notification.Name("VPNDidReinstall")
    public static let didChangeStatus = Notification.Name("VPNDidChangeStatus")
    public static let didFail = Notification.Name("VPNDidFail")
}

extension Notification {
    private enum UserInfoKey: String {
        case bundleIdentifier = "BundleIdentifier"
        case isEnabled = "IsEnabled"
        case status = "Status"
        case error = "Error"
        case connectionDate = "ConnectionDate"
    }
    
    public var vpnBundleIdentifier: String? {
        get { userInfo?[UserInfoKey.bundleIdentifier.rawValue] as? String }
        set { setUserInfoValue(newValue, for: .bundleIdentifier) }
    }

    public var vpnIsEnabled: Bool? {
        get { userInfo?[UserInfoKey.isEnabled.rawValue] as? Bool }
        set { setUserInfoValue(newValue, for: .isEnabled) }
    }

    public var vpnStatus: VPNStatus? {
        get { userInfo?[UserInfoKey.status.rawValue] as? VPNStatus }
        set { setUserInfoValue(newValue, for: .status) }
    }

    public var vpnError: Error? {
        get { userInfo?[UserInfoKey.error.rawValue] as? Error }
        set { setUserInfoValue(newValue, for: .error) }
    }

    public var connectionDate: Date? {
        get { userInfo?[UserInfoKey.connectionDate.rawValue] as? Date }
        set { setUserInfoValue(newValue, for: .connectionDate) }
    }

    public var connectionDuration: TimeInterval? {
        guard let date = connectionDate else { return nil }
        return Date().timeIntervalSince(date)
    }

    public var formattedDuration: String? {
        guard let duration = connectionDuration else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration)
    }

    private mutating func setUserInfoValue(_ value: Any?, for key: UserInfoKey) {
        var info = userInfo ?? [:]
        info[key.rawValue] = value
        userInfo = info
    }
}
