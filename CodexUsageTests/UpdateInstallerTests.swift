import Foundation
import XCTest
@testable import CodexUsage

final class UpdateInstallerTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)

    private func release(assets: [[String: Any]]? = nil, overrides: [String: Any] = [:]) throws -> Data {
        var object: [String: Any] = [
            "tag_name": "v1.0.25",
            "html_url": "https://github.com/asetho/ChatGPT-Usage/releases/tag/v1.0.25",
            "assets": assets ?? [asset("ChatGPTUsage-1.0.25.dmg"), asset("ChatGPTUsage-1.0.25.dmg.sha256")]
        ]
        object.merge(overrides) { _, new in new }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func asset(_ name: String, overrides: [String: Any] = [:]) -> [String: Any] {
        var object: [String: Any] = [
            "name": name, "size": 90, "digest": "sha256:\(digest)",
            "browser_download_url": "https://github.com/asetho/ChatGPT-Usage/releases/download/v1.0.25/\(name)"
        ]
        object.merge(overrides) { _, new in new }
        return object
    }

    func testOffersInstallerOnlyForCompleteMatchingAssets() throws {
        let update = UpdateCheckService.availableUpdate(from: try release(), currentVersion: "1.0.24")
        XCTAssertEqual(update?.package?.installer.name, "ChatGPTUsage-1.0.25.dmg")
        XCTAssertEqual(update?.package?.installer.sha256, digest)
        XCTAssertEqual(update?.package?.checksum.name, "ChatGPTUsage-1.0.25.dmg.sha256")
    }

    func testMissingChecksumKeepsManualReleaseLink() throws {
        let update = UpdateCheckService.availableUpdate(
            from: try release(assets: [asset("ChatGPTUsage-1.0.25.dmg")]), currentVersion: "1.0.24")
        XCTAssertNotNil(update)
        XCTAssertNil(update?.package)
    }

    func testRejectsUntrustedAssetAddressesAndDigests() throws {
        let invalid: [[String: Any]] = [
            ["browser_download_url": "https://example.com/ChatGPTUsage-1.0.25.dmg"],
            ["browser_download_url": "https://github.com/other/repo/releases/download/v1.0.25/ChatGPTUsage-1.0.25.dmg"],
            ["browser_download_url": "https://github.com/asetho/ChatGPT-Usage/releases/download/v1.0.25/ChatGPTUsage-1.0.25.dmg?download=1"],
            ["browser_download_url": "https://user@github.com/asetho/ChatGPT-Usage/releases/download/v1.0.25/ChatGPTUsage-1.0.25.dmg"],
            ["digest": "sha256:bad"], ["digest": "sha256:" + String(repeating: "g", count: 64)],
            ["size": 0], ["size": 600 * 1_024 * 1_024]
        ]
        for overrides in invalid {
            let data = try release(assets: [asset("ChatGPTUsage-1.0.25.dmg", overrides: overrides), asset("ChatGPTUsage-1.0.25.dmg.sha256")])
            XCTAssertNil(UpdateCheckService.availableUpdate(from: data, currentVersion: "1.0.24")?.package, "\(overrides)")
        }
    }

    func testRejectsDuplicateAssets() throws {
        let data = try release(assets: [asset("ChatGPTUsage-1.0.25.dmg"), asset("ChatGPTUsage-1.0.25.dmg"), asset("ChatGPTUsage-1.0.25.dmg.sha256")])
        XCTAssertNil(UpdateCheckService.availableUpdate(from: data, currentVersion: "1.0.24")?.package)
    }

    func testRejectsOtherRepositoriesDraftsAndPrereleases() throws {
        for overrides: [String: Any] in [
            ["html_url": "https://github.com/other/repo/releases/tag/v1.0.25"],
            ["html_url": "https://github.com:444/asetho/ChatGPT-Usage/releases/tag/v1.0.25"],
            ["draft": true], ["prerelease": true], ["tag_name": "v+1.0.25"]
        ] {
            XCTAssertNil(UpdateCheckService.availableUpdate(from: try release(overrides: overrides), currentVersion: "1.0.24"))
        }
    }

    func testChecksumRequiresTheMatchingDigestAndFilename() throws {
        let value = UpdateAsset(name: "ChatGPTUsage-1.0.25.dmg", downloadURL: URL(string: "https://github.com")!, size: 3, digest: "sha256:\(digest)")
        XCTAssertNoThrow(try UpdateInstaller.verifyChecksumFile(Data("\(digest)  \(value.name)\n".utf8), for: value))
        XCTAssertNoThrow(try UpdateInstaller.verifyChecksumFile(Data("\(digest) *\(value.name)\n".utf8), for: value))
        for text in ["\(digest)  wrong.dmg", "\(String(repeating: "b", count: 64))  \(value.name)", "\(digest)  \(value.name)\nextra", "invalid"] {
            XCTAssertThrowsError(try UpdateInstaller.verifyChecksumFile(Data(text.utf8), for: value))
        }
    }

    func testHashesActualFileContents() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try UpdateInstaller.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testRedirectsStayOnTrustedHTTPSDownloadHosts() {
        for address in ["https://github.com/file", "https://release-assets.githubusercontent.com/file?signature=example", "https://objects.githubusercontent.com/file"] {
            XCTAssertTrue(UpdateRedirectGuard.isAllowed(URL(string: address)!))
        }
        for address in ["http://github.com/file", "https://github.com:444/file", "https://user@github.com/file", "https://github.com.example.com/file", "file:///tmp/package.dmg"] {
            XCTAssertFalse(UpdateRedirectGuard.isAllowed(URL(string: address)!))
        }
    }

    private func writeTestBundle(_ app: URL, version: String = "1.0.24") throws {
        let executable = app.appendingPathComponent("Contents/MacOS/Example")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let values = ["CFBundleIdentifier": "example.test", "CFBundleShortVersionString": version, "CFBundleExecutable": "Example"]
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
    }

    private func withPendingUpdate(_ body: (URL, URL, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Updates")
        let uuid = UUID().uuidString
        let transaction = directory.appendingPathComponent("transaction-\(uuid)")
        let target = root.appendingPathComponent("Example.app")
        let backup = root.appendingPathComponent(".ChatGPTUsage-backup-\(uuid).app")
        try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: true)
        try writeTestBundle(target)
        let pending = UpdateInstaller.PendingUpdate(target: target, version: "1.0.25", transaction: transaction)
        try JSONEncoder().encode(pending).write(to: directory.appendingPathComponent("pending.json"))
        try body(directory, target, transaction, backup)
    }

    func testAbandonedUpdateAllowsRetryAndRetainsRecoveryFiles() throws {
        try withPendingUpdate { directory, target, transaction, backup in
            try writeTestBundle(backup)
            try UpdateInstaller.reconcilePendingUpdate(in: directory, target: target, identifier: "example.test",
                                                       helperIsRunning: { _ in false })
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: transaction.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix("abandoned-") })
            XCTAssertNoThrow(try UpdateInstaller.validateBundle(target, identifier: "example.test", version: "1.0.24"))
        }
    }

    func testLiveHelperRetainsPendingStateAndAcknowledgesOnlyUpdatedLaunch() throws {
        try withPendingUpdate { directory, target, transaction, _ in
            try UpdateInstaller.reconcilePendingUpdate(in: directory, target: target, identifier: "example.test",
                                                       launchedVersion: "1.0.24", helperIsRunning: { _ in true })
            XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.appendingPathComponent("launched").path))
            try UpdateInstaller.reconcilePendingUpdate(in: directory, target: target, identifier: "example.test",
                                                       launchedVersion: "1.0.25", helperIsRunning: { _ in true })
            XCTAssertTrue(FileManager.default.fileExists(atPath: transaction.appendingPathComponent("launched").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path))
        }
    }

    func testInterruptedReplacementRestoresMissingTargetFromBackup() throws {
        try withPendingUpdate { directory, target, _, backup in
            try FileManager.default.moveItem(at: target, to: backup)
            try UpdateInstaller.reconcilePendingUpdate(in: directory, target: target, identifier: "example.test",
                                                       helperIsRunning: { _ in false })
            XCTAssertNoThrow(try UpdateInstaller.validateBundle(target, identifier: "example.test", version: "1.0.24"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path))
        }
    }

    func testMalformedPendingStateIsArchivedWithoutBlockingRetries() throws {
        try withPendingUpdate { directory, target, _, _ in
            try Data("invalid".utf8).write(to: directory.appendingPathComponent("pending.json"))
            try UpdateInstaller.reconcilePendingUpdate(in: directory, target: target, identifier: "example.test",
                                                       helperIsRunning: { _ in XCTFail("Invalid state must not inspect a helper"); return true })
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path))
            XCTAssertNoThrow(try UpdateInstaller.validateBundle(target, identifier: "example.test", version: "1.0.24"))
        }
    }

    func testHelperLivenessChecksTheTransactionAndHandlesExitedProcesses() throws {
        try withPendingUpdate { directory, target, transaction, backup in
            let script = transaction.appendingPathComponent("install-update.sh")
            let resource = try XCTUnwrap(Bundle.main.url(forResource: "install-update", withExtension: "sh"))
            try FileManager.default.copyItem(at: resource, to: script)
            let stage = target.deletingLastPathComponent().appendingPathComponent(".ChatGPTUsage-update-test.app")
            try writeTestBundle(stage, version: "1.0.25")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, stage.path,
                                 backup.path, transaction.path, directory.appendingPathComponent("pending.json").path,
                                 directory.appendingPathComponent("last-error.txt").path]
            try process.run()
            defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
            let ready = transaction.appendingPathComponent("ready")
            for _ in 0..<100 where !FileManager.default.fileExists(atPath: ready.path) { Thread.sleep(forTimeInterval: 0.05) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path))
            XCTAssertTrue(try UpdateInstaller.isHelperRunning(in: transaction))
            try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: transaction.appendingPathComponent("helper.pid"))
            XCTAssertFalse(try UpdateInstaller.isHelperRunning(in: transaction), "A reused PID must not block retries")
            try Data(String(process.processIdentifier).utf8).write(to: transaction.appendingPathComponent("helper.pid"))
            process.terminate()
            process.waitUntilExit()
            XCTAssertFalse(try UpdateInstaller.isHelperRunning(in: transaction))
        }
    }

    func testBundleIdentityVersionAndExecutableMustMatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Example.app")
        let executable = app.appendingPathComponent("Contents/MacOS/Example")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let values = ["CFBundleIdentifier": "example.test", "CFBundleShortVersionString": "1.0.25", "CFBundleExecutable": "Example"]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNoThrow(try UpdateInstaller.validateBundle(app, identifier: "example.test", version: "1.0.25"))
        XCTAssertThrowsError(try UpdateInstaller.validateBundle(app, identifier: "wrong", version: "1.0.25"))
        XCTAssertThrowsError(try UpdateInstaller.validateBundle(app, identifier: "example.test", version: "1.0.24"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: executable.path)
        XCTAssertThrowsError(try UpdateInstaller.validateBundle(app, identifier: "example.test", version: "1.0.25"))
    }
}
