
import Foundation

/// A pair of received/sent bytes count.
public struct DataCount: Equatable {

    /// Received bytes count.
    public let received: UInt

    /// Sent bytes count.
    public let sent: UInt

    public init(_ received: UInt, _ sent: UInt) {
        self.received = received
        self.sent = sent
    }
}
