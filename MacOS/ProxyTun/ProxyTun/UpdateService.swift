import Foundation
import AppKit

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let prerelease: Bool
    let publishedAt: String
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case prerelease
        case publishedAt = "published_at"
        case body
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

struct VersionInfo {
    let currentVersion: String
    let latestVersion: String
    let isUpdateAvailable: Bool
    let releaseName: String
    let publishedAt: Date?
    let releaseNotes: String
    let downloadUrl: String?
    let fileName: String?
    let downloadSize: Int64?
    let error: String?
}

class UpdateService {
    private let githubApiUrl = "https://api.github.com/repos/ProxyTun/ProxyTun/releases/latest"
    private let releaseDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func checkForUpdates() async -> VersionInfo {
        do {
            guard let url = URL(string: githubApiUrl) else {
                return errorVersion("Invalid API URL")
            }

            var request = URLRequest(url: url)
            request.setValue("ProxyTun-UpdateChecker", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorVersion("GitHub returned a non-HTTP response")
            }

            guard httpResponse.statusCode == 200 else {
                let responseSummary = summarizeResponseBody(data)
                return errorVersion(
                    "GitHub returned HTTP \(httpResponse.statusCode)" +
                    (responseSummary.isEmpty ? "" : ": \(responseSummary)")
                )
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            let currentVersion = getCurrentVersion()
            let latestVersion = parseVersion(release.tagName)
            let releaseDate = parseReleaseDate(release.publishedAt)

            // Find the PKG installer in assets
            let pkgAsset = release.assets.first { asset in
                let name = asset.name.lowercased()
                return name.hasSuffix(".pkg") &&
                    (name.contains("proxytun") || name.contains("installer"))
            }

            // a macOS pkg installer in the release is valid update
            let isUpdateAvailable = isNewerVersion(latestVersion, currentVersion) && pkgAsset != nil

            return VersionInfo(
                currentVersion: currentVersion,
                latestVersion: release.tagName,
                isUpdateAvailable: isUpdateAvailable,
                releaseName: release.name,
                publishedAt: releaseDate,
                releaseNotes: normalizeReleaseNotes(release.body),
                downloadUrl: pkgAsset?.browserDownloadUrl,
                fileName: pkgAsset?.name,
                downloadSize: pkgAsset?.size,
                error: nil
            )
        } catch {
            return errorVersion("Failed to check for updates: \(error.localizedDescription)")
        }
    }

    func downloadUpdate(from urlString: String, fileName: String, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "UpdateService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "UpdateService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
        }

        let totalBytes = response.expectedContentLength
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        // Remove existing file if any
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }

        var downloadedBytes: Int64 = 0

        for try await byte in asyncBytes {
            try fileHandle.write(contentsOf: Data([byte]))
            downloadedBytes += 1

            if totalBytes > 0 {
                let progressValue = Double(downloadedBytes) / Double(totalBytes)
                await MainActor.run {
                    progress(progressValue)
                }
            }
        }

        return fileURL
    }

    func installUpdateAndQuit(installerPath: URL) {
        // Open the PKG installer
        NSWorkspace.shared.open(installerPath)

        // Give the installer a moment to start, then quit
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func getCurrentVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "v\(version)"
        }
        return "v3.2.0"
    }

    private func parseVersion(_ tagName: String) -> String {
        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    private func parseReleaseDate(_ value: String) -> Date? {
        if let parsedWithFractionalSeconds = releaseDateFormatter.date(from: value) {
            return parsedWithFractionalSeconds
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: value)
    }

    private func isNewerVersion(_ latest: String, _ current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentVersionString = current.hasPrefix("v") ? String(current.dropFirst()) : current
        let currentComponents = currentVersionString.split(separator: ".").compactMap { Int($0) }

        for i in 0..<min(latestComponents.count, currentComponents.count) {
            if latestComponents[i] > currentComponents[i] {
                return true
            } else if latestComponents[i] < currentComponents[i] {
                return false
            }
        }

        return latestComponents.count > currentComponents.count
    }

    private func normalizeReleaseNotes(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No release notes provided." : trimmed
    }

    private func summarizeResponseBody(_ data: Data) -> String {
        guard let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else {
            return ""
        }

        let flattened = body.replacingOccurrences(of: "\n", with: " ")
        if flattened.count <= 160 {
            return flattened
        }
        return String(flattened.prefix(160)) + "..."
    }

    private func errorVersion(_ message: String) -> VersionInfo {
        return VersionInfo(
            currentVersion: getCurrentVersion(),
            latestVersion: "Error",
            isUpdateAvailable: false,
            releaseName: "Unavailable",
            publishedAt: nil,
            releaseNotes: "No release notes available.",
            downloadUrl: nil,
            fileName: nil,
            downloadSize: nil,
            error: message
        )
    }
}
