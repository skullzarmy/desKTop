import Foundation
import AppKit

public struct SemanticVersion: Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let raw: String

    public init(_ string: String) {
        self.raw = string
        let clean = string.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let parts = clean.split(separator: ".").compactMap { Int($0) }
        self.major = parts.indices.contains(0) ? parts[0] : 0
        self.minor = parts.indices.contains(1) ? parts[1] : 0
        self.patch = parts.indices.contains(2) ? parts[2] : 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        return lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
    }
}

public struct GitHubReleaseInfo: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [GitHubAssetInfo]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public struct GitHubAssetInfo: Codable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

public enum UpdateCheckResult: Sendable {
    case updateAvailable(version: String, releaseNotes: String?, downloadURL: URL, releasePageURL: URL)
    case upToDate(currentVersion: String)
    case error(String)
}

/// In-app updater scanning GitHub Releases using semantic versioning to detect, download, and install updates
public final class UpdateService: Sendable {
    public static let shared = UpdateService()
    public let repo = "skullzarmy/desKTop"

    public var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public init() {}

    /// Checks GitHub Releases for a newer version than currentVersion
    public func checkForUpdates() async -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .error("Invalid update API endpoint")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("desKTop-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .error("GitHub API returned non-200 status")
            }

            let release = try JSONDecoder().decode(GitHubReleaseInfo.self, from: data)
            let latestSemVer = SemanticVersion(release.tagName)
            let currentSemVer = SemanticVersion(currentVersion)

            if latestSemVer > currentSemVer {
                // Find desKTop.zip or fallback to desKTop.dmg
                guard let asset = release.assets.first(where: { $0.name == "desKTop.zip" }) ??
                                  release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
                      let downloadURL = URL(string: asset.browserDownloadUrl),
                      let pageURL = URL(string: release.htmlUrl) else {
                    return .error("No compatible release assets found")
                }

                return .updateAvailable(
                    version: release.tagName,
                    releaseNotes: release.body,
                    downloadURL: downloadURL,
                    releasePageURL: pageURL
                )
            } else {
                return .upToDate(currentVersion: currentVersion)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Downloads and performs atomic in-place replacement of the running application bundle
    @MainActor
    public func downloadAndInstall(
        downloadURL: URL,
        onProgress: @escaping (Double, String) -> Void
    ) async throws {
        onProgress(0.1, "Connecting to GitHub...")

        let (tempZipURL, _) = try await URLSession.shared.download(from: downloadURL)
        onProgress(0.5, "Verifying downloaded archive...")

        let fileManager = FileManager.default
        let extractDir = fileManager.temporaryDirectory.appendingPathComponent("desKTop_update_\(UUID().uuidString)")
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempZipURL)
        }

        // Unpack zip using macOS ditto to preserve permissions and signature
        let dittoProcess = Process()
        dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        dittoProcess.arguments = ["-xk", tempZipURL.path, extractDir.path]
        try dittoProcess.run()
        dittoProcess.waitUntilExit()

        guard dittoProcess.terminationStatus == 0 else {
            throw NSError(domain: "UpdateService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract update archive"])
        }

        onProgress(0.8, "Validating application signature...")

        // Locate new .app bundle
        let items = (try? fileManager.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)) ?? []
        guard let newAppBundle = items.first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "UpdateService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app bundle found inside update archive"])
        }

        // Strip quarantine flags
        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-cr", newAppBundle.path]
        try? xattrProcess.run()
        xattrProcess.waitUntilExit()

        // Ad-hoc sign bundle
        let signProcess = Process()
        signProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProcess.arguments = ["--force", "--deep", "--sign", "-", newAppBundle.path]
        try? signProcess.run()
        signProcess.waitUntilExit()

        onProgress(0.95, "Installing update and restarting...")

        // Current application bundle path (typically /Applications/desKTop.app)
        let currentBundlePath = Bundle.main.bundlePath
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // Generate shell script to wait for current process exit, replace bundle, and relaunch
        let scriptPath = extractDir.appendingPathComponent("relaunch.sh")
        let scriptContent = """
        #!/usr/bin/env bash
        while kill -0 \(currentPID) 2>/dev/null; do
            sleep 0.2
        done
        rm -rf "\(currentBundlePath)"
        mv "\(newAppBundle.path)" "\(currentBundlePath)"
        xattr -cr "\(currentBundlePath)"
        open "\(currentBundlePath)"
        rm -rf "\(extractDir.path)"
        """

        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)

        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["+x", scriptPath.path]
        try chmodProcess.run()
        chmodProcess.waitUntilExit()

        // Spawn relauncher script detached
        let relaunchProcess = Process()
        relaunchProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        relaunchProcess.arguments = [scriptPath.path]
        try relaunchProcess.run()

        // Terminate current instance cleanly
        NSApp.terminate(nil)
    }
}
