import Foundation

struct AvailableUpdate: Equatable {
    let version: String
    let releaseURL: URL
    var package: UpdatePackage? = nil
}

struct UpdateAsset: Decodable, Equatable {
    let name: String
    let downloadURL: URL
    let size: Int64
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case downloadURL = "browser_download_url"
    }

    var sha256: String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let value = String(digest.dropFirst(7))
        guard value.count == 64, value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return value.lowercased()
    }
}

struct UpdatePackage: Equatable {
    let installer: UpdateAsset
    let checksum: UpdateAsset
}

enum UpdateCheckService {
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/asetho/ChatGPT-Usage/releases/latest"
    )!

    static func fetchAvailableUpdate(
        currentVersion: String,
        session: URLSession = .shared
    ) async throws -> AvailableUpdate? {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("asetho-ChatGPT-Usage/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return availableUpdate(from: data, currentVersion: currentVersion)
    }

    static func availableUpdate(from data: Data, currentVersion: String) -> AvailableUpdate? {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let latestVersion = SemanticVersion(release.tagName),
              let installedVersion = SemanticVersion(currentVersion),
              latestVersion > installedVersion,
              release.draft != true, release.prerelease != true,
              isReleaseURL(release.htmlURL, path: "/asetho/ChatGPT-Usage/releases/tag/\(release.tagName)") else {
            return nil
        }

        let name = "ChatGPTUsage-\(latestVersion).dmg"
        let package = package(from: release.assets ?? [], name: name, tag: release.tagName)
        return AvailableUpdate(version: latestVersion.description, releaseURL: release.htmlURL, package: package)
    }

    static func isReleaseURL(_ url: URL, path: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
            && url.path == path
    }

    private static func package(from assets: [UpdateAsset], name: String, tag: String) -> UpdatePackage? {
        func asset(_ name: String, maximumSize: Int64) -> UpdateAsset? {
            let matches = assets.filter { $0.name == name }
            guard matches.count == 1, let value = matches.first,
                  value.size > 0, value.size <= maximumSize, value.sha256 != nil,
                  isReleaseURL(value.downloadURL, path: "/asetho/ChatGPT-Usage/releases/download/\(tag)/\(name)") else {
                return nil
            }
            return value
        }
        guard let installer = asset(name, maximumSize: 512 * 1_024 * 1_024),
              let checksum = asset(name + ".sha256", maximumSize: 4_096) else { return nil }
        return UpdatePackage(installer: installer, checksum: checksum)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [UpdateAsset]?
    let draft: Bool?
    let prerelease: Bool?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets, draft, prerelease
    }
}

private struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }

        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(components[0]), major >= 0,
              let minor = Int(components[1]), minor >= 0,
              let patch = Int(components[2]), patch >= 0 else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
