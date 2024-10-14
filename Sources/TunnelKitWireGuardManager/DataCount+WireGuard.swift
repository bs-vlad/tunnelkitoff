import Foundation
import TunnelKitCore

extension DataCount {
    public static func from(wireGuardString string: String) -> DataCount? {
        var bytesReceived: UInt?
        var bytesSent: UInt?

        string.enumerateLines { line, stop in
            if bytesReceived == nil, let value = line.getPrefix("rx_bytes=") {
                bytesReceived = value
            } else if bytesSent == nil, let value = line.getPrefix("tx_bytes=") {
                bytesSent = value
            }
            if bytesReceived != nil, bytesSent != nil {
                stop = true
            }
        }

        guard let bytesReceived, let bytesSent else {
            return nil
        }

        return DataCount(bytesReceived, bytesSent)
    }
}

private extension String {
    func getPrefix(_ prefixKey: String) -> UInt? {
        guard hasPrefix(prefixKey) else {
            return nil
        }
        return UInt(dropFirst(prefixKey.count))
    }
}
