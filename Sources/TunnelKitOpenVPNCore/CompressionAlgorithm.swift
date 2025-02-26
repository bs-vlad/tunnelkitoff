
import Foundation
import CTunnelKitOpenVPNCore

extension OpenVPN {

    /// Defines the type of compression algorithm.
    public enum CompressionAlgorithm: Int, Codable, CustomStringConvertible {

        /// No compression.
        case disabled

        /// LZO compression.
        case LZO

        /// Any other compression algorithm (unsupported).
        case other

        public var native: CompressionAlgorithmNative {
            guard let val = CompressionAlgorithmNative(rawValue: rawValue) else {
                fatalError("Unhandled CompressionAlgorithm bridging")
            }
            return val
        }

        // MARK: CustomStringConvertible

        public var description: String {
            switch self {
            case .disabled:
                return "disabled"

            case .LZO:
                return "lzo"

            case .other:
                return "other"
            }
        }
    }
}
