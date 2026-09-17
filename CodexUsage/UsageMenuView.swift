import AppKit
import SwiftUI

struct UsageMenuView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var isShowingAbout = false

    private let usageDashboardURL = URL(string: "https://chatgpt.com/codex/settings/usage")!

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
            Button("Try Again") { store.refresh() }
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
        Button {
            NSWorkspace.shared.open(update.releaseURL)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available")
                        .font(.callout.weight(.semibold))
                    Text("Version \(update.version) · View release")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Update available, version \(update.version)")
        .accessibilityHint("Opens the GitHub release page")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: { store.refresh() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)

            if let fetchedAt = store.snapshot?.fetchedAt {
                Text(fetchedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
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
                Link("View version \(update.version)", destination: update.releaseURL)
                    .font(.caption)
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
