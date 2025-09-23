import Foundation
import NetworkExtension
import SwiftyBeaver
import TunnelKitCore
import TunnelKitLogging

private let log = TKLogger.shared

/// TCP implementation of a `GenericSocket` via NetworkExtension.
public class NETCPSocket: NSObject, GenericSocket {
    private static var linkContext = 0

    public let impl: NWTCPConnection

    public init(impl: NWTCPConnection) {
        self.impl = impl
        isActive = false
        isShutdown = false
    }

    // MARK: GenericSocket

    private weak var queue: DispatchQueue?

    private var isActive: Bool

    public private(set) var isShutdown: Bool

    public var remoteAddress: String? {
        return (impl.remoteAddress as? NWHostEndpoint)?.hostname
    }

    public var hasBetterPath: Bool {
        return impl.hasBetterPath
    }

    public weak var delegate: GenericSocketDelegate?

    public func observe(queue: DispatchQueue, activeTimeout: Int) {
        isActive = false

        self.queue = queue
        queue.schedule(after: .milliseconds(activeTimeout)) { [weak self] in
            guard let _self = self else {
                return
            }
            guard _self.isActive else {
                _self.delegate?.socketDidTimeout(_self)
                return
            }
        }
        impl.addObserver(self, forKeyPath: #keyPath(NWTCPConnection.state), options: [.initial, .new], context: &NETCPSocket.linkContext)
        impl.addObserver(self, forKeyPath: #keyPath(NWTCPConnection.hasBetterPath), options: .new, context: &NETCPSocket.linkContext)
    }

    public func unobserve() {
        impl.removeObserver(self, forKeyPath: #keyPath(NWTCPConnection.state), context: &NETCPSocket.linkContext)
        impl.removeObserver(self, forKeyPath: #keyPath(NWTCPConnection.hasBetterPath), context: &NETCPSocket.linkContext)
    }

    public func shutdown() {
        impl.writeClose()
        impl.cancel()
    }

    public func upgraded() -> GenericSocket? {
        guard impl.hasBetterPath else {
            return nil
        }
        return NETCPSocket(impl: NWTCPConnection(upgradeFor: impl))
    }

    // MARK: Connection KVO (any queue)

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &NETCPSocket.linkContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
//        if let keyPath = keyPath {
//            log.debug("KVO change reported (\(anyPointer(object)).\(keyPath))")
//        }
        queue?.async {
            self.observeValueInTunnelQueue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func observeValueInTunnelQueue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
//        if let keyPath = keyPath {
//            log.debug("KVO change reported (\(anyPointer(object)).\(keyPath))")
//        }
        guard let impl = object as? NWTCPConnection, (impl == self.impl) else {
            log.warning("Discard KVO change from old socket")
            return
        }
        guard let keyPath = keyPath else {
            return
        }
        switch keyPath {
        case #keyPath(NWTCPConnection.state):
            if let resolvedEndpoint = impl.remoteAddress {
                log.debug("Socket state is \(impl.state) (endpoint: \(impl.endpoint.maskedDescription) -> \(resolvedEndpoint.maskedDescription))")
            } else {
                log.debug("Socket state is \(impl.state) (endpoint: \(impl.endpoint.maskedDescription) -> in progress)")
            }

            switch impl.state {
            case .connected:
                guard !isActive else {
                    return
                }
                isActive = true
                delegate?.socketDidBecomeActive(self)

            case .cancelled:
                isShutdown = true
                delegate?.socket(self, didShutdownWithFailure: false)

            case .disconnected:
                isShutdown = true
                delegate?.socket(self, didShutdownWithFailure: true)

            default:
                break
            }

        case #keyPath(NWTCPConnection.hasBetterPath):
            guard impl.hasBetterPath else {
                break
            }
            log.debug("Socket has a better path")
            delegate?.socketHasBetterPath(self)

        default:
            break
        }
    }
}

extension NETCPSocket {
    public override var description: String {
        guard let hostEndpoint = impl.endpoint as? NWHostEndpoint else {
            return impl.endpoint.maskedDescription
        }
        return "\(hostEndpoint.hostname.maskedDescription):\(hostEndpoint.port)"
    }
}
