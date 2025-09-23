
import Foundation

/// Receives events from a `GenericSocket`.
public protocol GenericSocketDelegate: AnyObject {

    /**
     The socket timed out.
     **/
    func socketDidTimeout(_ socket: GenericSocket)

    /**
     The socket became active.
     **/
    func socketDidBecomeActive(_ socket: GenericSocket)

    /**
     The socket shut down.
     
     - Parameter failure: `true` if the shutdown was caused by a failure.
     **/
    func socket(_ socket: GenericSocket, didShutdownWithFailure failure: Bool)

    /**
     The socket has a better path.
     **/
    func socketHasBetterPath(_ socket: GenericSocket)
}

/// An opaque socket implementation.
public protocol GenericSocket {

    /// The address of the remote endpoint.
    var remoteAddress: String? { get }

    /// `true` if the socket has a better path.
    var hasBetterPath: Bool { get }

    /// `true` if the socket was shut down.
    var isShutdown: Bool { get }

    /// The optional delegate for events.
    var delegate: GenericSocketDelegate? { get set }

    /**
     Observes socket events.

     - Parameter queue: The queue to observe events in.
     - Parameter activeTimeout: The timeout in milliseconds for socket activity.
     **/
    func observe(queue: DispatchQueue, activeTimeout: Int)

    /**
     Stops observing socket events.
     **/
    func unobserve()

    /**
     Shuts down the socket
     **/
    func shutdown()

    /**
     Returns an upgraded socket if available (e.g. when a better path exists).
 
     - Returns: An upgraded socket if any.
     **/
    func upgraded() -> GenericSocket?
}
