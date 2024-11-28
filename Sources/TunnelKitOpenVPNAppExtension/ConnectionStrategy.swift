
import Foundation
import NetworkExtension
import SwiftyBeaver
import TunnelKitCore
import TunnelKitAppExtension
import TunnelKitOpenVPNCore
import TunnelKitOpenVPNManager
import TunnelKitLogging

private let log = TKLogger.shared

class ConnectionStrategy {
    private var remotes: [ResolvedRemote]
    private var currentRemoteIndex: Int

    var currentRemote: ResolvedRemote? {
        guard currentRemoteIndex < remotes.count else {
            return nil
        }
        return remotes[currentRemoteIndex]
    }

    init(configuration: OpenVPN.Configuration) {
        guard let remotes = configuration.processedRemotes, !remotes.isEmpty else {
            fatalError("No remotes provided")
        }
        self.remotes = remotes.map(ResolvedRemote.init)
        currentRemoteIndex = 0
    }

    func hasEndpoints() -> Bool {
        guard let remote = currentRemote else {
            return false
        }
        return !remote.isResolved || remote.currentEndpoint != nil
    }

    @discardableResult
    func tryNextEndpoint() -> Bool {
        guard let remote = currentRemote else {
            return false
        }
        log.debug("Try next endpoint in current remote: \(remote.maskedDescription)")
        if remote.nextEndpoint() {
            return true
        }

        log.debug("Exhausted endpoints, try next remote")
        currentRemoteIndex += 1
        guard let _ = currentRemote else {
            log.debug("Exhausted remotes, giving up")
            return false
        }
        return true
    }

    func createSocket(
        from provider: NEProvider,
        timeout: Int,
        queue: DispatchQueue,
        completionHandler: @escaping (Result<GenericSocket, TunnelKitOpenVPNError>) -> Void) {
        guard let remote = currentRemote else {
            completionHandler(.failure(.exhaustedEndpoints))
            return
        }
        if remote.isResolved, let endpoint = remote.currentEndpoint {
            log.debug("Pick current endpoint: \(endpoint.maskedDescription)")
            let socket = provider.createSocket(to: endpoint)
            completionHandler(.success(socket))
            return
        }

        log.debug("No resolved endpoints, will resort to DNS resolution")
        log.debug("DNS resolve address: \(remote.maskedDescription)")

        remote.resolve(timeout: timeout, queue: queue) {
            guard let endpoint = remote.currentEndpoint else {
                log.error("No endpoints available")
                completionHandler(.failure(.dnsFailure))
                return
            }
            log.debug("Pick current endpoint: \(endpoint.maskedDescription)")
            let socket = provider.createSocket(to: endpoint)
            completionHandler(.success(socket))
        }
    }
}

private extension NEProvider {
    func createSocket(to endpoint: Endpoint) -> GenericSocket {
        let ep = NWHostEndpoint(hostname: endpoint.address, port: "\(endpoint.proto.port)")
        switch endpoint.proto.socketType {
        case .udp, .udp4, .udp6:
            let impl = createUDPSession(to: ep, from: nil)
            return NEUDPSocket(impl: impl)

        case .tcp, .tcp4, .tcp6:
            let impl = createTCPConnection(to: ep, enableTLS: false, tlsParameters: nil, delegate: nil)
            return NETCPSocket(impl: impl)
        }
    }
}
