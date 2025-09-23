
import Foundation
import TunnelKitCore

/// Entity able to produce a `LinkInterface`.
public protocol LinkProducer {

    /**
     Returns a `LinkInterface`.
 
     - Parameter userObject: Optional user data.
     - Returns: A  generic `LinkInterface`.
     **/
    func link(userObject: Any?) -> LinkInterface
}
