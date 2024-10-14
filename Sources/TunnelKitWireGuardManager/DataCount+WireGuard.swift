import Foundation
import TunnelKitCore

///Optimized
extension DataCount {
    public static func from(wireGuardString string: String) -> DataCount? {
        let lines = string.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return nil }
        
        let bytesReceived = lines[0].getPrefix("rx_bytes=")
        let bytesSent = lines[1].getPrefix("tx_bytes=")
        
        guard let bytesReceived = bytesReceived, let bytesSent = bytesSent else {
            return nil
        }
        
        return DataCount(bytesReceived, bytesSent)
    }
}

private extension Substring {
    func getPrefix(_ prefixKey: String) -> UInt? {
        guard hasPrefix(prefixKey) else { return nil }
        return UInt(dropFirst(prefixKey.count))
    }
}
