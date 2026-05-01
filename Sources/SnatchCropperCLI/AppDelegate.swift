// Sources/SnatchCropperCLI/AppDelegate.swift
import AppKit
import SnatchKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Wired up in Tasks 9–13.
    private var cropperWindow: NSWindow?
    private let regionStore = RegionStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cropper window construction lands in Task 9.
        // For now we exit immediately so the SPM target builds and runs end-
        // to-end without a hang, proving the wiring.
        Self.emitCancelledAndExit()
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
