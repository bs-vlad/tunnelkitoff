import Foundation
import TunnelKitLogging
import NetworkExtension
import TunnelKitCore
import SwiftyBeaver

private let log = TKLogger.self

/// `TunnelInterface` implementation via NetworkExtension.
public class NETunnelInterface: TunnelInterface {
    private weak var impl: NEPacketTunnelFlow?

    public init(impl: NEPacketTunnelFlow) {
        self.impl = impl
    }

    // MARK: TunnelInterface

    public var isPersistent: Bool {
        return false
    }

    // MARK: IOInterface

    public func setReadHandler(queue: DispatchQueue, _ handler: @escaping ([Data]?, Error?) -> Void) {
        loopReadPackets(queue, handler)
    }

    private func loopReadPackets(_ queue: DispatchQueue, _ handler: @escaping ([Data]?, Error?) -> Void) {

        // WARNING: runs in NEPacketTunnelFlow queue
        impl?.readPackets { [weak self] (packets, _) in
            queue.sync {
                self?.loopReadPackets(queue, handler)
                handler(packets, nil)
            }
        }
    }

    public func writePacket(_ packet: Data, completionHandler: ((Error?) -> Void)?) {
        let protocolNumber = IPHeader.protocolNumber(inPacket: packet)
        impl?.writePackets([packet], withProtocols: [protocolNumber])
        completionHandler?(nil)
    }

    public func writePackets(_ packets: [Data], completionHandler: ((Error?) -> Void)?) {
        let protocols = packets.map {
            IPHeader.protocolNumber(inPacket: $0)
        }
        impl?.writePackets(packets, withProtocols: protocols)
        completionHandler?(nil)
    }
}
