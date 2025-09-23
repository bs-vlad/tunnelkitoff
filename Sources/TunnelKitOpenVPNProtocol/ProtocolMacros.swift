
import Foundation
import TunnelKitOpenVPNCore

extension OpenVPN {
    class ProtocolMacros {

        // UInt32(0) + UInt8(KeyMethod = 2)
        static let tlsPrefix = Data(hex: "0000000002")

        static let numberOfKeys = UInt8(8) // 3-bit
    }
}
