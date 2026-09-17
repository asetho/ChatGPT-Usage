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
    private var snapshotObserver: AnyCancellable?

#if DEBUG
    private var previewWindow: NSWindow?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp])
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
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)

        statusItem = item
        updateStatusItem()
        snapshotObserver = UsageStore.shared.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
    }

    private func updateStatusItem() {
        let percentage = UsageStore.shared.menuBarPercentage
        guard let button = statusItem?.button else { return }

        // Let AppKit style the title and template icon together on inactive menu bars.
        button.title = percentage
        button.toolTip = "ChatGPT weekly usage: \(percentage) remaining. Double-click to open ChatGPT."
        button.setAccessibilityLabel("ChatGPT weekly usage, \(percentage) remaining")
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            popover.performClose(sender)
            openChatGPT()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openChatGPT() {
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
