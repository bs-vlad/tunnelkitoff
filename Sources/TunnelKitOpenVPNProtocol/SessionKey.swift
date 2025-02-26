

import Foundation
import SwiftyBeaver
import TunnelKitCore
import TunnelKitOpenVPNCore
import CTunnelKitCore
import CTunnelKitOpenVPNProtocol
import TunnelKitLogging

private let log = TKLogger.shared

extension OpenVPN {
    class SessionKey {
        enum State {
            case invalid, hardReset, softReset, tls
        }

        enum ControlState {
            case preAuth, preIfConfig, connected
        }

        let id: UInt8 // 3-bit

        let timeout: TimeInterval

        let startTime: Date

        var state = State.invalid

        var controlState: ControlState?

        var tlsOptional: TLSBox?

        var tls: TLSBox {
            guard let tls = tlsOptional else {
                fatalError("TLSBox accessed when nil")
            }
            return tls
        }

        var dataPath: DataPath?

        private var isTLSConnected: Bool

        init(id: UInt8, timeout: TimeInterval) {
            self.id = id
            self.timeout = timeout

            startTime = Date()
            state = .invalid
            isTLSConnected = false
        }

        // Ruby: Key.hard_reset_timeout
        func didHardResetTimeOut(link: LinkInterface) -> Bool {
            return ((state == .hardReset) && (-startTime.timeIntervalSinceNow > CoreConfiguration.OpenVPN.hardResetTimeout))
        }

        // Ruby: Key.negotiate_timeout
        func didNegotiationTimeOut(link: LinkInterface) -> Bool {
            return ((controlState != .connected) && (-startTime.timeIntervalSinceNow > timeout))
        }

        // Ruby: Key.on_tls_connect
        func shouldOnTLSConnect() -> Bool {
            guard !isTLSConnected else {
                return false
            }
            if tls.isConnected() {
                isTLSConnected = true
            }
            return isTLSConnected
        }

        func encrypt(packets: [Data]) throws -> [Data]? {
            guard let dataPath = dataPath else {
                log.warning("Data: Set dataPath first")
                return nil
            }
            return try dataPath.encryptPackets(packets, key: id)
        }

        func decrypt(packets: [Data]) throws -> [Data]? {
            guard let dataPath = dataPath else {
                log.warning("Data: Set dataPath first")
                return nil
            }
            var keepAlive = false
            let decrypted = try dataPath.decryptPackets(packets, keepAlive: &keepAlive)
            if keepAlive {
                log.debug("Data: Received ping, do nothing")
            }
            return decrypted
        }
    }
}
