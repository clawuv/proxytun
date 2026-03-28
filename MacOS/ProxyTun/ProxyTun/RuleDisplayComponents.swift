import SwiftUI

struct RuleDisplayItem: Identifiable {
    let id: String
    let processDisplay: String
    let hostDisplay: String
    let portDisplay: String
    let protocolDisplay: String
    let actionDisplay: String
    let enabled: Bool

    var actionColor: Color {
        switch actionDisplay.uppercased() {
        case "PROXY":
            return AppColors.primary
        case "BLOCK":
            return .red
        default:
            return AppColors.textSecondary
        }
    }
}

struct RuleDisplayRow: View {
    let item: RuleDisplayItem

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.processDisplay)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("\(item.hostDisplay) • \(item.portDisplay)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.protocolDisplay)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 56, alignment: .leading)

            Text(item.actionDisplay)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(item.actionColor)
                .frame(width: 58, alignment: .leading)

            Text(item.enabled ? "Enabled" : "Disabled")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.enabled ? AppColors.primary : AppColors.textSecondary)
                .frame(width: 62, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
