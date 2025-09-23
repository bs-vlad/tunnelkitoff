
import Foundation

/// Global library settings.
public class CoreConfiguration {

    /// Unique identifier of the library.
    public static let identifier = "com.algoritmico.TunnelKit"

    /// Library version as seen in `Info.plist`.
    public static let version: String = {
        let bundle = Bundle(for: CoreConfiguration.self)
        guard let info = bundle.infoDictionary else {
            return ""
        }
//        guard let version = info["CFBundleShortVersionString"] as? String else {
//            return ""
//        }
//        guard let build = info["CFBundleVersion"] as? String else {
//            return version
//        }
//        return "\(version) (\(build))"
        return info["CFBundleShortVersionString"] as? String ?? ""
    }()

    /// Masks private data in logs.
    public static var masksPrivateData = true

    /// String representing library version.
    public static var versionIdentifier: String?

    /// Enables logging of sensitive data (hardcoded to false).
    public static let logsSensitiveData = false
}

extension CustomStringConvertible {

    /// Returns a masked version of `description` in case `CoreConfiguration.masksPrivateData` is `true`.
    public var maskedDescription: String {
        guard CoreConfiguration.masksPrivateData else {
            return description
        }
//        var data = description.data(using: .utf8)!
//        let dataCount = CC_LONG(data.count)
//        var md = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
//        md.withUnsafeMutableBytes {
//            _ = CC_SHA1(&data, dataCount, $0.bytePointer)
//        }
//        return "#\(md.toHex().prefix(16))#"
        return "<masked>"
    }
}
