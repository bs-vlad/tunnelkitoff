
import Foundation

/// Helper for handling IP headers.
public struct IPHeader {
    private static let ipV4: UInt8 = 4

    private static let ipV6: UInt8 = 6

    private static let ipV4ProtocolNumber = AF_INET as NSNumber

    private static let ipV6ProtocolNumber = AF_INET6 as NSNumber

    private static let fallbackProtocolNumber = ipV4ProtocolNumber

    /**
     Returns the protocol number from the IP header of a data packet.
     
     - Parameter packet: The data to inspect.
     - Returns: A protocol number between `AF_INET` and `AF_INET6`.
     */
    public static func protocolNumber(inPacket packet: Data) -> NSNumber {
        guard !packet.isEmpty else {
            return fallbackProtocolNumber
        }

        // 'packet' contains the decrypted incoming IP packet data

        // The first 4 bits identify the IP version
        let ipVersion = (packet[0] & 0xf0) >> 4
        assert(ipVersion == ipV4 || ipVersion == ipV6)
        return (ipVersion == ipV6) ? ipV6ProtocolNumber : ipV4ProtocolNumber
    }
}
