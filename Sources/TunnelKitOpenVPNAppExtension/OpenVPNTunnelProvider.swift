import NetworkExtension
import SwiftyBeaver
#if os(iOS)
import SystemConfiguration.CaptiveNetwork
#elseif os(macOS)
import CoreWLAN
#endif
import TunnelKitCore
import TunnelKitOpenVPNCore
import TunnelKitManager
import TunnelKitOpenVPNManager
import TunnelKitOpenVPNProtocol
import TunnelKitAppExtension
import CTunnelKitCore
import __TunnelKitUtils
import TunnelKitLogging

private let log = TKLogger.shared
/**
 Provides an all-in-one `NEPacketTunnelProvider` implementation for use in a
 Packet Tunnel Provider extension both on iOS and macOS.
 */
open class OpenVPNTunnelProvider: NEPacketTunnelProvider {

    // MARK: Tweaks

    /// An optional string describing host app version on tunnel start.
    public var appVersion: String?

    /// The log separator between sessions.
    public var logSeparator = "--- EOF ---"

    /// The maximum size of the log.
    public var maxLogSize = 20000

    /// The log level when `OpenVPNTunnelProvider.Configuration.shouldDebug` is enabled.
    public var debugLogLevel: SwiftyBeaver.Level = .debug

    /// The number of milliseconds after which a DNS resolution fails.
    public var dnsTimeout = 3000

    /// The number of milliseconds after which the tunnel gives up on a connection attempt.
    public var socketTimeout = 5000

    /// The number of milliseconds after which the tunnel is shut down forcibly.
    public var shutdownTimeout = 2000

    /// The number of milliseconds after which a reconnection attempt is issued.
    public var reconnectionDelay = 1000

    /// The number of link failures after which the tunnel is expected to die.
    public var maxLinkFailures = 3

    /// The number of milliseconds between data count updates. Set to 0 to disable updates (default).
    public var dataCountInterval = 0

    /// A list of public DNS servers to use as fallback when none are provided (defaults to CloudFlare).
    public var fallbackDNSServers = [
        "1.1.1.1",
        "1.0.0.1",
        "2606:4700:4700::1111",
        "2606:4700:4700::1001"
    ]

    // MARK: Constants

    private let tunnelQueue = DispatchQueue(label: OpenVPNTunnelProvider.description(), qos: .userInitiated, 
                                          attributes: [.concurrent])

    private let prngSeedLength = 64

    private var cachesURL: URL {
        let appGroup = cfg.appGroup
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            log.error("Failed to access app group container: \(appGroup)")
            fatalError("No access to app group: \(appGroup)")
        }
        log.debug("Using caches directory at: \(containerURL.path)/Library/Caches/")
        return containerURL.appendingPathComponent("Library/Caches/")
    }

    // MARK: Tunnel configuration

    private var cfg: OpenVPN.ProviderConfiguration!

    private var strategy: ConnectionStrategy!

    // MARK: Internal state

    private var session: OpenVPNSession?

    private var socket: GenericSocket?

    private var pendingStartHandler: ((Error?) -> Void)?

    private var pendingStopHandler: (() -> Void)?

    private var isCountingData = false

    private var shouldReconnect = false
    
    private var connectionAttempts = 0
    
    /// Track the current connection state for improved logging
    private var connectionState: String = "initializing"
    
    /// Track when the connection attempt started
    private var connectionStartTime: Date?
    
    /// Track latest network SSID for better debugging
    private var currentSSID: String?

    private var dataCountTimer: DispatchSourceTimer?

    // MARK: NEPacketTunnelProvider (XPC queue)

    open override var reasserting: Bool {
        didSet {
            log.debug("Reasserting flag \(reasserting ? "set" : "cleared")")
        }
    }

    open override func startTunnel(options: [String: NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
        connectionState = "starting"
        connectionStartTime = Date()
        log.info("Starting OpenVPN tunnel...")
        log.debug("Start options: \(options?.description ?? "none")")
        
        // required configuration
        do {
            guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
                let error = ConfigurationError.parameter(name: "protocolConfiguration")
                log.error("Invalid protocol configuration: \(error)")
                throw error
            }
            guard let serverAddress = tunnelProtocol.serverAddress else {
                let error = ConfigurationError.parameter(name: "protocolConfiguration.serverAddress")
                log.error("Missing server address: \(error)")
                throw error
            }
            log.info("Server address: \(serverAddress.maskedDescription)")
            
            guard let providerConfiguration = tunnelProtocol.providerConfiguration else {
                let error = ConfigurationError.parameter(name: "protocolConfiguration.providerConfiguration")
                log.error("Missing provider configuration: \(error)")
                throw error
            }
            log.debug("Provider configuration keys: \(providerConfiguration.keys)")
            
            cfg = try fromDictionary(OpenVPN.ProviderConfiguration.self, providerConfiguration)
            log.info("Successfully parsed provider configuration")
            
        } catch let cfgError as ConfigurationError {
            switch cfgError {
            case .parameter(let name):
                log.error("Tunnel configuration incomplete: \(name)")

            default:
                log.error("Tunnel configuration error: \(cfgError)")
            }
            connectionState = "configuration_error"
            completionHandler(cfgError)
            return
        } catch {
            log.error("Unexpected error in tunnel configuration: \(error)")
            connectionState = "unexpected_error"
            completionHandler(error)
            return
        }

        // prepare for logging (append)
        configureLogging()

        // logging only ACTIVE from now on
        log.info("")
        log.info(logSeparator)
        log.info("")
        log.info("OpenVPN tunnel starting - \(Date())")

        // override library configuration
        CoreConfiguration.masksPrivateData = cfg.masksPrivateData
        if let versionIdentifier = cfg.versionIdentifier {
            CoreConfiguration.versionIdentifier = versionIdentifier
            log.debug("Using version identifier: \(versionIdentifier)")
        }

        // optional credentials
        let credentials: OpenVPN.Credentials?
        if let username = protocolConfiguration.username, let passwordReference = protocolConfiguration.passwordReference {
            log.debug("Retrieving credentials for username: \(username.maskedDescription)")
            
            do {
                let password = try Keychain.password(forReference: passwordReference)
                credentials = OpenVPN.Credentials(username, password)
                log.debug("Successfully retrieved credentials from keychain")
            } catch {
                log.error("Failed to retrieve password from keychain reference: \(error)")
                connectionState = "credentials_error"
                completionHandler(ConfigurationError.credentials(details: "Keychain.password(forReference:)"))
                return
            }
        } else {
            log.debug("No credentials provided in configuration")
            credentials = nil
        }

        log.info("Starting tunnel...")
        connectionState = "initializing"
        cfg._appexSetLastError(nil)

        guard OpenVPN.prepareRandomNumberGenerator(seedLength: prngSeedLength) else {
            log.error("Failed to initialize PRNG with seed length \(prngSeedLength)")
            connectionState = "prng_error"
            completionHandler(ConfigurationError.prngInitialization)
            return
        }
        log.debug("Successfully initialized PRNG")

        if let appVersion = appVersion {
            log.info("App version: \(appVersion)")
        }
        cfg.print()

        // prepare to pick endpoints
        log.debug("Initializing connection strategy")
        strategy = ConnectionStrategy(configuration: cfg.configuration)
        log.debug("Connection strategy initialized with \(cfg.configuration.remotes?.count ?? 0) potential endpoints")

        let session: OpenVPNSession
        do {
            log.debug("Creating OpenVPN session...")
            session = try OpenVPNSession(queue: tunnelQueue, configuration: cfg.configuration, cachesURL: cachesURL)
            log.debug("OpenVPN session created successfully")
            refreshDataCount()
        } catch {
            log.error("Failed to create OpenVPN session: \(error)")
            connectionState = "session_creation_error"
            completionHandler(error)
            return
        }
        session.credentials = credentials
        session.delegate = self
        self.session = session

        logCurrentSSID()
        connectionAttempts = 0
        connectionState = "connecting"

        pendingStartHandler = completionHandler
        tunnelQueue.sync {
            log.debug("Dispatching connection attempt to tunnel queue")
            self.connectTunnel()
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        pendingStartHandler = nil
        log.info("Stopping tunnel with reason: \(reason.rawValue)")
        log.debug("Stop reason details: \(self.describeStopReason(reason))")
        connectionState = "stopping"
        cfg._appexSetLastError(nil)

        guard let session = session else {
            log.warning("Stop tunnel called but no active session exists")
            connectionState = "stopped"
            flushLog()
            completionHandler()
            forceExitOnMac()
            return
        }

        pendingStopHandler = completionHandler
        tunnelQueue.schedule(after: .milliseconds(shutdownTimeout)) { [weak self] in
            guard let weakSelf = self else {
                return
            }
            guard let pendingHandler = weakSelf.pendingStopHandler else {
                return
            }
            log.warning("Tunnel not responding after \(weakSelf.shutdownTimeout) milliseconds, forcing stop")
            weakSelf.connectionState = "force_stopped"
            weakSelf.flushLog()
            pendingHandler()
            self?.forceExitOnMac()
        }
        tunnelQueue.sync {
            log.debug("Dispatching shutdown to tunnel queue")
            session.shutdown(error: nil)
        }
    }

    // MARK: Wake/Sleep (debugging placeholders)
    
    open override func wake() {
        log.info("Wake signal received")
    }

    open override func sleep(completionHandler: @escaping () -> Void) {
        log.info("Sleep signal received")
        completionHandler()
    }

    // Helper method to describe stop reasons
    private func describeStopReason(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none:
            return "None"
        case .userInitiated:
            return "User initiated"
        case .providerFailed:
            return "Provider failed"
        case .noNetworkAvailable:
            return "No network available"
        case .unrecoverableNetworkChange:
            return "Unrecoverable network change"
        case .providerDisabled:
            return "Provider disabled"
        case .authenticationCanceled:
            return "Authentication canceled"
        case .configurationFailed:
            return "Configuration failed"
        case .idleTimeout:
            return "Idle timeout"
        case .configurationDisabled:
            return "Configuration disabled"
        case .configurationRemoved:
            return "Configuration removed"
        case .superceded:
            return "Superceded by new configuration"
        case .userLogout:
            return "User logout"
        case .userSwitch:
            return "User switch"
        case .connectionFailed:
            return "Connection failed"
        default:
            return "Unknown reason (\(reason.rawValue))"
        }
    }

    // MARK: Connection (tunnel queue)

    private func connectTunnel(upgradedSocket: GenericSocket? = nil) {
        connectionAttempts += 1
        log.info("Creating link session (attempt #\(connectionAttempts))")
        
        let elapsed = Date().timeIntervalSince(connectionStartTime ?? Date())
        log.debug("Connection attempt after \(String(format: "%.2f", elapsed))s since start")

        // reuse upgraded socket
        if let upgradedSocket = upgradedSocket, !upgradedSocket.isShutdown {
            log.debug("Socket follows a path upgrade")
            connectTunnel(via: upgradedSocket)
            return
        }

        log.debug("Requesting socket creation from connection strategy")
        strategy.createSocket(from: self, timeout: max(1000, dnsTimeout), queue: tunnelQueue) {
            switch $0 {
            case .success(let socket):
                log.debug("Socket created successfully: \(type(of: socket))")
                self.connectTunnel(via: socket)

            case .failure(let error):
                log.error("Failed to create socket: \(error)")
                
                if case .dnsFailure = error {
                    log.warning("DNS failure, trying next endpoint")
                    self.tunnelQueue.async {
                        let hasMoreEndpoints = self.strategy.tryNextEndpoint()
                        log.debug("Moving to next endpoint: \(hasMoreEndpoints ? "available" : "none left")")
                        self.connectTunnel()
                    }
                    return
                }
                self.connectionState = "socket_creation_failed"
                self.disposeTunnel(error: error)
            }
        }
    }

    private func connectTunnel(via socket: GenericSocket) {
        log.info("Will connect to \(socket)")
        cfg._appexSetLastError(nil)

        log.debug("Socket type is \(type(of: socket))")
        self.socket = socket
        self.socket?.delegate = self
        log.debug("Setting up socket observation with timeout: \(socketTimeout)ms")
        self.socket?.observe(queue: tunnelQueue, activeTimeout: socketTimeout)
    }

    private func finishTunnelDisconnection(error: Error?) {
        if let session = session {
            if shouldReconnect && session.canRebindLink() {
                log.info("Session can rebind, preserving for reconnection")
            } else {
                log.debug("Cleaning up session")
                session.cleanup()
            }
        }

        socket?.delegate = nil
        socket?.unobserve()
        log.debug("Socket observation stopped")
        socket = nil

        if let error = error {
            log.error("Tunnel did stop with error: \(error)")
            connectionState = "disconnected_with_error"
            setErrorStatus(with: error)
        } else {
            log.info("Tunnel did stop on request (no errors)")
            connectionState = "disconnected"
        }
    }

    private func disposeTunnel(error: Error?) {
        if let error = error {
            log.error("Disposing tunnel due to error: \(error)")
        } else {
            log.info("Disposing tunnel (no errors)")
        }
        
        log.info("Will dispose tunnel in \(reconnectionDelay) milliseconds...")
        tunnelQueue.asyncAfter(deadline: .now() + .milliseconds(reconnectionDelay)) { [weak self] in
            self?.reallyDisposeTunnel(error: error)
        }
    }

    private func reallyDisposeTunnel(error: Error?) {
        log.info("Really disposing tunnel now")
        flushLog()

        // failed to start
        if pendingStartHandler != nil {
            log.error("Tunnel failed to start, notifying pending start handler with error: \(error?.localizedDescription ?? "socketActivity fallback")")
            connectionState = "startup_failed"
            //
            // CAUTION
            //
            // passing nil to this callback will result in an extremely undesired situation,
            // because NetworkExtension would interpret it as "successfully connected to VPN"
            //
            // if we end up here disposing the tunnel with a pending start handled, we are
            // 100% sure that something wrong happened while starting the tunnel. in such
            // case, here we then must also make sure that an error object is ALWAYS
            // provided, so we do this with optional fallback to .socketActivity
            //
            // socketActivity makes sense, given that any other error would normally come
            // from OpenVPN.stopError. other paths to disposeTunnel() are only coming
            // from stopTunnel(), in which case we don't need to feed an error parameter to
            // the stop completion handler
            //
            pendingStartHandler?(error ?? TunnelKitOpenVPNError.socketActivity)
            pendingStartHandler = nil
        }
        // stopped intentionally
        else if pendingStopHandler != nil {
            log.info("Tunnel stopped intentionally, notifying pending stop handler")
            connectionState = "stopped_by_user"
            pendingStopHandler?()
            pendingStopHandler = nil
            forceExitOnMac()
        }
        // stopped externally, unrecoverable
        else {
            log.warning("Tunnel stopped externally (unrecoverable), cancelling tunnel with error: \(error?.localizedDescription ?? "none")")
            connectionState = "stopped_externally"
            cancelTunnelWithError(error)
            forceExitOnMac()
        }
    }

    // MARK: Data counter (tunnel queue)

    private func refreshDataCount() {
        guard dataCountInterval > 0 else { 
            log.debug("Data count updates disabled (interval = 0)")
            return 
        }
        
        log.debug("Setting up data count timer with interval: \(dataCountInterval)ms")
        dataCountTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: tunnelQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(dataCountInterval))
        timer.setEventHandler { [weak self] in
            guard let self, self.isCountingData,
                  let session = self.session,
                  let dataCount = session.dataCount() else {
                self?.cfg._appexSetDataCount(nil)
                return
            }
            log.verbose("Data count update: \(dataCount.received) received, \(dataCount.sent) sent")
            self.cfg._appexSetDataCount(dataCount)
        }
        timer.resume()
        dataCountTimer = timer
        log.debug("Data count timer started")
    }
}

extension OpenVPNTunnelProvider: GenericSocketDelegate {

    // MARK: GenericSocketDelegate (tunnel queue)

    public func socketDidTimeout(_ socket: GenericSocket) {
        log.warning("Socket timed out waiting for activity after \(socketTimeout)ms, cancelling...")
        connectionState = "socket_timeout"
        shouldReconnect = true
        socket.shutdown()

        // fallback: TCP connection timeout suggests falling back
        if let _ = socket as? NETCPSocket {
            log.debug("TCP socket timeout, attempting to use next endpoint")
            guard tryNextEndpoint() else {
                // disposeTunnel
                log.error("No more endpoints available after TCP timeout")
                return
            }
        }
    }

    public func socketDidBecomeActive(_ socket: GenericSocket) {
        log.info("Socket became active")
        connectionState = "socket_active"
        guard let session = session, let producer = socket as? LinkProducer else {
            log.warning("Cannot process active socket: missing session or socket is not a LinkProducer")
            return
        }
        if session.canRebindLink() {
            log.debug("Rebinding link to session")
            session.rebindLink(producer.link(userObject: cfg.configuration.xorMethod))
            reasserting = false
        } else {
            log.debug("Setting new link for session")
            session.setLink(producer.link(userObject: cfg.configuration.xorMethod))
        }
    }

    public func socket(_ socket: GenericSocket, didShutdownWithFailure failure: Bool) {
        log.info("Socket shutdown (failure: \(failure))")
        connectionState = failure ? "socket_failure" : "socket_shutdown"
        guard let session = session else {
            log.warning("Socket shutdown but no session exists")
            return
        }

        var shutdownError: Error?
        let didTimeoutNegotiation: Bool
        var upgradedSocket: GenericSocket?

        // look for error causing shutdown
        shutdownError = session.stopError
        if failure && (shutdownError == nil) {
            shutdownError = TunnelKitOpenVPNError.linkError
            log.error("Socket shutdown with link error")
        }
        if case .negotiationTimeout = shutdownError as? OpenVPNError {
            didTimeoutNegotiation = true
            log.warning("OpenVPN negotiation timed out")
        } else {
            didTimeoutNegotiation = false
        }

        // only try upgrade on network errors
        if shutdownError as? OpenVPNError == nil {
            upgradedSocket = socket.upgraded()
            if let upgradedSocket = upgradedSocket {
                log.debug("Socket has been upgraded to: \(type(of: upgradedSocket))")
            }
        }

        // clean up
        finishTunnelDisconnection(error: shutdownError)

        // fallback: UDP is connection-less, treat negotiation timeout as socket timeout
        if didTimeoutNegotiation {
            log.debug("Negotiation timeout, attempting to use next endpoint")
            guard tryNextEndpoint() else {
                // disposeTunnel
                log.error("No more endpoints available after negotiation timeout")
                return
            }
        }

        // reconnect?
        if shouldReconnect {
            log.info("Disconnection is recoverable, tunnel will reconnect in \(reconnectionDelay) milliseconds...")
            tunnelQueue.schedule(after: .milliseconds(reconnectionDelay)) {

                // give up if shouldReconnect cleared in the meantime
                guard self.shouldReconnect else {
                    log.warning("Reconnection cancelled: flag was cleared")
                    return
                }

                log.info("Reconnecting tunnel...")
                self.connectionState = "reconnecting"
                self.reasserting = true
                self.connectTunnel(upgradedSocket: upgradedSocket)
            }
            return
        }

        // shut down
        log.debug("No reconnection needed, disposing tunnel")
        disposeTunnel(error: shutdownError)
    }

    public func socketHasBetterPath(_ socket: GenericSocket) {
        log.info("Socket reports a better path is available")
        connectionState = "network_changed"
        logCurrentSSID()
        session?.reconnect(error: TunnelKitOpenVPNError.networkChanged)
    }
}

extension OpenVPNTunnelProvider: OpenVPNSessionDelegate {

    // MARK: OpenVPNSessionDelegate (tunnel queue)

    public func sessionDidStart(_ session: OpenVPNSession, remoteAddress: String, remoteProtocol: String?, options: OpenVPN.Configuration) {
        log.info("OpenVPN session did start successfully!")
        connectionState = "session_started"
        let connectionTime = Date().timeIntervalSince(connectionStartTime ?? Date())
        log.info("Connection established in \(String(format: "%.2f", connectionTime))s after \(connectionAttempts) attempts")
        log.info("\tRemote address: \(remoteAddress.maskedDescription)")
        if let proto = remoteProtocol {
            log.info("\tProtocol: \(proto)")
        }

        log.info("Local options:")
        cfg.configuration.print(isLocal: true)
        log.info("Remote options:")
        options.print(isLocal: false)

        log.debug("Saving server configuration to shared defaults")
        cfg._appexSetServerConfiguration(session.serverConfiguration() as? OpenVPN.Configuration)

        log.info("Bringing network up...")
        bringNetworkUp(remoteAddress: remoteAddress, localOptions: session.configuration, remoteOptions: options) { (error) in

            // FIXME: XPC queue
            self.reasserting = false

            if let error = error {
                log.error("Failed to configure tunnel: \(error)")
                self.connectionState = "network_configuration_failed"
                self.pendingStartHandler?(error)
                self.pendingStartHandler = nil
                return
            }

            log.info("Tunnel interface is now UP")

            log.debug("Setting tunnel interface")
            session.setTunnel(tunnel: NETunnelInterface(impl: self.packetFlow))

            log.info("OpenVPN connection established successfully")
            self.connectionState = "connected"
            self.pendingStartHandler?(nil)
            self.pendingStartHandler = nil
        }

        log.debug("Enabling data counting")
        isCountingData = true
        refreshDataCount()
    }

    public func sessionDidStop(_: OpenVPNSession, withError error: Error?, shouldReconnect: Bool) {
        log.info("OpenVPN session did stop")
        connectionState = "session_stopped"
        if let error = error {
            log.error("Session stopped with error: \(error)")
        }
        log.debug("Should reconnect: \(shouldReconnect)")
        
        log.debug("Clearing server configuration")
        cfg._appexSetServerConfiguration(nil)
        
        if let session = session {
            log.debug("Cleaning up session")
            session.cleanup()
        }
        session = nil

        log.debug("Disabling data counting")
        isCountingData = false
        refreshDataCount()

        self.shouldReconnect = shouldReconnect
        
        if let socket = socket {
            log.debug("Shutting down socket")
            socket.shutdown()
        } else {
            log.warning("No socket to shut down")
        }
    }

    private func bringNetworkUp(remoteAddress: String, localOptions: OpenVPN.Configuration, 
                          remoteOptions: OpenVPN.Configuration, completionHandler: @escaping (Error?) -> Void) {
        log.info("Building network settings...")
        let newSettings = NetworkSettingsBuilder(remoteAddress: remoteAddress, 
                                               localOptions: localOptions, 
                                               remoteOptions: remoteOptions)
        
    
        guard !newSettings.isGateway || newSettings.hasGateway else {
            log.error("Gateway unavailable! isGateway: \(newSettings.isGateway), hasGateway: \(newSettings.hasGateway)")
            connectionState = "gateway_unavailable"
            session?.shutdown(error: TunnelKitOpenVPNError.gatewayUnattainable)
            return
        }
        
        log.info("Applying tunnel network settings...")
        let settings = newSettings.build()
        setTunnelNetworkSettings(settings, completionHandler: { error in
            if let error = error {
                log.error("Failed to set tunnel network settings: \(error)")
                self.connectionState = "network_settings_failed"
            } else {
                log.info("Tunnel network settings applied successfully")
                self.connectionState = "network_configured"
            }
            completionHandler(error)
        })
    }
}

extension OpenVPNTunnelProvider {
    private func tryNextEndpoint() -> Bool {
        let hasNext = strategy.tryNextEndpoint()
        if hasNext {
            log.info("Moving to next endpoint in connection strategy")
        } else {
            log.warning("No more endpoints available in connection strategy")
        }
        guard hasNext else {
            connectionState = "no_more_endpoints"
            disposeTunnel(error: TunnelKitOpenVPNError.exhaustedEndpoints)
            return false
        }
        return true
    }

    // MARK: Logging

    private static var loggingInitialized = false

    private func configureLogging() {
        guard !Self.loggingInitialized else { 
            log.debug("Logging already initialized")
            return 
        }
        
        Self.loggingInitialized = true
        log.info("Configuring logging...")
        
        let logLevel: SwiftyBeaver.Level = (cfg.shouldDebug ? debugLogLevel : .info)
        let logFormat = cfg.debugLogFormat ?? "$Dyyyy-MM-dd HH:mm:ss.SSS$d $L $N.$F:$l - $M"

        if cfg.shouldDebug {
            let console = ConsoleDestination()
            console.useNSLog = true
            console.minLevel = logLevel
            console.format = logFormat
            log.addDestination(console)
            log.debug("Added console log destination with level: \(logLevel)")
        }

        if let logURL = cfg._appexDebugLogURL {
            log.info("Log file path: \(logURL.path)")
            let file = FileDestination(logFileURL: logURL)
            file.minLevel = logLevel
            file.format = logFormat
            file.logFileMaxSize = maxLogSize
            log.addDestination(file)
            log.debug("Added file log destination with level: \(logLevel), max size: \(maxLogSize)")
        } else {
            log.warning("No log file URL available")
        }

        // store path for clients
        cfg._appexSetDebugLogPath()
        log.info("Logging configured successfully")
    }

    private func flushLog() {
        log.debug("Flushing log...")

        // XXX: should enforce SwiftyBeaver flush?
//        if let url = cfg.urlForDebugLog {
//            memoryLog.flush(to: url)
//        }
    }

    private func logCurrentSSID() {
        log.debug("Checking current SSID...")
        InterfaceObserver.fetchCurrentSSID {
            if let ssid = $0 {
                log.debug("Current SSID: '\(ssid.maskedDescription)'")
                self.currentSSID = ssid
            } else {
                log.debug("Current SSID: none (disconnected from WiFi)")
                self.currentSSID = nil
            }
        }
    }

//    private func anyPointer(_ object: Any?) -> UnsafeMutableRawPointer {
//        let anyObject = object as AnyObject
//        return Unmanaged<AnyObject>.passUnretained(anyObject).toOpaque()
//    }
}

// MARK: Errors

private extension OpenVPNTunnelProvider {
    enum ConfigurationError: Error {

        /// A field in the `OpenVPNProvider.Configuration` provided is incorrect or incomplete.
        case parameter(name: String)

        /// Credentials are missing or inaccessible.
        case credentials(details: String)

        /// The pseudo-random number generator could not be initialized.
        case prngInitialization

        /// The TLS certificate could not be serialized.
        case certificateSerialization
    }

    func setErrorStatus(with error: Error) {
        log.error("Setting error status: \(error)")
        cfg._appexSetLastError(unifiedError(from: error))
    }

    func unifiedError(from error: Error) -> TunnelKitOpenVPNError {
        let openvpnError = openVPNError(from: error)
        log.debug("Mapped error \(error) to OpenVPN error: \(openvpnError?.rawValue ?? "nil, using linkError fallback")")
        // XXX: error handling is limited by lastError serialization
        // requirement, cannot return a generic Error here
//        openVPNError(from: error) ?? error
        return openvpnError ?? .linkError
    }

    func openVPNError(from error: Error) -> TunnelKitOpenVPNError? {
        if let neError = error as? NEVPNError {
            // Map system errors to existing cases
            let mappedError: TunnelKitOpenVPNError
            switch neError.code {
            case .connectionFailed: 
                mappedError = .linkError
            case .configurationInvalid: 
                mappedError = .tlsInitialization
            case .configurationDisabled: 
                mappedError = .authentication
            default: 
                mappedError = .unexpectedReply
            }
            log.debug("Mapped NEVPNError \(neError.code) to \(mappedError.rawValue)")
            return mappedError
        }
        if let specificError = error.asNativeOpenVPNError ?? error as? OpenVPNError {
            let mappedError: TunnelKitOpenVPNError
            switch specificError {
            case .negotiationTimeout, .pingTimeout, .staleSession:
                mappedError = .timeout

            case .badCredentials:
                mappedError = .authentication

            case .serverCompression:
                mappedError = .serverCompression

            case .failedLinkWrite:
                mappedError = .linkError

            case .noRouting:
                mappedError = .routing

            case .serverShutdown:
                mappedError = .serverShutdown

            case .native(let code):
                switch code {
                case .cryptoRandomGenerator, .cryptoAlgorithm:
                    mappedError = .encryptionInitialization

                case .cryptoEncryption, .cryptoHMAC:
                    mappedError = .encryptionData

                case .tlscaRead, .tlscaUse, .tlscaPeerVerification,
                        .tlsClientCertificateRead, .tlsClientCertificateUse,
                        .tlsClientKeyRead, .tlsClientKeyUse:
                    mappedError = .tlsInitialization

                case .tlsServerCertificate, .tlsServerEKU, .tlsServerHost:
                    mappedError = .tlsServerVerification

                case .tlsHandshake:
                    mappedError = .tlsHandshake

                case .dataPathOverflow, .dataPathPeerIdMismatch:
                    mappedError = .unexpectedReply

                case .dataPathCompression:
                    mappedError = .serverCompression

                default:
                    mappedError = .unexpectedReply
                }

            default:
                mappedError = .unexpectedReply
            }
            log.debug("Mapped OpenVPNError \(specificError) to \(mappedError.rawValue)")
            return mappedError
        }
        return nil
    }
}

// MARK: Hacks

private extension NEPacketTunnelProvider {
    func forceExitOnMac() {
        #if os(macOS)
        log.info("Force exiting on macOS")
        exit(0)
        #endif
    }
}
