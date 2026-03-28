import SwiftUI

@main
struct ProxyTunGUIApp: App {
    @StateObject private var viewModel = ProxyTunViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .background(MainWindowConfigurator())
                .onAppear {
                    AppDelegate.viewModel = viewModel
                    checkForUpdatesOnStartup()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            
            CommandMenu("Proxy") {
                Button("Proxy Settings...") {
                    openProxySettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Button("Proxy Rules...") {
                    openProxyRulesWindow()
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Toggle("Enable Traffic Logging", isOn: Binding(
                    get: { viewModel.isTrafficLoggingEnabled },
                    set: { _ in viewModel.toggleTrafficLogging() }
                ))
            }
            
            CommandGroup(replacing: .help) {
                Button("Check for Updates...") {
                    openUpdateCheckWindow()
                }
                
                Divider()
                
                Button("About ProxyTun") {
                    openAboutWindow()
                }
            }
        }
        
        Window("Proxy Settings", id: "proxy-settings") {
            ProxySettingsView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        Window("Proxy Rules", id: "proxy-rules") {
            ProxyRulesView(viewModel: viewModel)
        }
        .defaultPosition(.center)
        
        Window("About ProxyTun", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        Window("Check for Updates", id: "update-check") {
            UpdateCheckView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
    
    private func openProxySettingsWindow() {
        NSApp.sendAction(#selector(AppDelegate.openProxySettings), to: nil, from: nil)
    }
    
    private func openProxyRulesWindow() {
        NSApp.sendAction(#selector(AppDelegate.openProxyRules), to: nil, from: nil)
    }
    
    private func openAboutWindow() {
        NSApp.sendAction(#selector(AppDelegate.openAbout), to: nil, from: nil)
    }
    
    private func openUpdateCheckWindow() {
        NSApp.sendAction(#selector(AppDelegate.openUpdateCheck), to: nil, from: nil)
    }
    
    private func checkForUpdatesOnStartup() {
        let shouldCheck = UserDefaults.standard.object(forKey: "checkForUpdatesOnStartup") as? Bool ?? true
        
        if shouldCheck {
            Task {
                let updateService = UpdateService()
                let versionInfo = await updateService.checkForUpdates()
                
                await MainActor.run {
                    if let error = versionInfo.error {
                        viewModel.addLog("ERROR", "Update check failed: \(error)")
                    } else if versionInfo.isUpdateAvailable {
                        viewModel.addLog("INFO", "Update available: \(versionInfo.latestVersion) (\(versionInfo.releaseName))")
                        AppDelegate.pendingUpdateInfo = versionInfo
                        NSApp.sendAction(#selector(AppDelegate.showUpdateNotification(_:)), to: nil, from: nil)
                    } else {
                        viewModel.addLog("INFO", "Update check complete: already on the latest version")
                    }
                }
            }
        }
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            configureWindow(for: view)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unifiedCompact
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var viewModel: ProxyTunViewModel?
    static var pendingUpdateInfo: VersionInfo?
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Clear extension memory before app quits
        AppDelegate.viewModel?.stopProxy()
        
        // Give time for memory clearing to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        
        return .terminateLater
    }
    
    @objc func openProxySettings() {
        openWindow(title: "Proxy Settings", size: NSSize(width: 600, height: 500)) {
            ProxySettingsView(viewModel: AppDelegate.viewModel!)
        }
    }
    
    @objc func openProxyRules() {
        openWindow(title: "Proxy Rules", size: NSSize(width: 1200, height: 600), resizable: true) {
            ProxyRulesView(viewModel: AppDelegate.viewModel!)
        }
    }
    
    @objc func openAbout() {
        openWindow(title: "About ProxyTun", size: NSSize(width: 400, height: 350)) {
            AboutView()
        }
    }
    
    @objc func openUpdateCheck() {
        openWindow(title: "Check for Updates", size: NSSize(width: 460, height: 430)) {
            UpdateCheckView(logger: AppDelegate.viewModel?.addLog)
        }
    }
    
    @objc func showUpdateNotification(_ sender: Any?) {
        if let versionInfo = AppDelegate.pendingUpdateInfo {
            openWindow(title: "Update Available", size: NSSize(width: 460, height: 430)) {
                UpdateNotificationView(versionInfo: versionInfo, logger: AppDelegate.viewModel?.addLog)
            }
            AppDelegate.pendingUpdateInfo = nil
        }
    }
    
    private func openWindow<Content: View>(
        title: String,
        size: NSSize,
        resizable: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        if let window = NSApplication.shared.windows.first(where: { $0.title == title }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let controller = NSHostingController(rootView: content())
            let window = NSWindow(contentViewController: controller)
            window.title = title
            window.setContentSize(size)
            window.styleMask = resizable ? [.titled, .closable, .resizable] : [.titled, .closable]
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
}
