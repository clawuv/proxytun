import SwiftUI
import Combine

struct UpdateNotificationView: View {
    @Environment(\.dismiss) private var dismiss
    let versionInfo: VersionInfo
    @StateObject private var viewModel: UpdateNotificationViewModel
    
    init(versionInfo: VersionInfo, logger: ((String, String) -> Void)? = nil) {
        self.versionInfo = versionInfo
        _viewModel = StateObject(wrappedValue: UpdateNotificationViewModel(versionInfo: versionInfo, logger: logger))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon and Title
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                Text("Update Available")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Divider()
            
            // Version Information
            VStack(spacing: 10) {
                HStack {
                    Text("Current Version:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(versionInfo.currentVersion)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("New Version:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(versionInfo.latestVersion)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }

                if !viewModel.releaseDateText.isEmpty {
                    HStack {
                        Text("Published:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(viewModel.releaseDateText)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            Text("A new version of ProxyTun is available!")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if !viewModel.releaseNotesPreview.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Release Notes")
                        .font(.headline)

                    ScrollView {
                        Text(viewModel.releaseNotesPreview)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 82)
                }
                .padding(.horizontal)
            }
            
            // Download Progress
            if viewModel.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text(viewModel.downloadStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            
            // Error Message
            if viewModel.hasError {
                Text(viewModel.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            // Action Buttons
            if !viewModel.isDownloading {
                HStack(spacing: 12) {
                    Button("Don't Ask Again") {
                        viewModel.dontAskAgain()
                        dismiss()
                    }
                    
                    Button("Later") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Update Now") {
                        Task {
                            await viewModel.downloadAndInstall()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                }
            } else {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(true)
            }
        }
        .padding()
        .frame(width: 460, height: 430)
    }
}

@MainActor
class UpdateNotificationViewModel: ObservableObject {
    @Published var downloadStatus = ""
    @Published var errorMessage = ""
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var hasError = false
    @Published var releaseDateText = ""
    @Published var releaseNotesPreview = ""
    
    private let updateService = UpdateService()
    private let versionInfo: VersionInfo
    private let logger: ((String, String) -> Void)?
    private var loggedDownloadMilestones: Set<Int> = []
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    init(versionInfo: VersionInfo, logger: ((String, String) -> Void)? = nil) {
        self.versionInfo = versionInfo
        self.logger = logger
        self.releaseDateText = versionInfo.publishedAt.map { displayDateFormatter.string(from: $0) } ?? ""
        self.releaseNotesPreview = Self.truncatedReleaseNotes(versionInfo.releaseNotes)
    }
    
    func downloadAndInstall() async {
        guard let downloadUrl = versionInfo.downloadUrl,
              let fileName = versionInfo.fileName else {
            hasError = true
            errorMessage = "Download URL not available"
            logger?("ERROR", "Update download failed: download URL not available")
            return
        }
        
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Starting download..."
        hasError = false
        errorMessage = ""
        loggedDownloadMilestones.removeAll()
        logger?("INFO", "Starting update download: \(fileName)")
        
        do {
            let installerPath = try await updateService.downloadUpdate(
                from: downloadUrl,
                fileName: fileName
            ) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                    let percent = Int(progress * 100)
                    self.downloadStatus = String(format: "Downloading... %.0f%%", progress * 100)
                    self.logDownloadProgressIfNeeded(percent: percent)
                }
            }
            
            downloadStatus = "Download complete. Starting installer..."
            logger?("INFO", "Update download complete: \(fileName)")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            logger?("INFO", "Launching installer: \(fileName)")
            updateService.installUpdateAndQuit(installerPath: installerPath)
        } catch {
            hasError = true
            errorMessage = "Error downloading update: \(error.localizedDescription)"
            downloadStatus = "Download failed"
            isDownloading = false
            logger?("ERROR", "Update download failed: \(error.localizedDescription)")
        }
    }
    
    func dontAskAgain() {
        UserDefaults.standard.set(false, forKey: "checkForUpdatesOnStartup")
    }

    private func logDownloadProgressIfNeeded(percent: Int) {
        let milestones = [25, 50, 75, 100]
        guard let milestone = milestones.first(where: { percent >= $0 && !loggedDownloadMilestones.contains($0) }) else {
            return
        }

        loggedDownloadMilestones.insert(milestone)
        logger?("INFO", "Update download progress: \(milestone)%")
    }

    private static func truncatedReleaseNotes(_ notes: String) -> String {
        let normalized = notes.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.count <= 360 {
            return normalized
        }
        return String(normalized.prefix(360)) + "\n\n..."
    }
}
