import AppKit
import Darwin
import Foundation

enum CodexUsageError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case timedOut
    case invalidResponse
    case server(String)
    case processExited(Int32, String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex was not found. Install Codex and sign in to ChatGPT, or choose an existing Codex executable in Settings."
        case .launchFailed(let message):
            return "Could not start Codex: \(message)"
        case .timedOut:
            return "Codex took too long to return usage data."
        case .invalidResponse:
            return "Codex returned usage data in an unexpected format."
        case .server(let message):
            return message
        case .processExited(let status, let detail):
            let suffix = detail.isEmpty ? "" : ": \(detail)"
            return "Codex stopped unexpectedly (\(status))\(suffix)"
        }
    }
}

struct CodexUsageService {
    static func fetch(
        timeout: TimeInterval = 15,
        executablePath: String? = nil,
        optionalUsageTimeout: TimeInterval = 2
    ) async throws -> CodexUsageSnapshot {
        try await Task.detached(priority: .utility) {
            try CodexUsageProbe(
                timeout: timeout,
                executablePath: executablePath,
                optionalUsageTimeout: optionalUsageTimeout
            ).fetch()
        }.value
    }
}

struct CodexExecutableLocator {
    static let bundledExecutablePaths = [
        "Contents/Resources/codex-cli/bin/codex",
        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "Contents/Resources/codex"
    ]

    static func executable(at url: URL) -> String? {
        let candidates = url.pathExtension.lowercased() == "app"
            ? bundledExecutablePaths.map { url.appendingPathComponent($0).path }
            : [url.path]
        return candidates.first { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && FileManager.default.isExecutableFile(atPath: path)
        }
    }

    static func find(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        applicationURLs: [URL]? = nil,
        standardPaths: [String]? = nil
    ) -> String? {
        let applications = applicationURLs ?? (
            [NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")]
                .compactMap { $0 }
            + ["/Applications/ChatGPT.app", "/Applications/Codex.app",
               "\(home)/Applications/ChatGPT.app", "\(home)/Applications/Codex.app"]
                .map { URL(fileURLWithPath: $0) }
        )
        let candidates = [environment["CODEX_EXECUTABLE"]].compactMap { $0 }
            + applications.map(\.path) + (standardPaths ?? [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex"
        ]) + (environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }
            .map { "\($0)/codex" }

        return candidates.lazy.compactMap { executable(at: URL(fileURLWithPath: $0)) }.first
    }
}

private final class CodexUsageProbe: @unchecked Sendable {
    private static let ignoreBrokenPipeSignal: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    private let timeout: TimeInterval
    private let executablePath: String?
    private let optionalUsageTimeout: TimeInterval
    private let decoder = JSONDecoder()
    private let process = Process()
    private let standardInput = Pipe()
    private let standardOutput = Pipe()
    private let standardError = Pipe()
    private let queue = DispatchQueue(label: "com.aaronwhippo.CodexUsage.probe")
    private let finished = DispatchSemaphore(value: 0)

    // Access to the following state is serialized by queue.
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var limitsResponse: RateLimitsResponse?
    private var usageResponse: AccountUsageResponse?
    private var usageFinished = false
    private var resultError: Error?
    private var didFinish = false

    init(timeout: TimeInterval, executablePath: String?, optionalUsageTimeout: TimeInterval) {
        self.timeout = timeout
        self.executablePath = executablePath
        self.optionalUsageTimeout = optionalUsageTimeout
    }

    func fetch() throws -> CodexUsageSnapshot {
        _ = Self.ignoreBrokenPipeSignal

        guard let executable = executablePath ?? CodexExecutableLocator.find() else {
            throw CodexUsageError.codexNotFound
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        var environment = ProcessInfo.processInfo.environment
        let requiredPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = environment["PATH"], !existing.isEmpty {
            environment["PATH"] = requiredPath + ":" + existing
        } else {
            environment["PATH"] = requiredPath
        }
        process.environment = environment

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self.queue.async {
                self.outputBuffer.append(data)
                self.consumeOutput()
            }
        }

        standardError.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self.queue.async {
                if self.errorBuffer.count < 8_192 {
                    self.errorBuffer.append(data.prefix(8_192 - self.errorBuffer.count))
                }
            }
        }

        process.terminationHandler = { terminated in
            self.queue.async {
                guard !self.didFinish else { return }
                let detail = String(data: self.errorBuffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.complete(self.limitsResponse == nil
                    ? CodexUsageError.processExited(terminated.terminationStatus, detail) : nil)
            }
        }

        do {
            try process.run()
        } catch {
            stopProcess()
            throw CodexUsageError.launchFailed(error.localizedDescription)
        }

        queue.async {
            self.send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex_usage_menu",
                        "title": "Codex Usage",
                        "version": "1.0.0"
                    ],
                    "capabilities": ["experimentalApi": true]
                ]
            ])
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            queue.sync {
                if !self.didFinish {
                    self.didFinish = true
                    self.resultError = self.limitsResponse == nil ? CodexUsageError.timedOut : nil
                }
            }
        }

        stopProcess()
        let result = queue.sync {
            (resultError, limitsResponse, usageResponse)
        }

        if let resultError = result.0 {
            throw resultError
        }
        guard let limitsResponse = result.1 else {
            throw CodexUsageError.invalidResponse
        }

        var buckets = limitsResponse.rateLimitsByLimitId ?? [:]
        if buckets.isEmpty {
            buckets[limitsResponse.rateLimits.limitId ?? "codex"] = limitsResponse.rateLimits
        }

        return CodexUsageSnapshot(
            defaultRateLimits: limitsResponse.rateLimits,
            rateLimitsById: buckets,
            rateLimitResetCredits: limitsResponse.rateLimitResetCredits,
            accountUsage: result.2,
            fetchedAt: Date()
        )
    }

    private func complete(_ error: Error? = nil) {
        guard !didFinish else { return }
        didFinish = true
        resultError = error
        finished.signal()
    }

    private func send(_ object: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try standardInput.fileHandleForWriting.write(contentsOf: data)
        } catch {
            complete(error)
        }
    }

    private func maybeComplete() {
        if limitsResponse != nil && usageFinished {
            complete()
        }
    }

    private func handleResponse(_ object: [String: Any]) {
        guard !didFinish else { return }
        guard let id = (object["id"] as? NSNumber)?.intValue else { return }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex could not read usage data."
            if id == 4 {
                usageFinished = true
                maybeComplete()
            } else {
                complete(CodexUsageError.server(message))
            }
            return
        }

        guard let result = object["result"] else { return }

        if id == 1 {
            send(["method": "initialized"])
            send(["id": 3, "method": "account/rateLimits/read"])
            send(["id": 4, "method": "account/usage/read"])
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: result)
            switch id {
            case 3:
                limitsResponse = try decoder.decode(RateLimitsResponse.self, from: data)
                // Token statistics are optional; do not let a stalled endpoint hide quota data.
                queue.asyncAfter(deadline: .now() + optionalUsageTimeout) { [weak self] in
                    self?.complete()
                }
            case 4:
                usageResponse = try decoder.decode(AccountUsageResponse.self, from: data)
                usageFinished = true
            default:
                break
            }
            maybeComplete()
        } catch {
            if id == 4 {
                usageFinished = true
                maybeComplete()
            } else {
                complete(CodexUsageError.invalidResponse)
            }
        }
    }

    private func consumeOutput() {
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                continue
            }
            handleResponse(object)
        }
    }

    private func stopProcess() {
        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? standardInput.fileHandleForWriting.close()

        if process.isRunning {
            process.terminate()
        }
    }
}
