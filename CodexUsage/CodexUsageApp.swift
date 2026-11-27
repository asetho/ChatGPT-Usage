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
            rootView: UsageMenuView(store: UsageStore.shared)
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
        let creditsMayBeUsed = UsageStore.shared.creditsMayBeUsed
        guard let button = statusItem?.button else { return }

        // Let AppKit style the title and template icon together on inactive menu bars.
        button.title = creditsMayBeUsed ? "" : percentage
        if creditsMayBeUsed {
            let coin = NSTextAttachment()
            coin.image = Self.creditWarningImage
            coin.bounds = NSRect(x: 0, y: 0, width: 14, height: 14)
            button.attributedTitle = NSAttributedString(attachment: coin)
        }
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

    private static let creditWarningImage = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.labelColor.setStroke()
        let face = NSBezierPath(ovalIn: NSRect(x: 0.9, y: 0.846, width: 9.864, height: 16.308))
        face.lineWidth = 1.25
        face.stroke()

        // Rounded side-on rim scaled from the bundled coin SVG to the status bar.
        let rim = NSBezierPath()
        rim.move(to: NSPoint(x: 5.814, y: 17.154))
        rim.line(to: NSPoint(x: 11.1, y: 17.154))
        rim.curve(to: NSPoint(x: 16.14225, y: 9), controlPoint1: NSPoint(x: 13.875, y: 17.154),
                  controlPoint2: NSPoint(x: 16.14225, y: 13.8))
        rim.curve(to: NSPoint(x: 11.1, y: 0.846), controlPoint1: NSPoint(x: 16.14225, y: 4.2),
                  controlPoint2: NSPoint(x: 13.875, y: 0.846))
        rim.line(to: NSPoint(x: 5.814, y: 0.846))
        rim.move(to: NSPoint(x: 10.386, y: 12.15))
        rim.line(to: NSPoint(x: 15.675, y: 12.15))
        rim.move(to: NSPoint(x: 15.675, y: 6.237))
        rim.line(to: NSPoint(x: 10.566, y: 6.237))
        rim.lineWidth = 1.25
        rim.lineCapStyle = .round
        rim.stroke()

        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 10.5, y: 0.5, width: 7.5, height: 7.5)).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 13.75, y: 3.7, width: 1, height: 2.8), xRadius: 0.5, yRadius: 0.5).fill()
        NSBezierPath(ovalIn: NSRect(x: 13.75, y: 2, width: 1, height: 1)).fill()
        return true
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
        if let controller = popover.contentViewController as? NSHostingController<UsageMenuView> {
            let pointer = NSEvent.mouseLocation
            let screen = button.window?.screen
                ?? NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main
            let height = usageMenuHeightLimit(on: screen)
            if controller.rootView.maximumHeight != height {
                controller.rootView.maximumHeight = height
            }
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func usageMenuHeightLimit(on screen: NSScreen?) -> CGFloat? {
        // Leave room for the popover arrow and space at the bottom of the display.
        screen.map { max(0, $0.visibleFrame.height - 24) }
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
        let rootView = UsageMenuView(store: UsageStore.shared, maximumHeight: usageMenuHeightLimit(on: NSScreen.main))
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
