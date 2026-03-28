import SwiftUI
import Combine

struct UpdateCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: UpdateCheckViewModel

    init(logger: ((String, String) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: UpdateCheckViewModel(logger: logger))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Check for Updates")
                .font(.title2)
                .fontWeight(.semibold)
            
            Divider()
            
            // Version Info
            VStack(spacing: 12) {
                HStack {
                    Text("Current Version:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.currentVersion)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Latest Version:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.latestVersion)
                        .foregroundColor(viewModel.latestVersionColor)
                }

                if !viewModel.releaseName.isEmpty {
                    HStack(alignment: .top) {
                        Text("Release:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(viewModel.releaseName)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
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
            
            // Status Message
            if !viewModel.statusMessage.isEmpty {
                HStack {
                    Image(systemName: viewModel.isUpdateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(viewModel.statusColor)
                    Text(viewModel.statusMessage)
                        .foregroundColor(viewModel.statusColor)
                        .fontWeight(.medium)
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
            
            // Progress
            if viewModel.isChecking {
                ProgressView("Checking for updates...")
                    .padding()
            } else if viewModel.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text(viewModel.downloadStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

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
                    .frame(height: 84)
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Buttons
            HStack(spacing: 12) {
                if viewModel.isUpdateAvailable && !viewModel.isDownloading {
                    Button("Download Now") {
                        Task {
                            await viewModel.downloadAndInstall()
                        }
                    }
                    .controlSize(.large)
                }
                
                if !viewModel.isChecking && !viewModel.isDownloading {
                    Button("Check Again") {
                        Task {
                            await viewModel.checkForUpdates()
                        }
                    }
                }
                
                Button(viewModel.isDownloading ? "Cancel" : "Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isDownloading)
            }
        }
        .padding()
        .frame(width: 460, height: 430)
        .task {
            await viewModel.checkForUpdates()
        }
    }
}

@MainActor
class UpdateCheckViewModel: ObservableObject {
    @Published var currentVersion = ""
    @Published var latestVersion = ""
    @Published var statusMessage = ""
    @Published var statusColor = Color.secondary
    @Published var latestVersionColor = Color.secondary
    @Published var errorMessage = ""
    @Published var isChecking = false
    @Published var hasError = false
    @Published var isUpdateAvailable = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus = ""
    @Published var releaseName = ""
    @Published var releaseDateText = ""
    @Published var releaseNotesPreview = ""
    
    private let updateService = UpdateService()
    private var versionInfo: VersionInfo?
    private let logger: ((String, String) -> Void)?
    private var loggedDownloadMilestones: Set<Int> = []
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init(logger: ((String, String) -> Void)? = nil) {
        self.logger = logger
    }
    
    func checkForUpdates() async {
        isChecking = true
        hasError = false
        statusMessage = ""
        errorMessage = ""
        logger?("INFO", "Checking for updates...")
        
        let info = await updateService.checkForUpdates()
        versionInfo = info
        
        currentVersion = info.currentVersion
        latestVersion = info.latestVersion
        isUpdateAvailable = info.isUpdateAvailable
        releaseName = info.releaseName
        releaseDateText = info.publishedAt.map { displayDateFormatter.string(from: $0) } ?? ""
        releaseNotesPreview = truncatedReleaseNotes(info.releaseNotes)
        
        if let error = info.error {
            hasError = true
            errorMessage = error
            statusMessage = "Unable to check for updates"
            statusColor = .red
            latestVersionColor = .red
            logger?("ERROR", "Update check failed: \(error)")
        } else if info.isUpdateAvailable {
            statusMessage = "New version available!"
            statusColor = .green
            latestVersionColor = .green
            logger?("INFO", "Update available: \(info.latestVersion) (\(info.releaseName))")
        } else {
            statusMessage = "You have the latest version"
            statusColor = .green
            latestVersionColor = .blue
            logger?("INFO", "Manual update check complete: already on the latest version")
        }
        
        isChecking = false
    }
    
    func downloadAndInstall() async {
        guard let info = versionInfo,
              let downloadUrl = info.downloadUrl,
              let fileName = info.fileName else {
            errorMessage = "Download URL not available"
            hasError = true
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
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            logger?("INFO", "Launching installer: \(fileName)")
            updateService.installUpdateAndQuit(installerPath: installerPath)
        } catch {
            hasError = true
            errorMessage = "Download error: \(error.localizedDescription)"
            downloadStatus = "Download failed"
            isDownloading = false
            logger?("ERROR", "Update download failed: \(error.localizedDescription)")
        }
    }

    private func logDownloadProgressIfNeeded(percent: Int) {
        let milestones = [25, 50, 75, 100]
        guard let milestone = milestones.first(where: { percent >= $0 && !loggedDownloadMilestones.contains($0) }) else {
            return
        }

        loggedDownloadMilestones.insert(milestone)
        logger?("INFO", "Update download progress: \(milestone)%")
    }

    private func truncatedReleaseNotes(_ notes: String) -> String {
        let normalized = notes.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.count <= 500 {
            return normalized
        }
        return String(normalized.prefix(500)) + "\n\n..."
    }
}
