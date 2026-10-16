import AppKit
import Foundation
import Observation

/// Once a day, asks GitHub for the newest Chinese-edition release and shows a banner on the welcome
/// sheet when one is newer than the running build. Read-only: nothing is downloaded or installed.
/// "忽略此版本" silences a version until a newer one; "稍后" hides the banner for this launch.
@MainActor @Observable
final class ReleaseReminder {
    static let shared = ReleaseReminder()

    /// The release to announce: a version newer than the running build and not ignored.
    private(set) var update: (version: String, url: URL)?
    /// Set by "稍后": hides the banner until the next launch, without touching the ignored version.
    var dismissed = false

    private let defaults = UserDefaults.standard
    private let lastCheckKey = "releaseReminder.lastCheck"
    private let ignoredVersionKey = "releaseReminder.ignoredVersion"
    private let apiURL = URL(string: "https://api.github.com/repos/mainanamisa/compositor-cn/releases/latest")!

    /// Runs the check at most once a day; failures (offline, rate limits) stay silent and retry tomorrow.
    func checkIfDue() async {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - defaults.double(forKey: lastCheckKey) > 24 * 60 * 60 else { return }
        defaults.set(now, forKey: lastCheckKey)
        var request = URLRequest(url: apiURL)
        request.setValue("Compositor-CN", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let version = Self.version(fromTag: release.tag_name), let url = URL(string: release.html_url) else { return }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard Self.isNewer(version, than: current),
              Self.isNewer(version, than: defaults.string(forKey: ignoredVersionKey) ?? "0") else { return }
        update = (version, url)
    }

    /// "忽略此版本": never announce this version again (a newer one still will be).
    func ignore() {
        if let update { defaults.set(update.version, forKey: ignoredVersionKey) }
        self.update = nil
    }

    func openDownload() {
        if let update { NSWorkspace.shared.open(update.url) }
    }

    /// The version number in a release tag like "v1.5.3-cn": the leading digits and dots.
    nonisolated static func version(fromTag tag: String) -> String? {
        var tag = tag
        if tag.hasPrefix("v") { tag.removeFirst() }
        let version = tag.prefix(while: { $0.isNumber || $0 == "." })
        return version.isEmpty ? nil : String(version)
    }

    /// Numeric, section by section, so 1.5.10 is newer than 1.5.9 (text order would say otherwise).
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
    }
}
