// Sources/SnatchCropperCLI/AppDelegate.swift
import AppKit
import SnatchKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Wired up in Tasks 9–13.
    private var cropperWindow: NSWindow?
    private let regionStore = RegionStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else {
            // No screens means we can't show a cropper. Bail.
            Self.emitCancelledAndExit()
            return
        }

        let initialViewLocal = regionStore.lastRegion.map { region -> CGRect in
            CGRect(
                x: region.origin.x - screen.frame.origin.x,
                y: region.origin.y - screen.frame.origin.y,
                width: region.size.width,
                height: region.size.height
            )
        }
        let w = CropperWindow(screen: screen, initialRegion: initialViewLocal)
        self.cropperWindow = w
        w.makeKeyAndOrderFront(nil)
        // Mouse / keyboard handlers are wired up in Tasks 11–13.
    }

    // Called by the cropper view in Task 13 / 14.
    func cropperRecordRequested(region: CGRect) {
        regionStore.persist(region)
        let x = Int(region.origin.x.rounded())
        let y = Int(region.origin.y.rounded())
        let w = Int(region.size.width.rounded())
        let h = Int(region.size.height.rounded())
        print("RECORD region=(\(x),\(y),\(w),\(h))")
        NSApplication.shared.terminate(nil)
    }

    // Called by the cropper view in Task 13.
    func cropperCancelled() {
        Self.emitCancelledAndExit()
    }

    private static func emitCancelledAndExit() {
        print("CANCELLED")
        NSApplication.shared.terminate(nil)
    }
}
