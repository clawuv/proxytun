import SwiftUI

enum ProxySettingsFieldsStyle {
    case groupedForm
    case dashboard
}

struct ProxySettingsFieldsView: View {
    @ObservedObject var formModel: ProxySettingsFormModel
    let style: ProxySettingsFieldsStyle
    var showsRequiredFootnote = true

    var body: some View {
        switch style {
        case .groupedForm:
            groupedFormFields
        case .dashboard:
            dashboardFields
        }
    }

    private var groupedFormFields: some View {
        VStack(spacing: 0) {
            groupedPicker(label: "Proxy Type", selection: $formModel.proxyType, required: true)
            groupedTextField(label: "Proxy IP/Domain", placeholder: "127.0.0.1 or proxy.example.com", text: $formModel.proxyHost, required: true)
            groupedTextField(label: "Proxy Port", placeholder: "8080", text: $formModel.proxyPort, required: true)
            groupedTextField(label: "Username", placeholder: "Leave empty if no auth required", text: $formModel.username)
            groupedSecureField(label: "Password", placeholder: "Leave empty if no auth required", text: $formModel.password)

            if !formModel.validationError.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(formModel.validationError)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.top, 4)
            }

            if showsRequiredFootnote {
                HStack {
                    Text("* Required fields")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    private var dashboardFields: some View {
        VStack(spacing: 14) {
            dashboardMenuField(title: "Proxy Type", value: $formModel.proxyType, options: ProxySettingsFormModel.proxyTypes)

            HStack(spacing: 14) {
                dashboardTextField(title: "Proxy Host", placeholder: "127.0.0.1 or proxy.example.com", text: $formModel.proxyHost)
                dashboardTextField(title: "Port", placeholder: "8080", text: $formModel.proxyPort)
                    .frame(width: 140)
            }

            HStack(spacing: 14) {
                dashboardTextField(title: "Username", placeholder: "Optional", text: $formModel.username)
                dashboardSecureField(title: "Password", placeholder: "Optional", text: $formModel.password)
            }

            if !formModel.validationError.isEmpty {
                Text(formModel.validationError)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func groupedPicker(label: String, selection: Binding<String>, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            groupedLabel(label: label, required: required)
            Picker("Select proxy type", selection: selection) {
                Text("Select proxy type").tag("")
                ForEach(ProxySettingsFormModel.proxyTypes, id: \.self) { type in
                    Text(type.uppercased()).tag(type)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selection.wrappedValue) { _ in
                formModel.validate()
            }
        }
        .padding(.vertical, 8)
    }

    private func groupedTextField(label: String, placeholder: String, text: Binding<String>, required: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            groupedLabel(label: label, required: required)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _ in
                    formModel.validate()
                }
        }
        .padding(.vertical, 8)
    }

    private func groupedSecureField(label: String, placeholder: String, text: Binding<String>, required: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            groupedLabel(label: label, required: required)
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _ in
                    formModel.validate()
                }
        }
        .padding(.vertical, 8)
    }

    private func groupedLabel(label: String, required: Bool) -> some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            if required {
                Text("*")
                    .foregroundColor(.red)
            }
        }
    }

    private func dashboardTextField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onChange(of: text.wrappedValue) { _ in
                    formModel.validate()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColors.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardSecureField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onChange(of: text.wrappedValue) { _ in
                    formModel.validate()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColors.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardMenuField(title: String, value: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Picker(title, selection: value) {
                Text("Select proxy type").tag("")
                ForEach(options, id: \.self) { option in
                    Text(option.uppercased()).tag(option)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: value.wrappedValue) { _ in
                formModel.validate()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
    }
}
