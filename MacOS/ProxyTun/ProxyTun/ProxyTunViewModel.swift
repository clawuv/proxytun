import Foundation
import NetworkExtension
import SystemExtensions
import Combine

class ProxyTunViewModel: NSObject, ObservableObject {
    @Published var connections: [ConnectionLog] = []
    @Published var activityLogs: [ActivityLog] = []
    @Published var isProxyActive = false
    @Published var isTrafficLoggingEnabled = true
    
    var tunnelSession: NETunnelProviderSession?
    private var logTimer: Timer?
    private(set) var proxyConfig: ProxyConfig?
    private var statusObserver: NSObjectProtocol?
    private var pendingStartAfterActivation = false
    private var isActivationRequestInFlight = false
    
    private let maxLogEntries = 1000
    // trim to 80% when limit hit to avoid trimming on each entry
    private let trimToEntries = 800
    private let logPollingInterval = 1.0
    private var extensionIdentifier: String {
        if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
            return "\(bundleIdentifier).extension"
        }
        return "com.proxytun.ProxyTun.extension"
    }
    // reuse formatter
    // saves memory about 2% and speed up the ui
    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    // removed uuid and use int - memory usage and speed improved due to size
    private var connectionIdCounter: Int = 0
    private var activityIdCounter: Int = 0
    
    struct ProxyConfig {
        let type: String
        let host: String
        let port: Int
        let username: String?
        let password: String?
    }
    
    struct ConnectionLog: Identifiable {
        let id: Int
        let timestamp: String
        let connectionProtocol: String
        let process: String
        let destination: String
        let port: String
        let proxy: String
    }
    
    struct ActivityLog: Identifiable {
        let id: Int
        let timestamp: String
        let level: String
        let message: String
    }
    
    override init() {
        super.init()
        loadTrafficLoggingSetting()
        loadProxyConfig()
        observeTunnelStatusChanges()
        refreshProxyStatus()
    }
    
    private func loadTrafficLoggingSetting() {
        isTrafficLoggingEnabled = UserDefaults.standard.object(forKey: "trafficLoggingEnabled") as? Bool ?? true
    }
    
    func toggleTrafficLogging() {
        isTrafficLoggingEnabled.toggle()
        UserDefaults.standard.set(isTrafficLoggingEnabled, forKey: "trafficLoggingEnabled")
        sendTrafficLoggingToExtension(isTrafficLoggingEnabled)
        
        if isTrafficLoggingEnabled {
            startLogPollingTimer()
        } else {
            logTimer?.invalidate()
            logTimer = nil
        }
    }
    
    private func sendTrafficLoggingToExtension(_ enabled: Bool) {
        guard let session = tunnelSession else { return }
        
        let message: [String: Any] = [
            "action": "setTrafficLogging",
            "enabled": enabled
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        
        try? session.sendProviderMessage(data) { _ in }
    }
    
    private func loadProxyConfig() {
        if let type = UserDefaults.standard.string(forKey: "proxyType"),
           let host = UserDefaults.standard.string(forKey: "proxyHost"),
           let port = UserDefaults.standard.object(forKey: "proxyPort") as? Int {
            let username = UserDefaults.standard.string(forKey: "proxyUsername")
            let password = UserDefaults.standard.string(forKey: "proxyPassword")
            
            proxyConfig = ProxyConfig(
                type: type,
                host: host,
                port: port,
                username: username,
                password: password
            )
        }
    }
    
    private func saveProxyConfig(_ config: ProxyConfig) {
        UserDefaults.standard.set(config.type, forKey: "proxyType")
        UserDefaults.standard.set(config.host, forKey: "proxyHost")
        UserDefaults.standard.set(config.port, forKey: "proxyPort")
        
        if let username = config.username {
            UserDefaults.standard.set(username, forKey: "proxyUsername")
        } else {
            UserDefaults.standard.removeObject(forKey: "proxyUsername")
        }
        
        if let password = config.password {
            UserDefaults.standard.set(password, forKey: "proxyPassword")
        } else {
            UserDefaults.standard.removeObject(forKey: "proxyPassword")
        }
    }
    
    private func refreshProxyStatus() {
        NETransparentProxyManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.addLog("ERROR", "Failed to refresh tunnel status: \(error.localizedDescription)")
                }
                return
            }

            guard let existing = managers?.first,
                  let session = existing.connection as? NETunnelProviderSession else {
                DispatchQueue.main.async {
                    self.handleTunnelStatusChange(.disconnected, session: nil)
                }
                return
            }

            DispatchQueue.main.async {
                self.handleTunnelStatusChange(session.status, session: session)
            }
        }
    }
    
    private func observeTunnelStatusChanges() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let session = notification.object as? NETunnelProviderSession else { return }

            if let currentSession = self.tunnelSession, currentSession != session {
                return
            }

            self.handleTunnelStatusChange(session.status, session: session)
        }
    }

    private func handleTunnelStatusChange(_ status: NEVPNStatus, session: NETunnelProviderSession?) {
        switch status {
        case .connected, .connecting, .reasserting:
            if let session {
                tunnelSession = session
                setupLogPolling(session: session)
            }
            isProxyActive = true
        case .disconnecting:
            isProxyActive = false
        case .disconnected, .invalid:
            isProxyActive = false
            tunnelSession = nil
            logTimer?.invalidate()
            logTimer = nil
        @unknown default:
            isProxyActive = false
        }
    }

    private func submitExtensionActivationRequest() {
        guard !isActivationRequestInFlight else { return }

        isActivationRequestInFlight = true
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    func startProxy() {
        pendingStartAfterActivation = true
        NETransparentProxyManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            
            if let error = error {
                self.addLog("ERROR", "Failed to load managers: \(error.localizedDescription)")
                return
            }
            
            let manager = managers?.first ?? NETransparentProxyManager()
            manager.localizedDescription = "ProxyTun Transparent Proxy"
            manager.isEnabled = true
            
            let providerProtocol = NETunnelProviderProtocol()
            providerProtocol.providerBundleIdentifier = self.extensionIdentifier
            providerProtocol.serverAddress = "ProxyTun"
            manager.protocolConfiguration = providerProtocol

            self.addLog("INFO", "Preparing transparent proxy with extension: \(self.extensionIdentifier)")
            
            manager.saveToPreferences { saveError in
                if let saveError = saveError {
                    self.addLog("ERROR", "Failed to save preferences: \(saveError.localizedDescription)")
                    self.submitExtensionActivationRequest()
                    return
                }
                
                self.addLog("INFO", "Configuration saved")
                self.ensureManagerEnabledAndStart(manager: manager)
            }
        }
    }
    
    private func ensureManagerEnabledAndStart(manager: NETransparentProxyManager) {
        manager.loadFromPreferences { [weak self] loadError in
            guard let self = self else { return }
            
            if let loadError = loadError {
                self.addLog("ERROR", "Failed to reload preferences: \(loadError.localizedDescription)")
                return
            }

            if !manager.isEnabled {
                manager.isEnabled = true
                manager.saveToPreferences { [weak self] saveError in
                    guard let self = self else { return }

                    if let saveError {
                        self.addLog("ERROR", "Failed to enable system proxy configuration: \(saveError.localizedDescription)")
                        return
                    }

                    self.addLog("INFO", "System proxy configuration re-enabled")
                    manager.loadFromPreferences { [weak self] secondLoadError in
                        guard let self = self else { return }

                        if let secondLoadError {
                            self.addLog("ERROR", "Failed to confirm enabled proxy configuration: \(secondLoadError.localizedDescription)")
                            return
                        }

                        self.startTunnel(using: manager)
                    }
                }
                return
            }

            self.startTunnel(using: manager)
        }
    }

    private func startTunnel(using manager: NETransparentProxyManager) {
        DispatchQueue.main.async {
            self.tunnelSession = manager.connection as? NETunnelProviderSession
        }
            
        do {
            guard let session = manager.connection as? NETunnelProviderSession else {
                addLog("ERROR", "Unable to access tunnel session")
                return
            }

            try session.startTunnel()
            
            DispatchQueue.main.async {
                self.isProxyActive = true
                self.addLog("INFO", "Proxy tunnel started")
            }
            
            // Wait a moment for tunnel to be ready, then configure
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                self.setupLogPolling(session: session)
                
                if let config = self.proxyConfig {
                    self.sendProxyConfigToExtension(config, session: session)
                }
                
                RuleManager.loadRulesFromUserDefaults(session: session) { success, count in
                    if success && count > 0 {
                        self.addLog("INFO", "Loaded \(count) rule(s) from local storage")
                    }
                }
            }
        } catch {
            addLog("ERROR", "Failed to start tunnel: \(error.localizedDescription)")
            refreshProxyStatus()
            submitExtensionActivationRequest()
        }
    }
    
    func stopProxy() {
        isProxyActive = false
        pendingStartAfterActivation = false

        guard let session = tunnelSession else {
            logTimer?.invalidate()
            logTimer = nil
            refreshProxyStatus()
            return
        }
        
        // Clear all data from extension memory before stopping
        clearExtensionMemory(session: session) { [weak self] in
            guard let self = self else { return }
            
            NETransparentProxyManager.loadAllFromPreferences { managers, error in
                if let manager = managers?.first {
                    (manager.connection as? NETunnelProviderSession)?.stopTunnel()
                    self.isProxyActive = false
                    self.logTimer?.invalidate()
                    self.logTimer = nil
                    self.tunnelSession = nil
                    self.addLog("INFO", "Proxy stopped and extension memory cleared")
                    self.refreshProxyStatus()
                }
            }
        }
    }
    
    private func clearExtensionMemory(session: NETunnelProviderSession, completion: @escaping () -> Void) {
        // clear rules auto fix the #51 - and proxy rules become inactive after It closes
        RuleManager.clearRules(session: session) { success, message in
            //clear proxy config as well keep meory usage low for extesion 
            let clearConfigMessage: [String: Any] = [
                "action": "clearConfig"
            ]
            
            guard let data = try? JSONSerialization.data(withJSONObject: clearConfigMessage) else {
                completion()
                return
            }
            
            try? session.sendProviderMessage(data) { _ in
                completion()
            }
        }
    }
    
    private func setupLogPolling(session: NETunnelProviderSession) {
        tunnelSession = session
        
        sendTrafficLoggingToExtension(isTrafficLoggingEnabled)
        
        if isTrafficLoggingEnabled {
            startLogPollingTimer()
        }
    }
    
    private func startLogPollingTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.logTimer?.invalidate()
            self.logTimer = Timer.scheduledTimer(
                withTimeInterval: self.logPollingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.pollLogs()
            }
        }
    }
    
    private func pollLogs() {
        guard let session = tunnelSession else { return }
        
        let message = ["action": "getLogs"]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        
        try? session.sendProviderMessage(data) { [weak self] response in
            guard let self = self,
                  let responseData = response else {
                return
            }
            
            if let logs = try? JSONSerialization.jsonObject(with: responseData) as? [[String: String]] {
                DispatchQueue.main.async {
                    for log in logs {
                        if log["type"] == "connection" {
                            self.handleConnectionLog(log)
                        } else {
                            self.handleActivityLog(log)
                        }
                    }
                }
            }
        }
    }
    
    private func handleConnectionLog(_ log: [String: String]) {
        guard isTrafficLoggingEnabled else { return }
        
        guard let proto = log["protocol"],
              let process = log["process"],
              let dest = log["destination"],
              let port = log["port"],
              let proxy = log["proxy"] else {
            return
        }
        
        connectionIdCounter &+= 1
        let connectionLog = ConnectionLog(
            id: connectionIdCounter,
            timestamp: getCurrentTimestamp(),
            connectionProtocol: proto,
            process: process,
            destination: dest,
            port: port,
            proxy: proxy
        )
        connections.append(connectionLog)
        
        // Trim in bulk to avoid O(n) shift on every entry at the limit
        if connections.count > maxLogEntries {
            connections.removeFirst(connections.count - trimToEntries)
        }
    }
    
    private func handleActivityLog(_ log: [String: String]) {
        guard let timestamp = log["timestamp"],
              let level = log["level"],
              let message = log["message"] else {
            return
        }
        
        activityIdCounter &+= 1
        let activityLog = ActivityLog(
            id: activityIdCounter,
            timestamp: timestamp,
            level: level,
            message: message
        )
        activityLogs.append(activityLog)
        
        if activityLogs.count > maxLogEntries {
            activityLogs.removeFirst(activityLogs.count - trimToEntries)
        }
    }
    
    func setProxyConfig(_ config: ProxyConfig) {
        proxyConfig = config
        saveProxyConfig(config)
        
        guard let session = tunnelSession else {
            addLog("ERROR", "Extension not connected")
            return
        }
        
        sendProxyConfigToExtension(config, session: session)
    }
    
    private func sendProxyConfigToExtension(_ config: ProxyConfig, session: NETunnelProviderSession) {
        var message: [String: Any] = [
            "action": "setProxyConfig",
            "proxyType": config.type,
            "proxyHost": config.host,
            "proxyPort": config.port
        ]
        
        if let username = config.username {
            message["proxyUsername"] = username
        }
        if let password = config.password {
            message["proxyPassword"] = password
        }
        
        guard let data = try? JSONSerialization.data(withJSONObject: message) else {
            addLog("ERROR", "Failed to encode proxy config")
            return
        }
        
        try? session.sendProviderMessage(data) { [weak self] response in
            if let responseData = response,
               let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let status = json["status"] as? String, status == "ok" {
                DispatchQueue.main.async {
                    self?.addLog("INFO", "Proxy configured: \(config.type)://\(config.host):\(config.port)")
                }
            }
        }
    }
    
    func clearConnections() {
        connections.removeAll()
    }
    
    func clearActivityLogs() {
        activityLogs.removeAll()
    }
    
    func addLog(_ level: String, _ message: String) {
        activityIdCounter &+= 1
        let log = ActivityLog(
            id: activityIdCounter,
            timestamp: getCurrentTimestamp(),
            level: level,
            message: message
        )
        activityLogs.append(log)
        
        if activityLogs.count > maxLogEntries {
            activityLogs.removeFirst(activityLogs.count - trimToEntries)
        }
    }
    
    private func getCurrentTimestamp() -> String {
        return timestampFormatter.string(from: Date())
    }
    
    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        logTimer?.invalidate()
        stopProxy()
    }
}

extension ProxyTunViewModel: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        DispatchQueue.main.async {
            self.isActivationRequestInFlight = false
            self.addLog("INFO", "Extension installed successfully")
            if self.pendingStartAfterActivation {
                self.pendingStartAfterActivation = false
                self.startProxy()
            } else {
                self.refreshProxyStatus()
            }
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isActivationRequestInFlight = false
            self.pendingStartAfterActivation = false
            self.addLog("ERROR", "Extension failed: \(error.localizedDescription)")
        }
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        DispatchQueue.main.async {
            self.addLog("INFO", "Extension needs user approval in System Settings")
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        print("Replacing existing extension")
        return .replace
    }
}
