
import Foundation

/// Result of `DNSResolver`.
public struct DNSRecord {

    /// Address string.
    public let address: String

    /// `true` if IPv6.
    public let isIPv6: Bool

    public init(address: String, isIPv6: Bool) {
        self.address = address
        self.isIPv6 = isIPv6
    }
}

/// Errors coming from `DNSResolver`.
public enum DNSError: Error {

    /// Resolution failed.
    case failure

    /// Resolution timed out.
    case timeout
}

/// Convenient methods for DNS resolution.
public class DNSResolver {

    private static let queue = DispatchQueue(label: "DNSResolver")

    /**
     Resolves a hostname asynchronously.
     
     - Parameter hostname: The hostname to resolve.
     - Parameter timeout: The timeout in milliseconds.
     - Parameter queue: The queue to execute the `completionHandler` in.
     - Parameter completionHandler: The completion handler with the resolved addresses and an optional error.
     */
    public static func resolve(_ hostname: String, timeout: Int, queue: DispatchQueue, completionHandler: @escaping (Result<[DNSRecord], Error>) -> Void) {
        var pendingHandler: ((Result<[DNSRecord], Error>) -> Void)? = completionHandler
        let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
        DNSResolver.queue.async {
            CFHostStartInfoResolution(host, .addresses, nil)
            guard let handler = pendingHandler else {
                return
            }
            DNSResolver.didResolve(host: host) { result in
                queue.async {
                    handler(result)
                    pendingHandler = nil
                }
            }
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(timeout)) {
            guard let handler = pendingHandler else {
                return
            }
            CFHostCancelInfoResolution(host, .addresses)
            handler(.failure(TunnelKitCoreError.dnsResolver(.timeout)))
            pendingHandler = nil
        }
    }

    private static func didResolve(host: CFHost, completionHandler: @escaping (Result<[DNSRecord], Error>) -> Void) {
        var success: DarwinBoolean = false
        guard let rawAddresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as Array? else {
            completionHandler(.failure(TunnelKitCoreError.dnsResolver(.failure)))
            return
        }

        var records: [DNSRecord] = []
        for case let rawAddress as Data in rawAddresses {
            var ipAddress = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result: Int32 = rawAddress.withUnsafeBytes {
                let addr = $0.bindMemory(to: sockaddr.self).baseAddress!
                return getnameinfo(
                    addr,
                    socklen_t(rawAddress.count),
                    &ipAddress,
                    socklen_t(ipAddress.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
            }
            guard result == 0 else {
                continue
            }
            let address = String(cString: ipAddress)
            if rawAddress.count == 16 {
                records.append(DNSRecord(address: address, isIPv6: false))
            } else {
                records.append(DNSRecord(address: address, isIPv6: true))
            }
        }
        guard !records.isEmpty else {
            completionHandler(.failure(TunnelKitCoreError.dnsResolver(.failure)))
            return
        }
        completionHandler(.success(records))
    }

    /**
     Returns a `String` representation from a numeric IPv4 address.
     
     - Parameter ipv4: The IPv4 address as a 32-bit number.
     - Returns: The string representation of `ipv4`.
     */
    public static func string(fromIPv4 ipv4: UInt32) -> String {
        var remainder = ipv4
        var groups: [UInt32] = []
        var base: UInt32 = 1 << 24
        while base > 0 {
            groups.append(remainder / base)
            remainder %= base
            base >>= 8
        }
        return groups.map { "\($0)" }.joined(separator: ".")
    }

    /**
     Returns a numeric representation from an IPv4 address.
     
     - Parameter string: The IPv4 address as a string.
     - Returns: The numeric representation of `string`.
     */
    public static func ipv4(fromString string: String) -> UInt32? {
        var addr = in_addr()
        let result = string.withCString {
            inet_pton(AF_INET, $0, &addr)
        }
        guard result > 0 else {
            return nil
        }
        return CFSwapInt32BigToHost(addr.s_addr)
    }

    private init() {
    }
}
