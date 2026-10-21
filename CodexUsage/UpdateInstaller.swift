import AppKit
import CryptoKit
import Foundation

enum UpdateInstallError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum UpdateInstaller {
    private static var stateDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "com.aaronwhippo.CodexUsage")/Updates", isDirectory: true)
    }
    private static var pendingURL: URL { stateDirectory.appendingPathComponent("pending.json") }
    private static var errorURL: URL { stateDirectory.appendingPathComponent("last-error.txt") }

    private struct PendingUpdate: Codable {
        let target: URL
        let version: String
        let transaction: URL
    }

    // The new process acknowledges launch before the helper removes the rollback copy.
    static func recordSuccessfulLaunch() {
        guard let data = try? Data(contentsOf: pendingURL),
              let pending = try? JSONDecoder().decode(PendingUpdate.self, from: data),
              Bundle.main.bundleURL.standardizedFileURL == pending.target.standardizedFileURL,
              Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == pending.version,
              pending.transaction.deletingLastPathComponent().standardizedFileURL == stateDirectory.standardizedFileURL,
              pending.transaction.lastPathComponent.hasPrefix("transaction-") else { return }
        try? Data().write(to: pending.transaction.appendingPathComponent("launched"), options: .atomic)
    }

    static func takePreviousError() -> String? {
        guard let message = try? String(contentsOf: errorURL, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: errorURL)
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    static func prepareAndLaunch(_ update: AvailableUpdate, status: @escaping (String) -> Void) async throws {
        guard let package = update.package else {
            throw UpdateInstallError.message("This release needs to be installed from the release page.")
        }
        let target = Bundle.main.bundleURL.standardizedFileURL
        try validateTarget(target)
        let files = FileManager.default
        try files.createDirectory(at: stateDirectory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        guard !files.fileExists(atPath: pendingURL.path) else {
            throw UpdateInstallError.message("An update is still finishing. Try again shortly.")
        }
        let identifier = UUID().uuidString
        let transaction = stateDirectory.appendingPathComponent("transaction-\(identifier)", isDirectory: true)
        let stage = target.deletingLastPathComponent().appendingPathComponent(".ChatGPTUsage-update-\(identifier).app")
        let backup = target.deletingLastPathComponent().appendingPathComponent(".ChatGPTUsage-backup-\(identifier).app")
        try files.createDirectory(at: transaction, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        var handedOff = false
        defer {
            if !handedOff {
                try? files.removeItem(at: stage)
                try? files.removeItem(at: transaction)
                try? files.removeItem(at: pendingURL)
            }
        }

        status("Downloading update…")
        let installer = try await download(package.installer, into: transaction)
        let checksum = try await download(package.checksum, into: transaction)
        status("Verifying update…")
        try verifyChecksumFile(Data(contentsOf: checksum), for: package.installer)

        status("Preparing update…")
        let expectedIdentifier = Bundle.main.bundleIdentifier ?? "com.aaronwhippo.CodexUsage"
        try await Task.detached(priority: .utility) {
            let mount = transaction.appendingPathComponent("mount", isDirectory: true)
            try files.createDirectory(at: mount, withIntermediateDirectories: false)
            try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, installer.path])
            defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
            let candidate = mount.appendingPathComponent("ChatGPT Usage.app", isDirectory: true)
            try validateBundle(candidate, identifier: expectedIdentifier, version: update.version)
            try run("/usr/bin/codesign", ["--verify", "--strict", candidate.path])
            // ditto preserves quarantine and other extended attributes.
            try run("/usr/bin/ditto", [candidate.path, stage.path])
            try validateBundle(stage, identifier: expectedIdentifier, version: update.version)
            try run("/usr/bin/codesign", ["--verify", "--strict", stage.path])
        }.value

        guard let bundledScript = Bundle.main.url(forResource: "install-update", withExtension: "sh") else {
            throw UpdateInstallError.message("The update helper is missing. Use View release to install this update.")
        }
        let script = transaction.appendingPathComponent("install-update.sh")
        try files.copyItem(at: bundledScript, to: script)
        let pending = PendingUpdate(target: target, version: update.version, transaction: transaction)
        try JSONEncoder().encode(pending).write(to: pendingURL, options: .atomic)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path,
                             stage.path, backup.path, transaction.path, pendingURL.path, errorURL.path]
        let log = transaction.appendingPathComponent("install.log")
        files.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        for _ in 0..<150 {
            if files.fileExists(atPath: transaction.appendingPathComponent("ready").path) { break }
            guard process.isRunning else { throw UpdateInstallError.message("The update helper couldn’t start.") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard files.fileExists(atPath: transaction.appendingPathComponent("ready").path) else {
            process.terminate()
            throw UpdateInstallError.message("The update helper didn’t become ready. Try again.")
        }
        handedOff = true
        status("Installing and restarting…")
    }

    static func validateTarget(_ target: URL) throws {
        let values = try target.resourceValues(forKeys: [.volumeIsReadOnlyKey, .isSymbolicLinkKey])
        guard target.pathExtension == "app", values.volumeIsReadOnly != true, values.isSymbolicLink != true,
              !target.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateInstallError.message("Move ChatGPT Usage to a writable Applications folder, then try Update now again.")
        }
    }

    static func validateBundle(_ url: URL, identifier: String, version: String) throws {
        let info = url.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: info)
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              values["CFBundleIdentifier"] as? String == identifier,
              values["CFBundleShortVersionString"] as? String == version,
              let executable = values["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != ".", executable != "..",
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/\(executable)").path) else {
            throw UpdateInstallError.message("The downloaded app doesn’t match this update. Nothing was installed.")
        }
    }

    static func verifyChecksumFile(_ data: Data, for asset: UpdateAsset) throws {
        guard data.count <= 4_096, let text = String(data: data, encoding: .utf8) else {
            throw UpdateInstallError.message("The update checksum file is invalid.")
        }
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, String(fields[0]).lowercased() == asset.sha256,
              String(fields[1]) == asset.name || String(fields[1]) == "*" + asset.name else {
            throw UpdateInstallError.message("The update checksums don’t match. Nothing was installed.")
        }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func download(_ asset: UpdateAsset, into directory: URL) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let guardDelegate = UpdateRedirectGuard(maximumSize: asset.size)
        let (temporary, response) = try await session.download(for: URLRequest(url: asset.downloadURL), delegate: guardDelegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, UpdateRedirectGuard.isAllowed(finalURL),
              (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == asset.size,
              try sha256(of: temporary) == asset.sha256 else {
            throw UpdateInstallError.message("The downloaded update couldn’t be verified. Nothing was installed.")
        }
        let destination = directory.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError.message("The update couldn’t be prepared. Try again or use View release.")
        }
    }
}

final class UpdateRedirectGuard: NSObject, URLSessionDownloadDelegate {
    private var redirects = 0
    private let maximumSize: Int64

    init(maximumSize: Int64) { self.maximumSize = maximumSize }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumSize || totalBytesExpectedToWrite > maximumSize {
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) { }
    static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        completionHandler(redirects <= 5 && request.url.map(Self.isAllowed) == true ? request : nil)
    }
}
