
import Foundation

/// Defines the basics of a VPN session.
public protocol Session {

    /**
     Establishes the link interface for this session. The interface must be up and running for sending and receiving packets.
     
     - Precondition: `link` is an active network interface.
     - Postcondition: The VPN negotiation is started.
     - Parameter link: The `LinkInterface` on which to establish the VPN session.
     */
    func setLink(_ link: LinkInterface)

    /**
     Returns `true` if the current session can rebind to a new link with `rebindLink(...)`.
     
     - Returns: `true` if supports link rebinding.
     */
    func canRebindLink() -> Bool

    /**
     Rebinds the session to a new link if supported.
     
     - Precondition: `link` is an active network interface.
     - Postcondition: The VPN session is active.
     - Parameter link: The `LinkInterface` on which to establish the VPN session.
     - Seealso: `canRebindLink()`
     */
    func rebindLink(_ link: LinkInterface)

    /**
     Establishes the tunnel interface for this session. The interface must be up and running for sending and receiving packets.
     
     - Precondition: `tunnel` is an active network interface.
     - Postcondition: The VPN data channel is open.
     - Parameter tunnel: The `TunnelInterface` on which to exchange the VPN data traffic.
     */
    func setTunnel(tunnel: TunnelInterface)

    /**
     Returns the current data bytes count.
     
     - Returns: The current data bytes count.
     */
    func dataCount() -> DataCount?

    /**
     Returns the current server configuration.

     - Returns: The current server configuration, represented as a generic object.
     */
    func serverConfiguration() -> Any?

    /**
     Shuts down the session with an optional `Error` reason. Does nothing if the session is already stopped or about to stop.
     
     - Parameter error: An optional `Error` being the reason of the shutdown.
     */
    func shutdown(error: Error?)

    /**
     Shuts down the session with an optional `Error` reason and signals a reconnect flag to `OpenVPNSessionDelegate.sessionDidStop(...)`. Does nothing if the session is already stopped or about to stop.
     
     - Parameter error: An optional `Error` being the reason of the shutdown.
     - Seealso: `OpenVPNSessionDelegate.sessionDidStop(...)`
     */
    func reconnect(error: Error?)

    /**
     Cleans up the session resources.
     */
    func cleanup()
}
