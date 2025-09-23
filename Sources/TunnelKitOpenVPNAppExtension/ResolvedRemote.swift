
import Foundation
import TunnelKitCore
import SwiftyBeaver
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
        log.debug("TunnelKit.Remote", "Initialized remote for endpoint: \(originalEndpoint.maskedDescription)")
    }

    func nextEndpoint() -> Bool {
        let previousIndex = currentEndpointIndex
        currentEndpointIndex += 1
        let hasNext = currentEndpointIndex < resolvedEndpoints.count
        log.debug("TunnelKit.Remote", "Endpoint selection: moved from[\(previousIndex)] to[\(currentEndpointIndex)], hasNext: \(hasNext)")
        if hasNext, let endpoint = currentEndpoint {
            log.debug("TunnelKit.Remote", "Selected endpoint: \(endpoint.maskedDescription)")
        }
        return hasNext
    }

    func resolve(timeout: Int, queue: DispatchQueue, completionHandler: @escaping () -> Void) {
        log.info("TunnelKit.Remote", "Starting DNS resolution for \(originalEndpoint.address) (timeout: \(timeout)ms)")
        let startTime = Date()
        DNSResolver.resolve(originalEndpoint.address, timeout: timeout, queue: queue) { [weak self] result in
            let elapsed = Date().timeIntervalSince(startTime)
            log.debug("TunnelKit.Remote", "DNS resolution completed in \(String(format: "%.2f", elapsed))s")
            self?.handleResult(result)
            completionHandler()
        }
    }

    private func handleResult(_ result: Result<[DNSRecord], Error>) {
        switch result {
        case .success(let records):
            log.info("TunnelKit.Remote", "DNS resolution successful: \(records.count) records for \(originalEndpoint.address)")
            log.debug("TunnelKit.Remote", "DNS resolved addresses: \(records.map { $0.address }.maskedDescription)")
            isResolved = true
            resolvedEndpoints = unrolledEndpoints(records: records)
            log.info("TunnelKit.Remote", "Created \(resolvedEndpoints.count) compatible endpoints from DNS records")

        case .failure(let error):
            log.error("TunnelKit.Remote", "DNS resolution failed for \(originalEndpoint.address): \(error)")
            isResolved = false
            resolvedEndpoints = []
        }
    }

    private func unrolledEndpoints(records: [DNSRecord]) -> [Endpoint] {
        let compatibleRecords = records.filter {
            $0.isCompatible(withProtocol: originalEndpoint.proto)
        }
        log.debug("TunnelKit.Remote", "Filtered \(compatibleRecords.count)/\(records.count) compatible records for protocol \(originalEndpoint.proto)")
        
        let endpoints = compatibleRecords.map {
            Endpoint($0.address, originalEndpoint.proto)
        }
        log.debug("TunnelKit.Remote", "Unrolled endpoints: \(endpoints.maskedDescription)")
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
