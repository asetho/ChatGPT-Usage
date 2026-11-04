import AppKit
import Combine
import SwiftUI

@main
struct CodexUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let statusFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var statusObservers = Set<AnyCancellable>()

#if DEBUG
    private var previewWindow: NSWindow?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdateInstaller.recordSuccessfulLaunch()
        ProcessInfo.processInfo.disableAutomaticTermination("ChatGPT Usage runs in the menu bar")
#if DEBUG
        if ProcessInfo.processInfo.environment["CODEX_USAGE_PREVIEW"] == "1" {
            showPreviewWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
            configureStatusItem()
        }
#else
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
#endif
        UsageStore.shared.start()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
                UsageStore.shared.refresh()
            }
            .store(in: &statusObservers)
    }

    func applicationWillTerminate(_ notification: Notification) {
        UsageStore.shared.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = []
        item.isVisible = true

        guard let button = item.button else { return }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            item.expandedInterfaceDelegate = self
        } else {
            configureLegacyClick(button)
        }
        #else
        configureLegacyClick(button)
        #endif
        button.font = Self.statusFont
        let icon = loadChatGPTMenuBarIcon()?.copy() as? NSImage
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true

        let controller = NSHostingController(
            rootView: UsageMenuView().environmentObject(UsageStore.shared)
        )
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        statusItem = item
        updateStatusItem()
        UsageStore.shared.$snapshot.combineLatest(UsageStore.shared.$errorMessage)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &statusObservers)
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &statusObservers)
    }

    private func updateStatusItem() {
        let percentage = UsageStore.shared.menuBarPercentage
        guard let button = statusItem?.button else { return }

        // Let AppKit style the title and template icon together on inactive menu bars.
        button.title = percentage
        if let cell = button.cell {
            let bounds = NSRect(origin: .zero, size: NSSize(width: cell.cellSize.width, height: button.bounds.height))
            var contentBounds = cell.titleRect(forBounds: bounds)
            if button.image != nil {
                contentBounds = contentBounds.union(cell.imageRect(forBounds: bounds))
            }
            // Fit the drawn content without the status item's extra side margins.
            statusItem?.length = ceil(contentBounds.width)
        }
        button.toolTip = UsageStore.shared.statusDescription
        button.setAccessibilityLabel(UsageStore.shared.statusDescription)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(from: sender)
        }
    }

    private func configureLegacyClick(_ button: NSStatusBarButton) {
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    private func showPopover(from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    static func openChatGPT() {
        let webFallback = URL(string: "https://chatgpt.com")!
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            NSWorkspace.shared.open(webFallback)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        ) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.open(webFallback)
            }
        }
    }

    private func loadChatGPTMenuBarIcon() -> NSImage? {
        guard let image = NSImage(named: "ChatGPTMenuBarIcon") else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "ChatGPT"
        return image
    }

#if DEBUG
    private func showPreviewWindow() {
        NSApp.setActivationPolicy(.regular)
        let rootView = UsageMenuView().environmentObject(UsageStore.shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ChatGPT Usage Preview"
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
#endif
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            statusItem?.expandedInterfaceSession?.cancel()
        }
        #endif
    }
}

#if compiler(>=6.4)
@available(macOS 27.0, *)
extension AppDelegate: NSStatusItemExpandedInterfaceDelegate {
    nonisolated func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        MainActor.assumeIsolated {
            guard let button = statusItem.button else { return }
            showPopover(from: button)
        }
    }

    nonisolated func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        MainActor.assumeIsolated {
            popover.close()
        }
    }
}
#endif
