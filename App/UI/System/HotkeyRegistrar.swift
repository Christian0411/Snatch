import AppKit
import Carbon.HIToolbox
import SnatchKit

/// Carbon-based global hotkey registration. ⇧⌘6 always; Esc dynamically
/// during recording. Real implementation lands in Task 20.
@MainActor
final class HotkeyRegistrar {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func registerGlobal() {
        // Task 20.
    }

    func registerEsc() {
        // Task 20.
    }

    func unregisterEsc() {
        // Task 20.
    }

    func unregisterAll() {
        // Task 20.
    }
}
