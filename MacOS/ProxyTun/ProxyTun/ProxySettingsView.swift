import SwiftUI

struct ProxySettingsView: View {
    @ObservedObject var viewModel: ProxyTunViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var formModel = ProxySettingsFormModel()
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            formContent
            Divider()
            footerButtons
        }
        .frame(width: 600, height: 600)
        .onAppear {
            formModel.load(from: viewModel.proxyConfig)
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "network")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Proxy Settings")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var formContent: some View {
        Form {
            Section {
                ProxySettingsFieldsView(formModel: formModel, style: .groupedForm)
            }
        }
        .formStyle(.grouped)
    }
    
    private var footerButtons: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button("Save Changes") {
                saveSettings()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(formModel.isSaveDisabled)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func saveSettings() {
        _ = formModel.save(to: viewModel)
    }
}
