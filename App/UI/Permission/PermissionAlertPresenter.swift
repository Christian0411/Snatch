import AppKit
import os
import SnatchKit

@MainActor
final class PermissionAlertPresenter {

    init() {}

    /// Shown when the user triggers ⇧⌘6 / record while permission is denied.
    /// Returns true if the user clicked "Open System Settings".
    @discardableResult
    func showDeniedAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission required"
        alert.informativeText = """
        Snatch needs permission to capture your screen to make GIFs.

        You can grant this in System Settings → Privacy & Security → Screen Recording.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            return true
        }
        return false
    }

    /// Shown after the user grants permission via the system prompt. The
    /// process must relaunch for the new TCC state to take effect.
    func showRelaunchAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission granted"
        alert.informativeText = """
        Snatch needs to relaunch once to start recording. Click below to quit and reopen.
        """
        alert.addButton(withTitle: "Quit & Relaunch")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            relaunchSelf()
        } else {
            NSApp.terminate(nil)
        }
    }

    private func relaunchSelf() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = false
        Task { @MainActor in
            do {
                try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
            } catch {
                Log.system.error("relaunch failed: \(String(describing: error), privacy: .public)")
            }
            NSApp.terminate(nil)
        }
    }
}
