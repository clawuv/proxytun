import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ProxyTunViewModel
    @AppStorage("checkForUpdatesOnStartup") private var checkForUpdatesOnStartup = true
    @AppStorage("preferredLanguage") private var preferredLanguage = AppLanguage.english.rawValue
    @State private var selectedSection: SidebarSection = .overview
    @State private var logSearchText = ""
    @State private var rulesActionMessage: String?
    @State private var rulesActionIsError = false
    @State private var settingsSaveMessage: String?
    @State private var settingsSaveIsError = false
    @State private var preferencesMessage: String?
    @State private var rulesMessageDismissWorkItem: DispatchWorkItem?
    @State private var settingsMessageDismissWorkItem: DispatchWorkItem?
    @State private var preferencesMessageDismissWorkItem: DispatchWorkItem?
    @State private var showAddRule = false
    @StateObject private var settingsFormModel = ProxySettingsFormModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainContent
        }
        .frame(minWidth: 1024, minHeight: 768)
        .background(AppColors.canvas.ignoresSafeArea())
        .sheet(isPresented: $showAddRule) {
            RuleEditorView(viewModel: viewModel) {
                showRulesMessage(localized("Rule saved successfully.", "规则保存成功。"), isError: false)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("PROXYTUN")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
            }
            .padding(.top, 4)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 20) {
                sidebarGroup(
                    title: localized("Workspace", "工作区"),
                    sections: [.overview, .proxies, .rules]
                )

                sidebarGroup(
                    title: localized("Utilities", "工具"),
                    sections: [.connections, .settings]
                )
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(proxyStatusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(proxyStatusDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(width: 220)
        .background(AppColors.sidebar)
    }

    private func sidebarRow(for section: SidebarSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            selectedSection = section
            handleSidebarSelection(section)
        } label: {
            HStack(spacing: 10) {
                Label(localizedSectionTitle(for: section), systemImage: section.symbol)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? AppColors.primary : AppColors.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AppColors.primaryTint : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarGroup(title: String, sections: [SidebarSection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(sections) { section in
                sidebarRow(for: section)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedSection {
        case .overview:
            overviewContent
        case .connections:
            connectionsContent
        case .rules:
            rulesContent
        case .proxies:
            proxiesContent
        case .settings:
            settingsContent
        }
    }

    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader(
                    title: localized("Control Center", "控制中心"),
                    subtitle: localized("Route apps, inspect traffic, and keep proxy health visible at a glance.", "在一个界面里完成应用分流、流量观察和代理状态管理。")
                )

                statusBanner(
                    title: viewModel.isProxyActive ? localized("Tunnel online • \(viewModel.connections.count) active sockets", "隧道运行中 • \(viewModel.connections.count) 个活跃连接") : localized("Tunnel offline • configuration ready", "隧道未启动 • 配置已就绪"),
                    detail: viewModel.isProxyActive
                        ? localized("\(proxyStatusDetail). Logs are updating in real time.", "\(proxyStatusDetail)。日志正在实时更新。")
                        : localized("Choose a proxy profile, add your first rule, then start routing when you are ready.", "先选择代理、添加第一条规则，然后在准备好后启动路由。")
                )

                HStack(spacing: 18) {
                    stepCard(step: localized("Step 1", "第一步"), title: localized("Choose Proxy", "选择代理"), buttonTitle: localized("Go to Proxies", "去代理"), icon: "cable", tint: AppColors.primaryTint) {
                        selectedSection = .proxies
                    }
                    stepCard(step: localized("Step 2", "第二步"), title: localized("Add Rules", "添加规则"), buttonTitle: localized("Go to Rules", "去规则"), icon: "shield.plus", tint: AppColors.card) {
                        selectedSection = .rules
                    }
                    stepCard(step: localized("Step 3", "第三步"), title: localized("Start Routing", "开始运行"), buttonTitle: localized("View Connections", "看连接"), icon: "waveform.path.ecg", tint: AppColors.card) {
                        selectedSection = .connections
                    }
                }

                HStack(alignment: .top, spacing: 22) {
                    activityLogPanel(title: localized("Activity Log", "活动日志"), subtitle: localized("Recent rule hits, proxy changes, and connection updates.", "最近规则命中、代理切换和连接变化。"))
                    overviewSummaryColumn
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(AppColors.canvas)
    }

    private var connectionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader(
                    title: localized("Connections", "连接"),
                    subtitle: localized("Inspect live flows, trace destinations, and verify which rules are deciding traffic.", "查看实时连接、跟踪目标地址，并确认当前命中的规则。")
                )

                statusBanner(
                    title: localized("\(viewModel.connections.count) active sockets", "\(viewModel.connections.count) 个活跃连接"),
                    detail: viewModel.connections.isEmpty
                        ? localized("No active connections yet. Start the tunnel to inspect traffic.", "当前还没有活跃连接。启动隧道后即可查看流量。")
                        : localized("Connection activity updates in real time while the tunnel is running.", "隧道运行时，连接活动会实时更新。")
                )

                HStack(alignment: .top, spacing: 22) {
                    connectionTableCard
                    connectionsSummaryColumn
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(AppColors.canvas)
    }

    private var rulesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader(
                    title: localized("Rules Studio", "规则"),
                    subtitle: localized("Manage app routing policies, quick presets, and rule order without leaving the main window.", "在主窗口内管理应用分流策略、常用预设和规则。"),
                    primaryActionTitle: localized("Add Rule", "添加规则"),
                    primaryAction: {
                        showAddRule = true
                    },
                    secondaryActionTitle: localized("Import", "导入"),
                    secondaryAction: {
                        importRulesFromFile()
                    }
                )

                if let rulesActionMessage {
                    inlineFeedbackBanner(message: rulesActionMessage, isError: rulesActionIsError)
                }

                rulesListCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(AppColors.canvas)
    }

    private var proxiesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader(
                    title: localized("Proxy Settings", "代理"),
                    subtitle: localized("Add or update the proxy endpoint used by ProxyTun without leaving the main workspace.", "在主工作区内添加或修改 ProxyTun 使用的代理端点。")
                )

                if let settingsSaveMessage {
                    inlineFeedbackBanner(message: settingsSaveMessage, isError: settingsSaveIsError)
                }

                proxiesEditorCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(AppColors.canvas)
        .onAppear {
            settingsFormModel.load(from: viewModel.proxyConfig)
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader(
                    title: localized("Settings", "设置"),
                    subtitle: localized("Adjust application behavior, background defaults, and runtime preferences for ProxyTun.", "调整应用行为、默认选项和 ProxyTun 的运行偏好。")
                )

                statusBanner(
                    title: settingsStatusTitle,
                    detail: settingsStatusDetail
                )

                if let preferencesMessage {
                    inlineFeedbackBanner(message: preferencesMessage, isError: false)
                }

                settingsPreferencesCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(AppColors.canvas)
    }

    private func dashboardHeader(
        title: String,
        subtitle: String,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            HStack(spacing: 10) {
                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(SecondaryPillButtonStyle())
                } else {
                    Button(localized("Edit Rules", "编辑规则")) {
                        openProxyRulesWindow()
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                }

                if let primaryActionTitle, let primaryAction {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(PrimaryPillButtonStyle())
                } else {
                    Button(viewModel.isProxyActive ? localized("Stop Routing", "停止路由") : localized("Start Routing", "开始路由")) {
                        viewModel.isProxyActive ? viewModel.stopProxy() : viewModel.startProxy()
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                }
            }
        }
    }

    private func statusBanner(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: viewModel.isProxyActive ? "shield.checkered" : "bolt.horizontal.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.banner)
        )
    }

    private func stepCard(step: String, title: String, buttonTitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.primary)

            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer(minLength: 0)

            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(buttonTitle)
                }
            }
            .buttonStyle(PrimaryPillButtonStyle(compact: true))
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func activityLogPanel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.textSecondary)
                    TextField(localized("Search logs: app, host, protocol...", "搜索日志：应用、地址、协议..."), text: $logSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: 290)
                .background(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(AppColors.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }

            VStack(spacing: 0) {
                ForEach(filteredDashboardLogs) { entry in
                    dashboardLogRow(entry)

                    if entry.id != filteredDashboardLogs.last?.id {
                        Divider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardLogRow(_ entry: DashboardLogEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.message)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.badge)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.badgeColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var overviewSummaryColumn: some View {
        VStack(spacing: 16) {
            summaryCard(
                title: localized("Proxy Profile", "代理概况"),
                subtitle: localized("Current tunnel endpoint and policy defaults.", "当前隧道端点与默认策略。"),
                lines: [
                    localized("Primary: \(proxyStatusDetail)", "当前代理：\(proxyStatusDetail)"),
                    localized("DNS via proxy: \(viewModel.isProxyActive ? "Enabled" : "Ready")", "DNS 代理：\(viewModel.isProxyActive ? "已启用" : "已准备")"),
                    localized("Traffic logging: \(viewModel.isTrafficLoggingEnabled ? "Enabled" : "Disabled")", "流量日志：\(viewModel.isTrafficLoggingEnabled ? "已启用" : "已关闭")"),
                    localized("Default route: Direct unless matched", "默认路由：未命中规则则直连")
                ]
            )
        }
        .frame(width: 290)
    }

    private var connectionTableCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("Live Connections", "实时连接"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(localized("Recent application connections and routing decisions.", "最近的应用连接和路由决策。"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(localized("Filters", "筛选"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 12) {
                    filterField(title: localized("Search", "搜索"), value: localized("process, host, or pid...", "进程、主机或 pid..."), grows: true)
                    filterField(title: localized("Action", "动作"), value: localized("All actions", "全部动作"))
                    filterField(title: localized("Protocol", "协议"), value: "TCP + UDP")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )

            VStack(spacing: 0) {
                ForEach(viewModel.connections.prefix(6)) { connection in
                    connectionRow(connection)

                    if connection.id != viewModel.connections.prefix(6).last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterField(title: String, value: String, grows: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(grows ? AppColors.textSecondary : AppColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: grows ? .infinity : nil, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(AppColors.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
        .frame(maxWidth: grows ? .infinity : 180, alignment: .leading)
    }

    private func connectionRow(_ connection: ProxyTunViewModel.ConnectionLog) -> some View {
        HStack(spacing: 16) {
            Group {
                Text(connection.process).frame(width: 130, alignment: .leading)
                Text(connection.connectionProtocol).frame(width: 62, alignment: .leading)
                Text("\(connection.destination):\(connection.port)").frame(maxWidth: .infinity, alignment: .leading)
                Text(connection.proxy).frame(width: 70, alignment: .leading)
                Text(connection.timestamp).frame(width: 72, alignment: .trailing)
            }
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var connectionsSummaryColumn: some View {
        VStack(spacing: 16) {
            summaryCard(
                title: localized("Selected Flow", "选中连接"),
                subtitle: selectedConnectionTitle,
                lines: selectedConnectionLines
            )

            warningCard(
                title: localized("Blocked Steam flow requires review", "Steam 拦截连接需要确认"),
                detail: localized("A denylist match is preventing content.steampowered.com from leaving the tunnel. Confirm whether this is expected.", "某条拦截规则阻止了 content.steampowered.com 离开隧道，请确认这是否符合预期。")
            )
        }
        .frame(width: 290)
    }

    private var rulesListCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("Common Presets", "常用预设"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 12) {
                    ForEach(RulePreset.defaults) { preset in
                        RulePresetCard(preset: preset) {
                            applyPreset(preset)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var proxiesEditorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Proxy Endpoint", "代理端点"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(localized("Create or edit the SOCKS5 / HTTP endpoint used for traffic routing.", "创建或编辑用于流量转发的 SOCKS5 / HTTP 代理端点。"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Text(viewModel.isProxyActive ? localized("Running", "运行中") : localized("Ready", "就绪"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(viewModel.isProxyActive ? AppColors.primary : AppColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(viewModel.isProxyActive ? AppColors.primaryTint : AppColors.card)
                    )
            }
            
            ProxySettingsFieldsView(
                formModel: settingsFormModel,
                style: .dashboard,
                showsRequiredFootnote: false
            )

            HStack(spacing: 10) {
                Button(localized("Reload", "重新加载")) {
                    settingsFormModel.load(from: viewModel.proxyConfig)
                    settingsSaveMessage = nil
                }
                .buttonStyle(SecondaryPillButtonStyle())

                Button(localized("Save Proxy", "保存代理")) {
                    saveInlineSettings()
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(settingsFormModel.isSaveDisabled)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var settingsPreferencesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("Application Preferences", "应用偏好"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(localized("Control how ProxyTun behaves on this Mac without changing the active proxy endpoint.", "在不修改当前代理端点的情况下，调整 ProxyTun 在本机上的行为。"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: 0) {
                settingsToggleRow(
                    title: localized("Traffic Logging", "流量日志"),
                    detail: localized("Collect live tunnel events and connection activity for the dashboard.", "为仪表盘采集隧道事件和连接活动。"),
                    isOn: Binding(
                        get: { viewModel.isTrafficLoggingEnabled },
                        set: { _ in
                            viewModel.toggleTrafficLogging()
                            showPreferencesMessage(
                                viewModel.isTrafficLoggingEnabled
                                    ? localized("Traffic logging enabled.", "流量日志已开启。")
                                    : localized("Traffic logging disabled.", "流量日志已关闭。")
                            )
                        }
                    )
                )

                Divider()

                settingsLanguageRow

                Divider()

                settingsToggleRow(
                    title: localized("Check for Updates on Launch", "启动时检查更新"),
                    detail: localized("Automatically look for new ProxyTun releases when the app opens.", "在应用启动时自动检查 ProxyTun 新版本。"),
                    isOn: Binding(
                        get: { checkForUpdatesOnStartup },
                        set: { newValue in
                            checkForUpdatesOnStartup = newValue
                            showPreferencesMessage(
                                newValue
                                    ? localized("Automatic update checks enabled.", "自动检查更新已开启。")
                                    : localized("Automatic update checks disabled.", "自动检查更新已关闭。")
                            )
                        }
                    )
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
            )

            VStack(alignment: .leading, spacing: 14) {
                Text(localized("Runtime Snapshot", "运行状态"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                settingsInfoRow(title: localized("Tunnel Status", "隧道状态"), value: viewModel.isProxyActive ? localized("Running", "运行中") : localized("Idle", "空闲"))
                settingsInfoRow(title: localized("Saved Rules", "已保存规则"), value: localized("\(storedRules.count) total • \(enabledRuleCount) enabled", "\(storedRules.count) 条 • 已启用 \(enabledRuleCount) 条"))
                settingsInfoRow(title: localized("Configured Endpoint", "当前端点"), value: proxyStatusDetail)
                settingsInfoRow(title: localized("Last Activity", "最近活动"), value: lastActivityTimestamp)
            }

            HStack(spacing: 10) {
                Button(localized("Check for Updates", "检查更新")) {
                    NSApp.sendAction(#selector(AppDelegate.openUpdateCheck), to: nil, from: nil)
                }
                .buttonStyle(SecondaryPillButtonStyle())

                Button(localized("Open Proxy Window", "打开代理窗口")) {
                    openProxySettingsWindow()
                }
                .buttonStyle(PrimaryPillButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func settingsToggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var settingsLanguageRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("Language", "语言"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(localized("Switch the main workspace between English and Simplified Chinese.", "在英文和简体中文之间切换主工作区界面。"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Picker("", selection: $preferredLanguage) {
                Text("English").tag(AppLanguage.english.rawValue)
                Text("简体中文").tag(AppLanguage.chinese.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: preferredLanguage) { newValue in
                showPreferencesMessage(
                    newValue == AppLanguage.chinese.rawValue
                        ? "界面语言已切换为简体中文。"
                        : "Interface language switched to English."
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func settingsInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func summaryCard(title: String, subtitle: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func inlineFeedbackBanner(message: String, isError: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.red : AppColors.primary)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isError ? AppColors.errorTint : AppColors.primaryTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.18) : AppColors.border, lineWidth: 1)
        )
    }

    private func actionCard(title: String, detail: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

            Button(buttonTitle, action: action)
                .buttonStyle(PrimaryPillButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func warningCard(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.69, green: 0.41, blue: 0.12))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.85))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.warningTint)
        )
    }

    private func handleSidebarSelection(_ section: SidebarSection) {
        _ = section
    }

    private func applyPreset(_ preset: RulePreset) {
        RulePresetManager.applyPreset(preset, viewModel: viewModel) { result in
            showRulesMessage(result.message, isError: result.isError)
        }
    }

    private func importRulesFromFile() {
        guard viewModel.tunnelSession != nil else {
            showRulesMessage(localized("Start the tunnel before importing rules.", "请先启动隧道，再导入规则。"), isError: true)
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.title = "Import Proxy Rules"
        openPanel.message = "Choose a rules file to import"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        guard openPanel.runModal() == .OK, let url = openPanel.urls.first else { return }
        importRules(from: url)
    }

    private func importRules(from url: URL) {
        guard let session = viewModel.tunnelSession else {
            showRulesMessage(localized("Tunnel session unavailable for import.", "当前没有可用的隧道会话，无法导入。"), isError: true)
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let importedRules = try decoder.decode([ProxyRule].self, from: data)

            for rule in importedRules {
                RuleManager.addRule(
                    session: session,
                    processNames: rule.processNames,
                    targetHosts: rule.targetHosts,
                    targetPorts: rule.targetPorts,
                    protocol: rule.ruleProtocol,
                    action: rule.action,
                    enabled: rule.enabled
                ) { _, _, _ in }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showRulesMessage(
                    localized("Imported \(importedRules.count) rule\(importedRules.count == 1 ? "" : "s").", "已导入 \(importedRules.count) 条规则。"),
                    isError: false
                )
            }
        } catch {
            showRulesMessage(localized("Failed to import rules.", "导入规则失败。"), isError: true)
        }
    }

    private func openProxySettingsWindow() {
        NSApp.sendAction(#selector(AppDelegate.openProxySettings), to: nil, from: nil)
    }

    private func openProxyRulesWindow() {
        NSApp.sendAction(#selector(AppDelegate.openProxyRules), to: nil, from: nil)
    }

    private func saveInlineSettings() {
        let result = settingsFormModel.save(to: viewModel)
        showSettingsMessage(result.message, isError: result.isError)
        if !result.isError {
            settingsFormModel.load(from: viewModel.proxyConfig)
        }
    }

    private func showRulesMessage(_ message: String, isError: Bool) {
        rulesActionIsError = isError
        rulesActionMessage = message
        rulesMessageDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            rulesActionMessage = nil
        }
        rulesMessageDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func showSettingsMessage(_ message: String, isError: Bool) {
        settingsSaveIsError = isError
        settingsSaveMessage = message
        settingsMessageDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            settingsSaveMessage = nil
        }
        settingsMessageDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func showPreferencesMessage(_ message: String) {
        preferencesMessage = message
        preferencesMessageDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            preferencesMessage = nil
        }
        preferencesMessageDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private var proxyStatusTitle: String {
        viewModel.isProxyActive ? localized("Tunnel ready", "隧道已就绪") : localized("Tunnel idle", "隧道空闲")
    }

    private var proxyStatusDetail: String {
        guard let config = viewModel.proxyConfig else {
            return "No proxy configured"
        }

        return "\(config.host):\(config.port)"
    }

    private var filteredDashboardLogs: [DashboardLogEntry] {
        let entries = buildDashboardLogs()

        guard !logSearchText.isEmpty else { return entries }

        return entries.filter {
            $0.message.localizedCaseInsensitiveContains(logSearchText) ||
            $0.badge.localizedCaseInsensitiveContains(logSearchText)
        }
    }

    private func buildDashboardLogs() -> [DashboardLogEntry] {
        if !viewModel.connections.isEmpty {
            return viewModel.connections.prefix(6).map { connection in
                DashboardLogEntry(
                    id: connection.id,
                    message: "[\(connection.timestamp)] [\(connection.connectionProtocol)] \(connection.process) -> \(connection.destination):\(connection.port) -> \(connection.proxy)",
                    badge: connection.connectionProtocol,
                    badgeColor: .blue
                )
            }
        }

        if !viewModel.activityLogs.isEmpty {
            return viewModel.activityLogs.prefix(6).map { log in
                DashboardLogEntry(
                    id: log.id,
                    message: "[\(log.timestamp)] [\(log.level)] \(log.message)",
                    badge: log.level,
                    badgeColor: log.level == "ERROR" ? .red : AppColors.textSecondary
                )
            }
        }

        return [
            DashboardLogEntry(id: -1, message: "[--:--:--] [INFO] Configure a proxy profile to start collecting events.", badge: "INFO", badgeColor: AppColors.textSecondary),
            DashboardLogEntry(id: -2, message: "[--:--:--] [RULE] Add your first process rule to guide traffic routing.", badge: "RULE", badgeColor: AppColors.primary),
            DashboardLogEntry(id: -3, message: "[--:--:--] [CHECK] Start the tunnel to observe live connection activity.", badge: "CHECK", badgeColor: AppColors.textSecondary)
        ]
    }

    private var selectedConnectionTitle: String {
        guard let first = viewModel.connections.first else { return localized("No live selection", "暂无选中连接") }
        return "\(first.process) • \(first.destination)"
    }

    private var selectedConnectionLines: [String] {
        guard let first = viewModel.connections.first else {
            return [
                localized("Action: Waiting for live traffic", "动作：等待实时流量"),
                localized("Matched Rule: Not available yet", "命中规则：暂无"),
                localized("Start the tunnel to inspect live connection details.", "启动隧道后即可查看实时连接详情。")
            ]
        }

        return [
            localized("Action: \(first.proxy) via \(proxyStatusDetail)", "动作：通过 \(proxyStatusDetail) 使用 \(first.proxy)"),
            localized("Matched Rule: Derived from live tunnel inspection", "命中规则：来自实时隧道观察"),
            localized("Protocol: \(first.connectionProtocol) • Port: \(first.port)", "协议：\(first.connectionProtocol) • 端口：\(first.port)"),
            localized("Observed at \(first.timestamp)", "记录时间：\(first.timestamp)")
        ]
    }

    private var lastActivityTimestamp: String {
        viewModel.activityLogs.first?.timestamp ?? viewModel.connections.first?.timestamp ?? "--:--:--"
    }

    private var storedRules: [PersistedRule] {
        let rawRules = UserDefaults.standard.array(forKey: "proxyRules") as? [[String: Any]] ?? []
        return rawRules.enumerated().map { index, rule in
            PersistedRule(
                id: index,
                processNames: rule["processNames"] as? String ?? "",
                targetHosts: rule["targetHosts"] as? String ?? "",
                targetPorts: rule["targetPorts"] as? String ?? "",
                protocolName: rule["protocol"] as? String ?? "BOTH",
                action: rule["action"] as? String ?? "DIRECT",
                enabled: rule["enabled"] as? Bool ?? true
            )
        }
    }

    private var enabledRuleCount: Int {
        storedRules.filter(\.enabled).count
    }

    private var disabledRuleCount: Int {
        storedRules.count - enabledRuleCount
    }

    private var directRuleCount: Int {
        storedRules.filter { $0.actionDisplay == "DIRECT" }.count
    }

    private var proxyRuleCount: Int {
        storedRules.filter { $0.actionDisplay == "PROXY" }.count
    }

    private var settingsStatusTitle: String {
        localized("Application preferences ready", "应用偏好已就绪")
    }

    private var settingsStatusDetail: String {
        localized("Use this page for logging, update checks, and local behavior. Proxy host and credential changes now live in Proxies.", "这里用于配置日志、更新检查和本地行为；代理主机和认证信息请到“代理”页面修改。")
    }

    private func localizedSectionTitle(for section: SidebarSection) -> String {
        switch section {
        case .overview:
            return localized("Overview", "概览")
        case .connections:
            return localized("Connections", "连接")
        case .rules:
            return localized("Rules", "规则")
        case .proxies:
            return localized("Proxies", "代理")
        case .settings:
            return localized("Settings", "设置")
        }
    }

    private var isChinese: Bool {
        preferredLanguage == AppLanguage.chinese.rawValue
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
}

private struct DashboardLogEntry: Identifiable {
    let id: Int
    let message: String
    let badge: String
    let badgeColor: Color
}

private struct PersistedRule: Identifiable {
    let id: Int
    let processNames: String
    let targetHosts: String
    let targetPorts: String
    let protocolName: String
    let action: String
    let enabled: Bool

    var processDisplay: String {
        processNames.isEmpty ? "Any application" : processNames
    }

    var hostDisplay: String {
        targetHosts.isEmpty ? "Any host" : targetHosts
    }

    var portDisplay: String {
        targetPorts.isEmpty ? "Any port" : targetPorts
    }

    var protocolDisplay: String {
        protocolName.uppercased()
    }

    var actionDisplay: String {
        action.uppercased()
    }

    var actionColor: Color {
        switch actionDisplay {
        case "PROXY":
            return AppColors.primary
        case "BLOCK":
            return .red
        default:
            return AppColors.textSecondary
        }
    }

    var displayItem: RuleDisplayItem {
        RuleDisplayItem(
            id: "persisted-\(id)",
            processDisplay: processDisplay,
            hostDisplay: hostDisplay,
            portDisplay: portDisplay,
            protocolDisplay: protocolDisplay,
            actionDisplay: actionDisplay,
            enabled: enabled
        )
    }
}

private enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case connections
    case rules
    case proxies
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .connections: return "Connections"
        case .rules: return "Rules"
        case .proxies: return "Proxies"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .connections: return "waveform.path.ecg"
        case .rules: return "shield"
        case .proxies: return "network"
        case .settings: return "slider.horizontal.3"
        }
    }
}

private enum AppLanguage: String {
    case english = "en"
    case chinese = "zh-Hans"
}

enum AppColors {
    static let canvas = Color(nsColor: NSColor(calibratedRed: 0.965, green: 0.973, blue: 0.984, alpha: 1))
    static let sidebar = Color(nsColor: NSColor(calibratedRed: 0.973, green: 0.976, blue: 0.988, alpha: 1))
    static let card = Color(nsColor: NSColor(calibratedRed: 0.949, green: 0.957, blue: 0.973, alpha: 1))
    static let border = Color(nsColor: NSColor(calibratedRed: 0.886, green: 0.906, blue: 0.941, alpha: 1))
    static let banner = Color(nsColor: NSColor(calibratedRed: 0.800, green: 0.855, blue: 0.973, alpha: 1))
    static let warningTint = Color(nsColor: NSColor(calibratedRed: 1.0, green: 0.945, blue: 0.867, alpha: 1))
    static let errorTint = Color(nsColor: NSColor(calibratedRed: 0.992, green: 0.918, blue: 0.918, alpha: 1))
    static let primary = Color(nsColor: NSColor(calibratedRed: 0.357, green: 0.286, blue: 0.957, alpha: 1))
    static let primaryTint = Color(nsColor: NSColor(calibratedRed: 0.929, green: 0.945, blue: 1.0, alpha: 1))
    static let textPrimary = Color(nsColor: NSColor(calibratedRed: 0.164, green: 0.16, blue: 0.2, alpha: 1))
    static let textSecondary = Color(nsColor: NSColor(calibratedRed: 0.447, green: 0.471, blue: 0.529, alpha: 1))
    static let textMuted = Color(nsColor: NSColor(calibratedRed: 0.502, green: 0.525, blue: 0.592, alpha: 1))
}

struct PrimaryPillButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 16 : 18)
            .padding(.vertical, compact ? 10 : 12)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(AppColors.primary.opacity(configuration.isPressed ? 0.85 : 1))
            )
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
