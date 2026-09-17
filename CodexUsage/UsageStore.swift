import Foundation

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var updateCheckStatus: String?

    private var refreshLoop: Task<Void, Never>?
    private var updateCheckLoop: Task<Void, Never>?

    private static let updateCheckIntervalNanoseconds: UInt64 = 12 * 60 * 60 * 1_000_000_000

    var remainingWeeklyPercent: Int? {
        snapshot?.codexRateLimits.weeklyWindow?.remainingPercent
    }

    var menuBarPercentage: String {
        guard let remainingWeeklyPercent else { return "--%" }
        return "\(remainingWeeklyPercent)%"
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

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task { [weak self] in
            do {
                let snapshot = try await CodexUsageService.fetch()
                guard let self else { return }
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
        updateCheckStatus = "Checking for updates…"
        Task { [weak self] in
            await self?.checkForUpdates(isManual: true)
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
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        let installedVersion = currentVersion ?? (Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0")

        do {
            let update = try await UpdateCheckService.fetchAvailableUpdate(
                currentVersion: installedVersion
            )
            guard !Task.isCancelled else { return }
            availableUpdate = update
            if isManual {
                updateCheckStatus = update.map { "Version \($0.version) is available." }
                    ?? "You’re up to date."
            }
        } catch {
            if isManual {
                updateCheckStatus = "Unable to check for updates right now."
            }
            // Automatic update checks never interfere with usage refreshes.
        }
    }
}
