
import Foundation

/// Represents a specific I/O interface meant to work at the link layer (e.g. TCP/IP).
public protocol LinkInterface: IOInterface {

    /// When `true`, packets delivery is guaranteed.
    var isReliable: Bool { get }

    /// The literal address of the remote host.
    var remoteAddress: String? { get }

    /// A literal describing the remote protocol.
    var remoteProtocol: String? { get }

    /// The number of packets that this interface is able to bufferize.
    var packetBufferSize: Int { get }
}
