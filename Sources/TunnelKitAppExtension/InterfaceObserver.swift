

import Foundation
#if os(iOS)
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
#elseif os(macOS)
import CoreWLAN
#endif
import SwiftyBeaver
import TunnelKitLogging

private let log = TKLogger.shared

/// Observes changes in the current Wi-Fi network.
public class InterfaceObserver: NSObject {

    /// A change in Wi-Fi state occurred.
    public static let didDetectWifiChange = Notification.Name("InterfaceObserverDidDetectWifiChange")

    private var queue: DispatchQueue?

    private var timer: DispatchSourceTimer?

    private var lastWifiName: String?

    /**
     Starts observing Wi-Fi updates.

     - Parameter queue: The `DispatchQueue` to deliver notifications to.
     **/
    public func start(queue: DispatchQueue) {
        self.queue = queue

        let timer = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(rawValue: UInt(0)), queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler {
            self.fireWifiChangeObserver()
        }
        timer.resume()

        self.timer = timer
    }

    /**
     Stops observing Wi-Fi updates.
     **/
    public func stop() {
        timer?.cancel()
        timer = nil
        queue = nil
    }

    private func fireWifiChangeObserver() {
        InterfaceObserver.fetchCurrentSSID {
            self.fireWifiChange(withSSID: $0)
        }
    }

    private func fireWifiChange(withSSID ssid: String?) {
        if ssid != lastWifiName {
            if let current = ssid {
                log.debug("SSID is now '\(current.maskedDescription)'")
                if let last = lastWifiName, (current != last) {
                    queue?.async {
                        NotificationCenter.default.post(name: InterfaceObserver.didDetectWifiChange, object: nil)
                    }
                }
            } else {
                log.debug("SSID is null")
            }
        }
        lastWifiName = ssid
    }

    /**
     Returns the current Wi-Fi SSID if any.

     - Parameter completionHandler: Receives the current Wi-Fi SSID if any.
     **/
    public static func fetchCurrentSSID(completionHandler: @escaping (String?) -> Void) {
        #if os(iOS)
        NEHotspotNetwork.fetchCurrent {
            completionHandler($0?.ssid)
        }
        #elseif os(macOS)
        let client = CWWiFiClient.shared()
        let ssid = client.interfaces()?.compactMap { $0.ssid() }.first
        completionHandler(ssid)
        #else
        completionHandler(nil)
        #endif
    }
}
