import AppKit
import SwiftUI

struct UsageMenuView: View {
    @EnvironmentObject private var store: UsageStore
    @ObservedObject private var settings = AppSettings.shared
    @State private var isShowingAbout = false
    @State private var isShowingSettings = false

    private let usageDashboardURL = URL(string: "https://chatgpt.com/settings/usage?tab=overview")!

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let snapshot = store.snapshot {
                usageContent(snapshot)
            } else if store.isRefreshing {
                loadingContent
            } else {
                unavailableContent
            }

            if let error = store.errorMessage, store.snapshot != nil {
                Divider()
                errorBanner(error)
            }

            if let update = store.availableUpdate {
                Divider()
                updateBanner(update)
            }

            Divider()
            footer
        }
        .frame(width: 280)
        .background {
            ZStack {
                ActiveDarkGlassBackground()
                Color.black.opacity(0.58)
            }
        }
        .preferredColorScheme(.dark)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Usage remaining")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                isShowingAbout = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .help("About ChatGPT Usage")
            .accessibilityLabel("About ChatGPT Usage")
            .popover(isPresented: $isShowingAbout, arrowEdge: .top) {
                AboutView()
                    .environmentObject(store)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func usageContent(_ snapshot: CodexUsageSnapshot) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                UsageWindowRow(
                    title: "Weekly",
                    window: snapshot.codexRateLimits.weeklyWindow,
                    showsFullResetDate: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if snapshot.codexRateLimits.rateLimitReachedType != nil {
                statusWarning
            }

            Button(action: openUsageDashboard) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(manageUsageTitle(snapshot))
                        if let expiration = resetExpirationTitle(snapshot) {
                            Text(expiration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if !snapshot.additionalRateLimits.isEmpty || snapshot.accountUsage != nil {
                Divider()

                VStack(spacing: 8) {
                    if !snapshot.additionalRateLimits.isEmpty {
                        ExpandableSection("Additional limits") {
                            VStack(spacing: 8) {
                                ForEach(snapshot.additionalRateLimits) { limit in
                                    AdditionalLimitView(limit: limit)
                                }
                            }
                        }
                    }

                    if let usage = snapshot.accountUsage {
                        ExpandableSection("Token usage") {
                            VStack(spacing: 7) {
                                DetailRow(title: "Today", value: UsageFormatters.tokenCount(snapshot.todayTokens))
                                DetailRow(title: "Lifetime", value: UsageFormatters.tokenCount(usage.summary.lifetimeTokens))
                                if let streak = usage.summary.currentStreakDays {
                                    DetailRow(title: "Current streak", value: "\(streak) days")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Reading usage from ChatGPT…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Usage unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(store.errorMessage ?? "ChatGPT has not returned usage data yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Try Again") { store.refresh() }
                Button("Choose Codex…") {
                    if settings.chooseExecutable() { store.refresh() }
                }
            }
            if let error = settings.executableError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var statusWarning: some View {
        Label("A usage limit has been reached.", systemImage: "exclamationmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Showing the last update. \(message)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private func updateBanner(_ update: AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isInstallingUpdate ? "Updating…" : "Update available")
                        .font(.callout.weight(.semibold))
                    Text(store.updateInstallStatus ?? "Version \(update.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if store.isInstallingUpdate { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 14) {
                if update.package != nil {
                    Button("Update now") { store.installAvailableUpdate() }
                        .disabled(store.isInstallingUpdate)
                        .accessibilityHint("Downloads the update, installs it, and reopens the app")
                }
                Link("View release", destination: update.releaseURL)
            }.font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.updateInstallError {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fetchedAt = store.snapshot?.fetchedAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(spacing: 3) {
                        if store.isStale {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        Text("\(store.isStale ? "Stale · updated" : "Updated") \(UsageFormatters.updateAgeLabel(fetchedAt, now: context.date))")
                    }
                    .foregroundStyle(store.isStale ? .orange : .secondary)
                    .lineLimit(1)
                    .help("Last successful update: \(UsageFormatters.fullDateTime.string(from: fetchedAt))")
                }
            }

            HStack(spacing: 14) {
                Button(action: { store.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)

                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .popover(isPresented: $isShowingSettings) {
                    UsageSettingsView(settings: settings, store: store)
                }

                Spacer()

                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func manageUsageTitle(_ snapshot: CodexUsageSnapshot) -> String {
        if let count = snapshot.rateLimitResetCredits?.availableCount, count > 0 {
            return count == 1 ? "1 reset available" : "\(count) resets available"
        }

        let limit = snapshot.codexRateLimits
        guard let credits = limit.credits else { return "Open ChatGPT Usage" }
        if credits.unlimited { return "Unlimited credits" }
        if credits.hasCredits, let balance = credits.balance {
            return "\(balance) credits available"
        }
        return "Manage resets & credits"
    }

    private func resetExpirationTitle(_ snapshot: CodexUsageSnapshot) -> String? {
        guard let expiration = snapshot.rateLimitResetCredits?.nextExpiration else { return nil }
        return "Expires \(UsageFormatters.fullResetLabel(expiration))"
    }

    private func openUsageDashboard() {
        NSWorkspace.shared.open(usageDashboardURL)
    }
}

struct UsageSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.headline)

            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)

            if settings.loginNeedsApproval {
                Text("Allow ChatGPT Usage in Login Items to finish enabling launch at login.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = settings.loginError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if settings.loginNeedsApproval || settings.loginError != nil {
                Button("Open Login Items") { settings.openLoginSettings() }
            }

            Divider()

            Text("Codex").font(.subheadline.weight(.semibold))
            Text(settings.codexExecutablePath == nil ? "Automatic detection" : "Selected executable")
                .font(.caption).foregroundStyle(.secondary)
            Text(settings.codexExecutablePath ?? CodexExecutableLocator.find() ?? "Codex was not found.")
                .font(.caption).textSelection(.enabled)
                .lineLimit(3).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Choose…") {
                    if settings.chooseExecutable() { store.refresh() }
                }
                if settings.codexExecutablePath != nil {
                    Button("Use Automatic") {
                        settings.useAutomaticDetection()
                        store.refresh()
                    }
                }
            }
            if let error = settings.executableError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .preferredColorScheme(.dark)
        .onAppear { settings.reloadLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.reloadLoginStatus()
        }
    }
}

private struct ExpandableSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = false

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 13))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides details")

            if isExpanded {
                content()
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActiveDarkGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
    }
}

private struct UsageWindowRow: View {
    let title: String
    let window: RateLimitWindow?
    var showsFullResetDate = false
    var fontSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                if let window {
                    if !showsFullResetDate {
                        Text(UsageFormatters.resetLabel(window.resetsAt))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                    Text("\(window.remainingPercent)%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }

            if showsFullResetDate, let resetsAt = window?.resetsAt {
                Text("Resets \(UsageFormatters.fullResetLabel(resetsAt))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: fontSize))
    }
}

private struct AdditionalLimitView: View {
    let limit: RateLimitSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(limit.displayName)
                if limit.isLunaReserve {
                    Link(destination: URL(string: "https://help-lb.openai.com/en/articles/20001499-luna-reserve-in-codex-and-chatgpt-work")!) {
                        Image(systemName: "questionmark.circle")
                    }
                    .help("Read the Luna Reserve guide")
                    .accessibilityLabel("Read the Luna Reserve guide")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let fiveHourWindow = limit.fiveHourWindow {
                UsageWindowRow(title: "5h", window: fiveHourWindow, fontSize: 14)
            }
            if let weeklyWindow = limit.weeklyWindow {
                UsageWindowRow(
                    title: "Weekly",
                    window: weeklyWindow,
                    showsFullResetDate: true,
                    fontSize: 14
                )
            }
        }
    }
}

private struct AboutView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.dismiss) private var dismiss

    private let repositoryURL = URL(string: "https://github.com/asetho/ChatGPT-Usage")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 3) {
                Text("ChatGPT Usage")
                    .font(.title2.weight(.semibold))
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
                Text("© 2026 asetho™")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                store.checkForUpdatesManually()
            } label: {
                Label("Check for Updates", systemImage: "arrow.clockwise")
            }
            .disabled(store.isCheckingForUpdates)

            if let status = store.updateCheckStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let update = store.availableUpdate {
                HStack {
                    if update.package != nil {
                        Button(store.isInstallingUpdate ? "Updating…" : "Update now") { store.installAvailableUpdate() }
                            .disabled(store.isInstallingUpdate)
                    }
                    Link("View version \(update.version)", destination: update.releaseURL)
                }.font(.caption)
            }
            if let error = store.updateInstallError {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.isInstallingUpdate, let status = store.updateInstallStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            Link(destination: repositoryURL) {
                Image("GitHubMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open ChatGPT Usage on GitHub")
            .accessibilityLabel("Open ChatGPT Usage on GitHub")

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360)
        .preferredColorScheme(.dark)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 13))
    }
}
