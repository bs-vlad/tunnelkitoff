
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
            log.error("TunnelKit.Strategy", "No remotes provided in configuration")
            fatalError("No remotes provided")
        }
        self.remotes = remotes.map(ResolvedRemote.init)
        currentRemoteIndex = 0
        log.info("TunnelKit.Strategy", "Initialized connection strategy with \(remotes.count) remotes")
        for (index, remote) in remotes.enumerated() {
            log.debug("TunnelKit.Strategy", "Remote[\(index)]: \(remote.maskedDescription):\(remote.proto.port) (\(remote.proto.socketType))")
        }
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
            log.warning("TunnelKit.Strategy", "No current remote available for endpoint selection")
            return false
        }
        log.debug("TunnelKit.Strategy", "Trying next endpoint in current remote[\(currentRemoteIndex)]: \(remote.maskedDescription)")
        if remote.nextEndpoint() {
            log.info("TunnelKit.Strategy", "Selected endpoint: \(remote.currentEndpoint?.maskedDescription ?? "unknown")")
            return true
        }

        log.info("TunnelKit.Strategy", "Exhausted endpoints for remote[\(currentRemoteIndex)], trying next remote")
        currentRemoteIndex += 1
        guard let nextRemote = currentRemote else {
            log.warning("TunnelKit.Strategy", "Exhausted all \(remotes.count) remotes, connection failed")
            return false
        }
        log.info("TunnelKit.Strategy", "Switched to remote[\(currentRemoteIndex)]: \(nextRemote.maskedDescription)")
        return true
    }

    func createSocket(
        from provider: NEProvider,
        timeout: Int,
        queue: DispatchQueue,
        completionHandler: @escaping (Result<GenericSocket, TunnelKitOpenVPNError>) -> Void) {
        guard let remote = currentRemote else {
            log.error("TunnelKit.Strategy", "No current remote available for socket creation")
            completionHandler(.failure(.exhaustedEndpoints))
            return
        }
        if remote.isResolved, let endpoint = remote.currentEndpoint {
            log.info("TunnelKit.Strategy", "Creating socket to resolved endpoint: \(endpoint.maskedDescription) (\(endpoint.proto.socketType))")
            let socket = provider.createSocket(to: endpoint)
            completionHandler(.success(socket))
            return
        }

        log.info("TunnelKit.Strategy", "No resolved endpoints available, initiating DNS resolution")
        log.debug("TunnelKit.Strategy", "DNS resolution target: \(remote.maskedDescription) (timeout: \(timeout)ms)")

        remote.resolve(timeout: timeout, queue: queue) {
            guard let endpoint = remote.currentEndpoint else {
                log.error("TunnelKit.Strategy", "DNS resolution failed - no endpoints available for \(remote.maskedDescription)")
                completionHandler(.failure(.dnsFailure))
                return
            }
            log.info("TunnelKit.Strategy", "DNS resolution successful - creating socket to: \(endpoint.maskedDescription) (\(endpoint.proto.socketType))")
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
