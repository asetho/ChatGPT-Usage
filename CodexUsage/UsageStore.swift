import AppKit
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var isUpToDate = false
    @Published private(set) var updateCheckStatus: String?
    @Published private(set) var isInstallingUpdate = false
    @Published private(set) var updateInstallStatus: String?
    @Published private(set) var updateInstallError: String?

    private var refreshLoop: Task<Void, Never>?
    private var updateCheckLoop: Task<Void, Never>?
    private let fetchSnapshot: @MainActor () async throws -> CodexUsageSnapshot

    private static let updateCheckIntervalNanoseconds: UInt64 = 12 * 60 * 60 * 1_000_000_000

    init(fetchSnapshot: (@MainActor () async throws -> CodexUsageSnapshot)? = nil) {
        self.fetchSnapshot = fetchSnapshot ?? {
            try await CodexUsageService.fetch(executablePath: AppSettings.shared.codexExecutablePath)
        }
        updateInstallError = UpdateInstaller.takePreviousError()
    }

    var isStale: Bool {
        guard let snapshot else { return false }
        return errorMessage != nil || Date().timeIntervalSince(snapshot.fetchedAt) >= 120
    }

    var statusDescription: String {
        guard let remainingWeeklyPercent, let snapshot else { return "ChatGPT usage unavailable" }
        let freshness = isStale ? "Stale data. " : ""
        return "\(freshness)ChatGPT weekly usage: \(remainingWeeklyPercent)% remaining. Last updated \(UsageFormatters.fullDateTime.string(from: snapshot.fetchedAt))."
    }

    var remainingWeeklyPercent: Int? {
        snapshot?.codexRateLimits.weeklyWindow?.remainingPercent
    }

    var menuBarPercentage: String {
        guard let remainingWeeklyPercent else { return "--%" }
        return "\(remainingWeeklyPercent)%\(isStale ? " !" : "")"
    }

    func start() {
        guard refreshLoop == nil else { return }
        refresh()
        startUpdateChecks()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
        updateCheckLoop?.cancel()
        updateCheckLoop = nil
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard !isRefreshing else { return nil }
        isRefreshing = true

        return Task { [weak self] in
            do {
                guard let self else { return }
                let snapshot = try await self.fetchSnapshot()
                self.snapshot = snapshot
                self.errorMessage = nil
                self.isRefreshing = false
            } catch {
                guard let self else { return }
                self.errorMessage = error.localizedDescription
                self.isRefreshing = false
            }
        }
    }

    func checkForUpdatesManually() {
        guard !isCheckingForUpdates else { return }
        isUpToDate = false
        updateCheckStatus = nil
        Task { [weak self] in
            await self?.checkForUpdates(isManual: true)
        }
    }

    func clearUpdateCheckConfirmation() {
        isUpToDate = false
    }

    func installAvailableUpdate() {
        guard !isInstallingUpdate, let update = availableUpdate else { return }
        isInstallingUpdate = true
        updateInstallError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await UpdateInstaller.prepareAndLaunch(update) { self.updateInstallStatus = $0 }
                NSApplication.shared.terminate(nil)
            } catch {
                self.updateInstallError = error.localizedDescription
                self.updateInstallStatus = nil
                self.isInstallingUpdate = false
            }
        }
    }

    private func startUpdateChecks() {
        guard updateCheckLoop == nil else { return }

        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"

        updateCheckLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdates(currentVersion: currentVersion, isManual: false)

                do {
                    try await Task.sleep(nanoseconds: Self.updateCheckIntervalNanoseconds)
                } catch {
                    break
                }
            }
        }
    }


    private func checkForUpdates(
        currentVersion: String? = nil,
        isManual: Bool
    ) async {
        guard !isCheckingForUpdates, !isInstallingUpdate else { return }
        isCheckingForUpdates = true
        isUpToDate = false
        defer { isCheckingForUpdates = false }

        let installedVersion = currentVersion ?? (Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0")

        do {
            let update = try await UpdateCheckService.fetchAvailableUpdate(
                currentVersion: installedVersion
            )
            guard !Task.isCancelled, !isInstallingUpdate else { return }
            availableUpdate = update
            if isManual {
                isUpToDate = update == nil
                updateCheckStatus = update.map { "Version \($0.version) is available." }
            }
        } catch {
            if isManual {
                updateCheckStatus = "Unable to check for updates right now."
            }
            // Automatic update checks never interfere with usage refreshes.
        }
    }
}
