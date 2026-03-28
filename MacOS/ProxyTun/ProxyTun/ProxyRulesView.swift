import SwiftUI
import NetworkExtension
import UniformTypeIdentifiers
import AppKit

struct ProxyRule: Identifiable, Codable {
    let id: UInt32
    let title: String
    let processNames: String
    let targetHosts: String
    let targetPorts: String
    let ruleProtocol: String
    let action: String
    var enabled: Bool
    
    enum CodingKeys: String, CodingKey {
        case title
        case processNames
        case targetHosts
        case targetPorts
        case ruleProtocol = "protocol"
        case action
        case enabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = 0
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.processNames = try container.decode(String.self, forKey: .processNames)
        self.targetHosts = try container.decode(String.self, forKey: .targetHosts)
        self.targetPorts = try container.decode(String.self, forKey: .targetPorts)
        self.ruleProtocol = try container.decode(String.self, forKey: .ruleProtocol)
        self.action = try container.decode(String.self, forKey: .action)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(processNames, forKey: .processNames)
        try container.encode(targetHosts, forKey: .targetHosts)
        try container.encode(targetPorts, forKey: .targetPorts)
        try container.encode(ruleProtocol, forKey: .ruleProtocol)
        try container.encode(action, forKey: .action)
        try container.encode(enabled, forKey: .enabled)
    }
    
    init(id: UInt32, title: String, processNames: String, targetHosts: String, targetPorts: String, ruleProtocol: String, action: String, enabled: Bool) {
        self.id = id
        self.title = title
        self.processNames = processNames
        self.targetHosts = targetHosts
        self.targetPorts = targetPorts
        self.ruleProtocol = ruleProtocol
        self.action = action
        self.enabled = enabled
    }
}

struct ProxyRulesView: View {
    @ObservedObject var viewModel: ProxyTunViewModel
    @State private var rules: [ProxyRule] = []
    @State private var selectedRuleIds: Set<UInt32> = []
    @State private var showAddRule = false
    @State private var editingRule: ProxyRule?
    @State private var isLoading = false
    @State private var presetMessage: String?
    @State private var presetMessageIsError = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            presetsStrip
            rulesOverviewStrip

            if let presetMessage {
                inlinePresetFeedback(message: presetMessage, isError: presetMessageIsError)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Spacer()
            } else if rules.isEmpty {
                Spacer()
                RuleEmptyStateView(
                    title: "No rules configured",
                    detail: "Use a preset or click 'Add Rule' to create your first routing policy."
                )
                Spacer()
            } else {
                Table(rules) {
                    TableColumn("Select") { rule in
                        Toggle("", isOn: Binding(
                            get: { selectedRuleIds.contains(rule.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedRuleIds.insert(rule.id)
                                } else {
                                    selectedRuleIds.remove(rule.id)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    .width(60)
                    
                    TableColumn("Enabled") { rule in
                        Toggle("", isOn: binding(for: rule))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .width(60)
                    
                    TableColumn("Actions") { rule in
                        HStack(spacing: 8) {
                            Button(action: { editingRule = rule }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "pencil")
                                    Text("Edit")
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.blue)
                            
                            Button(action: { deleteRule(rule) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                    Text("Delete")
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                    }
                    .width(140)
                    
                    TableColumn("SR") { rule in
                        Text("\(rule.id)")
                    }
                    .width(50)
                    
                    TableColumn("Bundle ID") { rule in
                        Text(rule.processNames.isEmpty ? "Any" : rule.processNames)
                    }
                    .width(150)
                    
                    TableColumn("Target Hosts") { rule in
                        Text(rule.targetHosts.isEmpty ? "Any" : rule.targetHosts)
                    }
                        .width(180)
                    
                    TableColumn("Target Ports") { rule in
                        Text(rule.targetPorts.isEmpty ? "Any" : rule.targetPorts)
                    }
                    .width(120)
                    
                    TableColumn("Protocol") { rule in
                        Text(rule.ruleProtocol)
                    }
                    .width(80)
                    
                    TableColumn("Action") { rule in
                        Text(rule.action)
                            .foregroundColor(actionColor(rule.action))
                            .fontWeight(.semibold)
                    }
                    .width(80)
                }
                .padding()
            }
        }
        .frame(minWidth: 1200, minHeight: 600)
        .onAppear {
            loadRules()
        }
        .sheet(isPresented: $showAddRule) {
            RuleEditorView(viewModel: viewModel, onSave: { loadRules() })
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(viewModel: viewModel, existingRule: rule, onSave: { loadRules() })
        }
    }

    private var rulesOverviewStrip: some View {
        Group {
            if !rules.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Saved Rules Overview")
                        .font(.headline)

                    VStack(spacing: 0) {
                        ForEach(rules.prefix(4)) { rule in
                            RuleDisplayRow(item: rule.displayItem)

                            if rule.id != rules.prefix(4).last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Proxy Rules")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button(action: {
                if selectedRuleIds.count == rules.count {
                    selectedRuleIds.removeAll()
                } else {
                    selectedRuleIds = Set(rules.map { $0.id })
                }
            }) {
                HStack {
                    Image(systemName: selectedRuleIds.count == rules.count ? "checkmark.square" : "square")
                    Text(selectedRuleIds.count == rules.count ? "Deselect All" : "Select All")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .disabled(rules.isEmpty)

            Button(action: { exportSelectedRules() }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .disabled(selectedRuleIds.isEmpty)

            Button(action: { importRulesFromFile() }) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Button(action: { showAddRule = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Rule")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var presetsStrip: some View {
        let presetColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Common Presets")
                .font(.headline)

            LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 12) {
                ForEach(RulePresetManager.availablePresets()) { preset in
                    let isApplied = RulePresetManager.isPresetEnabled(for: preset)
                    let hasStoredRule = RulePresetManager.hasDuplicateRule(for: preset)
                    RulePresetCard(
                        preset: preset,
                        toggleTitle: isApplied ? "Disable" : "Enable",
                        editTitle: "Edit",
                        deleteTitle: "Delete",
                        isApplied: isApplied,
                        canToggle: !viewModel.isProxyActive,
                        canDelete: hasStoredRule && !isApplied,
                        onToggle: { togglePreset(preset) },
                        onEdit: { editPreset(preset) },
                        onDelete: { deletePreset(preset) }
                    )
                }

                AddRuleCard(
                    title: "Add Rule",
                    detail: "Create a custom routing policy and save it into your local presets."
                ) {
                    showAddRule = true
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    private func inlinePresetFeedback(message: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.red : AppColors.primary)
            Text(message)
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isError ? AppColors.errorTint : AppColors.primaryTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.18) : AppColors.border, lineWidth: 1)
        )
    }
    
    private func binding(for rule: ProxyRule) -> Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { newValue in
                toggleRule(rule, enabled: newValue)
            }
        )
    }
    
    private func actionColor(_ action: String) -> Color {
        switch action {
        case "PROXY": return .green
        case "BLOCK": return .red
        case "DIRECT": return .blue
        default: return .primary
        }
    }
    
    private func loadRules() {
        guard let session = viewModel.tunnelSession else {
            rules = RulePresetManager.storedRules().enumerated().map { index, rule in
                ProxyRule(
                    id: UInt32(index + 1),
                    title: rule["title"] as? String ?? "",
                    processNames: rule["processNames"] as? String ?? "",
                    targetHosts: rule["targetHosts"] as? String ?? "",
                    targetPorts: rule["targetPorts"] as? String ?? "",
                    ruleProtocol: rule["protocol"] as? String ?? "BOTH",
                    action: rule["action"] as? String ?? "DIRECT",
                    enabled: rule["enabled"] as? Bool ?? true
                )
            }
            return
        }
        
        isLoading = true
        RuleManager.listRules(session: session) { [self] success, rulesList in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    rules = rulesList.map(mapToProxyRule)
                    RuleManager.saveRulesToUserDefaults(rulesList)
                }
            }
        }
    }
    
    private func mapToProxyRule(_ dict: [String: Any]) -> ProxyRule {
        ProxyRule(
            id: dict["ruleId"] as? UInt32 ?? 0,
            title: dict["title"] as? String ?? "",
            processNames: dict["processNames"] as? String ?? "",
            targetHosts: dict["targetHosts"] as? String ?? "",
            targetPorts: dict["targetPorts"] as? String ?? "",
            ruleProtocol: dict["protocol"] as? String ?? "BOTH",
            action: dict["action"] as? String ?? "DIRECT",
            enabled: dict["enabled"] as? Bool ?? true
        )
    }
    
    private func deleteRule(_ rule: ProxyRule) {
        guard let session = viewModel.tunnelSession else { return }
        
        RuleManager.removeRule(session: session, ruleId: rule.id) { [self] success, _ in
            if success { loadRules() }
        }
    }
    
    private func toggleRule(_ rule: ProxyRule, enabled: Bool) {
        guard let session = viewModel.tunnelSession else { return }
        
        RuleManager.toggleRule(session: session, ruleId: rule.id, enabled: enabled) { [self] _, _ in
            loadRules()
        }
    }
    
    private func getSelectedRules() -> [ProxyRule] {
        return rules.filter { selectedRuleIds.contains($0.id) }
    }
    
    private func exportSelectedRules() {
        guard !selectedRuleIds.isEmpty else { return }
        
        let selectedRules = getSelectedRules()
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export Proxy Rules"
        savePanel.message = "Choose a location to save the selected rules"
        savePanel.nameFieldStringValue = "ProxyTun-Rules.json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        
        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(selectedRules)
            try data.write(to: url)
        } catch {
            print("Export failed: \(error)")
        }
    }

    private func editPreset(_ preset: RulePreset) {
        editingRule = ProxyRule(
            id: 0,
            title: preset.title,
            processNames: preset.processNames,
            targetHosts: preset.targetHosts,
            targetPorts: preset.targetPorts,
            ruleProtocol: preset.protocolName,
            action: preset.action,
            enabled: true
        )
    }

    private func togglePreset(_ preset: RulePreset) {
        if RulePresetManager.isPresetEnabled(for: preset) {
            RulePresetManager.disablePreset(preset, viewModel: viewModel) { result in
                presetMessageIsError = result.isError
                presetMessage = result.message
                loadRules()
            }
        } else {
            RulePresetManager.applyPreset(preset, viewModel: viewModel) { result in
                presetMessageIsError = result.isError
                presetMessage = result.message
                loadRules()
            }
        }
    }

    private func deletePreset(_ preset: RulePreset) {
        guard RulePresetManager.hasDuplicateRule(for: preset) else { return }

        RulePresetManager.removePreset(preset, viewModel: viewModel) { result in
            presetMessageIsError = result.isError
            switch result {
            case .removedLocally(let title):
                presetMessage = "\(title) removed from local rules."
            case .removedAndSynced(let title):
                presetMessage = "\(title) removed and synced to the active tunnel."
            default:
                presetMessage = result.message
            }
            loadRules()
        }
    }
    
    private func importRulesFromFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Proxy Rules"
        openPanel.message = "Choose a rules file to import"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        
        let response = openPanel.runModal()
        guard response == .OK, let url = openPanel.urls.first else { return }
        
        importRules(from: url)
    }
    
    private func importRules(from url: URL) {
        guard let session = viewModel.tunnelSession else { return }
        
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
                loadRules()
            }
        } catch {
            print("Failed to import rules: \(error)")
        }
    }
}

private extension ProxyRule {
    var displayItem: RuleDisplayItem {
        RuleDisplayItem(
            id: "live-\(id)",
            processDisplay: processNames.isEmpty ? "Any application" : processNames,
            hostDisplay: targetHosts.isEmpty ? "Any host" : targetHosts,
            portDisplay: targetPorts.isEmpty ? "Any port" : targetPorts,
            protocolDisplay: ruleProtocol.uppercased(),
            actionDisplay: action.uppercased(),
            enabled: enabled
        )
    }
}

struct RuleEditorView: View {
    @ObservedObject var viewModel: ProxyTunViewModel
    var existingRule: ProxyRule?
    var onSave: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    @State private var title: String
    @State private var processNames: String
    @State private var targetHosts: String
    @State private var targetPorts: String
    @State private var selectedProtocol: String
    @State private var selectedAction: String
    
    private var isEditMode: Bool { existingRule != nil }
    
    init(viewModel: ProxyTunViewModel, existingRule: ProxyRule? = nil, onSave: @escaping () -> Void) {
        self.viewModel = viewModel
        self.existingRule = existingRule
        self.onSave = onSave
        
        _title = State(initialValue: existingRule?.title ?? "")
        _processNames = State(initialValue: existingRule?.processNames ?? "*")
        _targetHosts = State(initialValue: existingRule?.targetHosts ?? "*")
        _targetPorts = State(initialValue: existingRule?.targetPorts ?? "*")
        _selectedProtocol = State(initialValue: existingRule?.ruleProtocol ?? "TCP")
        _selectedAction = State(initialValue: existingRule?.action ?? "PROXY")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEditMode ? localized("Edit Rule", "编辑规则") : localized("Add Rule", "添加规则"))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(localized("Create an application routing policy using the same lightweight workflow as the main window.", "使用和主窗口一致的轻量方式创建应用分流规则。"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        editorField(
                            label: localized("Title", "标题"),
                            placeholder: localized("Rule title", "规则标题"),
                            text: $title,
                            hint: localized("Display name used in local configuration and exports.", "用于本地配置和导出文件中的显示名称。")
                        )
                        dividerInset
                        editorField(
                            label: localized("Bundle Identifier (Package Name)", "Bundle Identifier（包名）"),
                            placeholder: "*",
                            text: $processNames,
                            hint: localized("Example: com.apple.Safari; com.google.Chrome; com.*.browser; *", "示例：com.apple.Safari；com.google.Chrome；com.*.browser；*")
                        )
                        dividerInset
                        editorField(
                            label: localized("Target hosts", "目标主机"),
                            placeholder: "*",
                            text: $targetHosts,
                            hint: localized("Example: 127.0.0.1; 192.168.1.*; 10.0.0.1-10.0.0.254", "示例：127.0.0.1；192.168.1.*；10.0.0.1-10.0.0.254")
                        )
                        dividerInset
                        editorField(
                            label: localized("Target ports", "目标端口"),
                            placeholder: "*",
                            text: $targetPorts,
                            hint: localized("Example: 80; 8000-9000; 3128", "示例：80；8000-9000；3128")
                        )
                        dividerInset
                        segmentedEditorField(
                            label: localized("Protocol", "协议"),
                            selection: $selectedProtocol,
                            options: ["TCP", "UDP", "BOTH"]
                        )
                        dividerInset
                        segmentedEditorField(
                            label: localized("Action", "动作"),
                            selection: $selectedAction,
                            options: ["PROXY", "DIRECT", "BLOCK"]
                        )
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
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            Divider()

            HStack(spacing: 10) {
                Button(localized("Cancel", "取消")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SecondaryPillButtonStyle())

                Spacer()

                Button(localized("Save Rule", "保存规则")) {
                    saveRule()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PrimaryPillButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(AppColors.canvas)
        }
        .frame(width: 680, height: 620)
        .background(AppColors.canvas)
    }
    
    private var dividerInset: some View {
        Divider()
            .padding(.horizontal, 20)
    }

    private func editorField(label: String, placeholder: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )

            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func segmentedEditorField(label: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
    
    private func saveRule() {
        if let session = viewModel.tunnelSession {
            if let existing = existingRule {
                updateExistingRule(session: session, ruleId: existing.id)
            } else {
                addNewRule(session: session)
            }
        } else {
            saveRuleLocally()
        }
    }
    
    private func updateExistingRule(session: NETunnelProviderSession, ruleId: UInt32) {
        RuleManager.updateRule(
            session: session,
            ruleId: ruleId,
            processNames: processNames,
            targetHosts: targetHosts,
            targetPorts: targetPorts,
            protocol: selectedProtocol,
            action: selectedAction,
            enabled: true
        ) { [self] success, _ in
            if success {
                persistLocalRuleTitle()
                dismissOnSuccess()
            }
        }
    }
    
    private func addNewRule(session: NETunnelProviderSession) {
        RuleManager.addRule(
            session: session,
            processNames: processNames,
            targetHosts: targetHosts,
            targetPorts: targetPorts,
            protocol: selectedProtocol,
            action: selectedAction,
            enabled: true
        ) { [self] success, _, _ in
            if success {
                persistLocalRuleTitle()
                dismissOnSuccess()
            }
        }
    }

    private func saveRuleLocally() {
        var savedRules = RulePresetManager.storedRules()
        let ruleData = localRulePayload()

        if let existing = existingRule {
            if let matchedIndex = savedRules.firstIndex(where: { matches($0, existingRule: existing) }) {
                savedRules[matchedIndex] = ruleData
            } else {
                savedRules.append(ruleData)
            }
        } else if let matchedIndex = savedRules.firstIndex(where: { matches($0, ruleData: ruleData) }) {
            savedRules[matchedIndex] = ruleData
        } else {
            savedRules.append(ruleData)
        }

        UserDefaults.standard.set(savedRules, forKey: "proxyRules")
        dismissOnSuccess()
    }

    private func persistLocalRuleTitle() {
        var savedRules = RulePresetManager.storedRules()
        let ruleData = localRulePayload()
        let matchedIndex = savedRules.firstIndex(where: { matches($0, ruleData: ruleData) })

        if let matchedIndex {
            savedRules[matchedIndex] = ruleData.merging(savedRules[matchedIndex]) { newValue, _ in newValue }
        } else {
            savedRules.append(ruleData)
        }

        UserDefaults.standard.set(savedRules, forKey: "proxyRules")
    }

    private func localRulePayload() -> [String: Any] {
        [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "processNames": processNames,
            "targetHosts": targetHosts,
            "targetPorts": targetPorts,
            "protocol": selectedProtocol,
            "action": selectedAction,
            "enabled": true
        ]
    }

    private func matches(_ storedRule: [String: Any], existingRule: ProxyRule) -> Bool {
        (storedRule["processNames"] as? String ?? "") == existingRule.processNames &&
        (storedRule["targetHosts"] as? String ?? "") == existingRule.targetHosts &&
        (storedRule["targetPorts"] as? String ?? "") == existingRule.targetPorts &&
        (storedRule["protocol"] as? String ?? "").uppercased() == existingRule.ruleProtocol.uppercased() &&
        (storedRule["action"] as? String ?? "").uppercased() == existingRule.action.uppercased()
    }

    private func matches(_ storedRule: [String: Any], ruleData: [String: Any]) -> Bool {
        (storedRule["processNames"] as? String ?? "") == (ruleData["processNames"] as? String ?? "") &&
        (storedRule["targetHosts"] as? String ?? "") == (ruleData["targetHosts"] as? String ?? "") &&
        (storedRule["targetPorts"] as? String ?? "") == (ruleData["targetPorts"] as? String ?? "") &&
        (storedRule["protocol"] as? String ?? "").uppercased() == (ruleData["protocol"] as? String ?? "").uppercased() &&
        (storedRule["action"] as? String ?? "").uppercased() == (ruleData["action"] as? String ?? "").uppercased()
    }

    private var isChinese: Bool {
        preferredLanguage == "zh-Hans"
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
    
    private func dismissOnSuccess() {
        DispatchQueue.main.async {
            onSave()
            dismiss()
        }
    }
}

struct RulesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var rules: [ProxyRule]
    
    init(rules: [ProxyRule]) {
        self.rules = rules
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        rules = try decoder.decode([ProxyRule].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        return FileWrapper(regularFileWithContents: data)
    }
}
