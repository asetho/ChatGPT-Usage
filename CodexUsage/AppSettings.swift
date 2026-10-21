import AppKit
import Foundation
import ServiceManagement

protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemManaging { }

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let executableKey = "codexExecutablePath"

    @Published private(set) var codexExecutablePath: String?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var loginError: String?
    @Published private(set) var executableError: String?

    private let defaults: UserDefaults
    private let loginItem: LoginItemManaging

    init(defaults: UserDefaults = .standard, loginItem: LoginItemManaging = SMAppService.mainApp) {
        self.defaults = defaults
        self.loginItem = loginItem
        codexExecutablePath = defaults.string(forKey: Self.executableKey)
        reloadLoginStatus()
    }

    func reloadLoginStatus() {
        let status = loginItem.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        reloadLoginStatus()
        do {
            if enabled && !launchAtLogin {
                try loginItem.register()
            } else if !enabled && launchAtLogin {
                try loginItem.unregister()
            }
        } catch {
            loginError = "Couldn’t change launch at login. \(error.localizedDescription)"
        }
        reloadLoginStatus()
    }

    func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @discardableResult
    func selectExecutable(at url: URL) -> Bool {
        guard let path = CodexExecutableLocator.executable(at: url) else {
            executableError = "Choose a runnable Codex executable or an app that includes Codex."
            return false
        }
        defaults.set(path, forKey: Self.executableKey)
        codexExecutablePath = path
        executableError = nil
        return true
    }

    func chooseExecutable() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex"
        panel.message = "Select the Codex executable or the ChatGPT/Codex app."
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return selectExecutable(at: url)
    }

    func useAutomaticDetection() {
        defaults.removeObject(forKey: Self.executableKey)
        codexExecutablePath = nil
        executableError = nil
    }
}
