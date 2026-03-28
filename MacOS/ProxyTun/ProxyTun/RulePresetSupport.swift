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
        processNames: "codex",
        targetHosts: "*.openai.com,api.openai.com,chat.openai.com",
        targetPorts: "443",
        protocolName: "TCP",
        action: "PROXY",
        description: "Direct OpenAI tooling traffic through your active proxy."
    )

    static let antigravity = RulePreset(
        id: "antigravity",
        title: "Antigravity",
        processNames: "antigravity",
        targetHosts: "*",
        targetPorts: "*",
        protocolName: "BOTH",
        action: "DIRECT",
        description: "Bootstrap a common desktop app rule with safe defaults."
    )

    static let claudeDesktop = RulePreset(
        id: "claude-desktop",
        title: "Claude Desktop",
        processNames: "Claude,Claude Desktop",
        targetHosts: "*.anthropic.com,api.anthropic.com",
        targetPorts: "443",
        protocolName: "TCP",
        action: "PROXY",
        description: "Create a desktop assistant route policy in one click."
    )

    static let defaults: [RulePreset] = [.codex, .antigravity, .claudeDesktop]
}

enum RulePresetApplyResult {
    case duplicate(String)
    case savedLocally(String)
    case savedAndSynced(String)
    case syncFailed(String)

    var message: String {
        switch self {
        case .duplicate(let title):
            return "\(title) is already saved in your rules."
        case .savedLocally(let title):
            return "\(title) saved locally. Start the tunnel to load it into the extension."
        case .savedAndSynced(let title):
            return "\(title) added and synced to the active tunnel."
        case .syncFailed(let message):
            return message
        }
    }

    var isError: Bool {
        switch self {
        case .duplicate, .syncFailed:
            return true
        case .savedLocally, .savedAndSynced:
            return false
        }
    }
}

enum RulePresetManager {
    static func storedRules() -> [[String: Any]] {
        UserDefaults.standard.array(forKey: "proxyRules") as? [[String: Any]] ?? []
    }

    static func applyPreset(
        _ preset: RulePreset,
        viewModel: ProxyTunViewModel,
        completion: @escaping (RulePresetApplyResult) -> Void
    ) {
        if hasDuplicateRule(for: preset) {
            completion(.duplicate(preset.title))
            return
        }

        let newRule: [String: Any] = [
            "processNames": preset.processNames,
            "targetHosts": preset.targetHosts,
            "targetPorts": preset.targetPorts,
            "protocol": preset.protocolName,
            "action": preset.action,
            "enabled": true
        ]

        var savedRules = storedRules()
        savedRules.append(newRule)
        UserDefaults.standard.set(savedRules, forKey: "proxyRules")

        guard let session = viewModel.tunnelSession else {
            completion(.savedLocally(preset.title))
            return
        }

        RuleManager.addRule(
            session: session,
            processNames: preset.processNames,
            targetHosts: preset.targetHosts,
            targetPorts: preset.targetPorts,
            protocol: preset.protocolName,
            action: preset.action,
            enabled: true
        ) { success, message, _ in
            DispatchQueue.main.async {
                if success {
                    completion(.savedAndSynced(preset.title))
                } else {
                    completion(.syncFailed("Saved \(preset.title) locally, but live sync failed: \(message)"))
                }
            }
        }
    }

    static func hasDuplicateRule(for preset: RulePreset) -> Bool {
        storedRules().contains { rule in
            (rule["processNames"] as? String ?? "") == preset.processNames &&
            (rule["targetHosts"] as? String ?? "") == preset.targetHosts &&
            (rule["targetPorts"] as? String ?? "") == preset.targetPorts &&
            (rule["protocol"] as? String ?? "").uppercased() == preset.protocolName.uppercased() &&
            (rule["action"] as? String ?? "").uppercased() == preset.action.uppercased()
        }
    }
}

struct RulePresetCard: View {
    let preset: RulePreset
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(preset.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(preset.action)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColors.primaryTint)
                    )
            }

            Text(preset.description)
                .font(.system(size: 12.5))
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Button("Use Preset", action: action)
                .buttonStyle(SecondaryPillButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
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
