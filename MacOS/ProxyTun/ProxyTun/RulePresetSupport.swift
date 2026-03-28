import SwiftUI

struct RulePreset: Identifiable {
    let id: String
    let title: String
    let processNames: String
    let targetHosts: String
    let targetPorts: String
    let protocolName: String
    let action: String
    let description: String

    static let codex = RulePreset(
        id: "codex",
        title: "Codex",
        processNames: "Codex.app; Codex; com.openai.codex",
        targetHosts: "*",
        targetPorts: "*",
        protocolName: "TCP",
        action: "PROXY",
        description: "builtin"
    )

    static let antigravity = RulePreset(
        id: "antigravity",
        title: "Antigravity",
        processNames: "Antigravity.app; Antigravity; com.google.antigravity;com.google.antigravity.helper; language_server_macos_arm",
        targetHosts: "*",
        targetPorts: "*",
        protocolName: "TCP",
        action: "PROXY",
        description: "builtin"
    )

    static let claudeDesktop = RulePreset(
        id: "claude-desktop",
        title: "Claude Desktop",
        processNames: "Claude,Claude Desktop",
        targetHosts: "*.anthropic.com,api.anthropic.com",
        targetPorts: "443",
        protocolName: "TCP",
        action: "PROXY",
        description: "builtin"
    )

    static let defaults: [RulePreset] = [.codex, .antigravity, .claudeDesktop]
}

enum RulePresetApplyResult {
    case duplicate(String)
    case savedLocally(String)
    case savedAndSynced(String)
    case disabledLocally(String)
    case disabledAndSynced(String)
    case removedLocally(String)
    case removedAndSynced(String)
    case syncFailed(String)

    var message: String {
        switch self {
        case .duplicate(let title):
            return "\(title) is already saved in your rules."
        case .savedLocally(let title):
            return "\(title) saved locally. Start the tunnel to load it into the extension."
        case .savedAndSynced(let title):
            return "\(title) added and synced to the active tunnel."
        case .disabledLocally(let title):
            return "\(title) disabled locally."
        case .disabledAndSynced(let title):
            return "\(title) disabled and synced to the active tunnel."
        case .removedLocally(let title):
            return "\(title) removed from local rules."
        case .removedAndSynced(let title):
            return "\(title) removed and synced to the active tunnel."
        case .syncFailed(let message):
            return message
        }
    }

    var isError: Bool {
        switch self {
        case .duplicate, .syncFailed:
            return true
        case .savedLocally, .savedAndSynced, .disabledLocally, .disabledAndSynced, .removedLocally, .removedAndSynced:
            return false
        }
    }
}

enum RulePresetManager {
    static func storedRules() -> [[String: Any]] {
        UserDefaults.standard.array(forKey: "proxyRules") as? [[String: Any]] ?? []
    }

    static func availablePresets() -> [RulePreset] {
        let builtInPresets = RulePreset.defaults
        let customPresets = storedRules().compactMap(makeCustomPreset(from:))
            .filter { customPreset in
                !builtInPresets.contains(where: { preset in
                    matches(
                        processNames: preset.processNames,
                        targetHosts: preset.targetHosts,
                        targetPorts: preset.targetPorts,
                        protocolName: preset.protocolName,
                        action: preset.action,
                        against: customPreset
                    )
                })
            }

        return builtInPresets + customPresets
    }

    static func applyPreset(
        _ preset: RulePreset,
        viewModel: ProxyTunViewModel,
        completion: @escaping (RulePresetApplyResult) -> Void
    ) {
        var savedRules = storedRules()
        if let existingIndex = savedRules.firstIndex(where: { matches(rule: $0, preset: preset) }) {
            savedRules[existingIndex]["enabled"] = true
            if (savedRules[existingIndex]["title"] as? String)?.isEmpty != false {
                savedRules[existingIndex]["title"] = preset.title
            }
        } else {
            savedRules.append([
                "title": preset.title,
                "processNames": preset.processNames,
                "targetHosts": preset.targetHosts,
                "targetPorts": preset.targetPorts,
                "protocol": preset.protocolName,
                "action": preset.action,
                "enabled": true
            ])
        }
        UserDefaults.standard.set(savedRules, forKey: "proxyRules")

        guard let session = viewModel.tunnelSession else {
            completion(.savedLocally(preset.title))
            return
        }

        RuleManager.clearRules(session: session) { success, message in
            guard success else {
                DispatchQueue.main.async {
                    completion(.syncFailed("Saved \(preset.title) locally, but live sync failed: \(message)"))
                }
                return
            }

            RuleManager.loadRulesFromUserDefaults(session: session) { _, _ in
                DispatchQueue.main.async {
                    completion(.savedAndSynced(preset.title))
                }
            }
        }
    }

    static func disablePreset(
        _ preset: RulePreset,
        viewModel: ProxyTunViewModel,
        completion: @escaping (RulePresetApplyResult) -> Void
    ) {
        var savedRules = storedRules()
        guard let existingIndex = savedRules.firstIndex(where: { matches(rule: $0, preset: preset) }) else {
            DispatchQueue.main.async {
                completion(.duplicate(preset.title))
            }
            return
        }

        savedRules[existingIndex]["enabled"] = false
        UserDefaults.standard.set(savedRules, forKey: "proxyRules")

        guard let session = viewModel.tunnelSession else {
            completion(.disabledLocally(preset.title))
            return
        }

        RuleManager.clearRules(session: session) { success, message in
            guard success else {
                DispatchQueue.main.async {
                    completion(.syncFailed("Disabled \(preset.title) locally, but live sync failed: \(message)"))
                }
                return
            }

            RuleManager.loadRulesFromUserDefaults(session: session) { _, _ in
                DispatchQueue.main.async {
                    completion(.disabledAndSynced(preset.title))
                }
            }
        }
    }

    static func removePreset(
        _ preset: RulePreset,
        viewModel: ProxyTunViewModel,
        completion: @escaping (RulePresetApplyResult) -> Void
    ) {
        let filteredRules = storedRules().filter { rule in
            !matches(rule: rule, preset: preset)
        }
        UserDefaults.standard.set(filteredRules, forKey: "proxyRules")

        guard let session = viewModel.tunnelSession else {
            completion(.removedLocally(preset.title))
            return
        }

        RuleManager.clearRules(session: session) { success, message in
            guard success else {
                DispatchQueue.main.async {
                    completion(.syncFailed("Removed \(preset.title) locally, but live sync failed: \(message)"))
                }
                return
            }

            RuleManager.loadRulesFromUserDefaults(session: session) { _, _ in
                DispatchQueue.main.async {
                    completion(.removedAndSynced(preset.title))
                }
            }
        }
    }

    static func hasDuplicateRule(for preset: RulePreset) -> Bool {
        storedRules().contains { matches(rule: $0, preset: preset) }
    }

    static func isPresetEnabled(for preset: RulePreset) -> Bool {
        storedRules().first(where: { matches(rule: $0, preset: preset) })?["enabled"] as? Bool ?? false
    }

    private static func makeCustomPreset(from rule: [String: Any]) -> RulePreset? {
        let processNames = rule["processNames"] as? String ?? ""
        let targetHosts = rule["targetHosts"] as? String ?? ""
        let targetPorts = rule["targetPorts"] as? String ?? ""
        let protocolName = (rule["protocol"] as? String ?? "BOTH").uppercased()
        let action = (rule["action"] as? String ?? "DIRECT").uppercased()
        guard !processNames.isEmpty || !targetHosts.isEmpty || !targetPorts.isEmpty else { return nil }

        let rawTitle = (rule["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (rawTitle?.isEmpty == false ? rawTitle! : processNames.isEmpty ? "Custom Rule" : processNames)
        let hostDisplay = targetHosts.isEmpty ? "*" : targetHosts
        let portDisplay = targetPorts.isEmpty ? "*" : targetPorts
        let description = "\(hostDisplay) · \(portDisplay)"
        let idSeed = "\(processNames)|\(targetHosts)|\(targetPorts)|\(protocolName)|\(action)"

        return RulePreset(
            id: "custom-\(idSeed)",
            title: title,
            processNames: processNames,
            targetHosts: targetHosts,
            targetPorts: targetPorts,
            protocolName: protocolName,
            action: action,
            description: description
        )
    }

    private static func matches(rule: [String: Any], preset: RulePreset) -> Bool {
        (rule["processNames"] as? String ?? "") == preset.processNames &&
        (rule["targetHosts"] as? String ?? "") == preset.targetHosts &&
        (rule["targetPorts"] as? String ?? "") == preset.targetPorts &&
        (rule["protocol"] as? String ?? "").uppercased() == preset.protocolName.uppercased() &&
        (rule["action"] as? String ?? "").uppercased() == preset.action.uppercased()
    }

    private static func matches(
        processNames: String,
        targetHosts: String,
        targetPorts: String,
        protocolName: String,
        action: String,
        against preset: RulePreset
    ) -> Bool {
        processNames == preset.processNames &&
        targetHosts == preset.targetHosts &&
        targetPorts == preset.targetPorts &&
        protocolName.uppercased() == preset.protocolName.uppercased() &&
        action.uppercased() == preset.action.uppercased()
    }
}

struct RulePresetCard: View {
    let preset: RulePreset
    let toggleTitle: String
    let editTitle: String
    let deleteTitle: String
    let isApplied: Bool
    let canToggle: Bool
    let canDelete: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(preset.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isApplied ? Color(red: 0.17, green: 0.22, blue: 0.34) : AppColors.textPrimary)
                Spacer()
                Button(toggleTitle, action: onToggle)
                    .buttonStyle(PresetToggleButtonStyle(isApplied: isApplied, isEnabled: canToggle))
                    .disabled(!canToggle)
            }

            Text(preset.processNames.isEmpty ? "*" : preset.processNames)
                .font(.system(size: 12.5))
                .foregroundStyle(
                    isApplied
                        ? Color(red: 0.36, green: 0.43, blue: 0.56)
                        : AppColors.textSecondary
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(editTitle, action: onEdit)
                    .buttonStyle(PresetEditButtonStyle(isEnabled: !isApplied))
                    .disabled(isApplied)

                Button(deleteTitle, action: onDelete)
                    .buttonStyle(PresetDeleteButtonStyle(isEnabled: canDelete))
                    .disabled(!canDelete)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isApplied
                        ? Color(red: 0.84, green: 0.89, blue: 0.99)
                        : AppColors.card
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isApplied ? AppColors.primary.opacity(0.16) : AppColors.border, lineWidth: 1)
        )
    }
}

struct PresetToggleButtonStyle: ButtonStyle {
    let isApplied: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(
                isEnabled
                    ? (
                        isApplied
                            ? Color.red.opacity(0.9)
                            : AppColors.primary
                    )
                    : AppColors.textMuted
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isEnabled
                            ? (
                                isApplied
                                    ? Color.red.opacity(configuration.isPressed ? 0.12 : 0.08)
                                    : AppColors.primaryTint.opacity(configuration.isPressed ? 0.8 : 1)
                            )
                            : Color.white.opacity(0.68)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isEnabled
                            ? (
                                isApplied
                                    ? Color.red.opacity(0.18)
                                    : AppColors.primary.opacity(0.15)
                            )
                            : AppColors.border,
                        lineWidth: 1
                    )
            )
    }
}

struct AddRuleCard: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(AppColors.primaryTint)
                        .frame(width: 56, height: 56)

                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(detail)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 148)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

struct PresetEditButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? AppColors.textPrimary : AppColors.textMuted)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }
}

struct PresetDeleteButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.red.opacity(0.9) : AppColors.textMuted)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(
                        isEnabled
                            ? Color.red.opacity(configuration.isPressed ? 0.12 : 0.08)
                            : Color.white.opacity(0.72)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(isEnabled ? Color.red.opacity(0.18) : AppColors.border, lineWidth: 1)
            )
    }
}

struct RuleEmptyStateView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
