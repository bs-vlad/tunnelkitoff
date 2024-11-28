
import Foundation
import TunnelKitCore
import SwiftyBeaver
import TunnelKitLogging
import TunnelKitLogging

private let log = TKLogger.shared

class ResolvedRemote: CustomStringConvertible {
    let originalEndpoint: Endpoint

    private(set) var isResolved: Bool

    private(set) var resolvedEndpoints: [Endpoint]

    private var currentEndpointIndex: Int

    var currentEndpoint: Endpoint? {
        guard currentEndpointIndex < resolvedEndpoints.count else {
            return nil
        }
        return resolvedEndpoints[currentEndpointIndex]
    }

    init(_ originalEndpoint: Endpoint) {
        self.originalEndpoint = originalEndpoint
        isResolved = false
        resolvedEndpoints = []
        currentEndpointIndex = 0
    }

    func nextEndpoint() -> Bool {
        currentEndpointIndex += 1
        return currentEndpointIndex < resolvedEndpoints.count
    }

    func resolve(timeout: Int, queue: DispatchQueue, completionHandler: @escaping () -> Void) {
        DNSResolver.resolve(originalEndpoint.address, timeout: timeout, queue: queue) { [weak self] in
            self?.handleResult($0)
            completionHandler()
        }
    }

    private func handleResult(_ result: Result<[DNSRecord], Error>) {
        switch result {
        case .success(let records):
            log.debug("DNS resolved addresses: \(records.map { $0.address }.maskedDescription)")
            isResolved = true
            resolvedEndpoints = unrolledEndpoints(records: records)

        case .failure:
            log.error("DNS resolution failed!")
            isResolved = false
            resolvedEndpoints = []
        }
    }

    private func unrolledEndpoints(records: [DNSRecord]) -> [Endpoint] {
        let endpoints = records.filter {
            $0.isCompatible(withProtocol: originalEndpoint.proto)
        }.map {
            Endpoint($0.address, originalEndpoint.proto)
        }
        log.debug("Unrolled endpoints: \(endpoints.maskedDescription)")
        return endpoints
    }

    // MARK: CustomStringConvertible

    var description: String {
        "{\(originalEndpoint.maskedDescription), resolved: \(resolvedEndpoints.maskedDescription)}"
    }
}

private extension DNSRecord {
    func isCompatible(withProtocol proto: EndpointProtocol) -> Bool {
        if isIPv6 {
            return proto.socketType != .udp4 && proto.socketType != .tcp4
        } else {
            return proto.socketType != .udp6 && proto.socketType != .tcp6
        }
    }
}
