
import Foundation
import TunnelKitOpenVPNCore

extension OpenVPN {
    struct PushReply: CustomStringConvertible {
        private static let prefix = "PUSH_REPLY,"

        private let original: String

        let options: Configuration

        init?(message: String) throws {
            guard message.hasPrefix(PushReply.prefix) else {
                return nil
            }
            guard let prefixIndex = message.range(of: PushReply.prefix)?.lowerBound else {
                return nil
            }
            original = String(message[prefixIndex...])

            let lines = original.components(separatedBy: ",")
            options = try ConfigurationParser.parsed(fromLines: lines).configuration
        }

        // MARK: CustomStringConvertible

        var description: String {
            let stripped = NSMutableString(string: original)
            ConfigurationParser.Regex.authToken.replaceMatches(
                in: stripped,
                options: [],
                range: NSRange(location: 0, length: stripped.length),
                withTemplate: "auth-token"
            )
            return stripped as String
        }
    }
}
