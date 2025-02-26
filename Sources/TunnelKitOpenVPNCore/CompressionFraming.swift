

import Foundation
import CTunnelKitOpenVPNCore

extension OpenVPN {

    /// Defines the type of compression framing.
    public enum CompressionFraming: Int, Codable, CustomStringConvertible {

        /// No compression framing.
        case disabled

        /// Framing compatible with `comp-lzo` (deprecated in 2.4).
        case compLZO

        /// Framing compatible with 2.4 `compress`.
        case compress

        /// Framing compatible with 2.4 `compress` (version 2, e.g. stub-v2).
        case compressV2

        public var native: CompressionFramingNative {
            guard let val = CompressionFramingNative(rawValue: rawValue) else {
                fatalError("Unhandled CompressionFraming bridging")
            }
            return val
        }

        // MARK: CustomStringConvertible

        public var description: String {
            switch self {
            case .disabled:
                return "disabled"

            case .compress:
                return "compress"

            case .compressV2:
                return "compress"

            case .compLZO:
                return "comp-lzo"
            }
        }
    }
}
