import AppKit
import Combine
import os
import SnatchKit
import SnatchAppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Component graph (allocated in applicationDidFinishLaunching).
    private var pipeline: ScreenRecordingPipeline!
    private var session: RecordingSession!
    private var regionStore: RegionStore!
    private var scaleStore: ScalePresetStore!
    private var recentsStore: RecentRecordingsStore!
    private var permissions: PermissionsCoordinator!
    private var pasteboard: PasteboardWriter!
    private var notifier: NotificationPresenter!
    private var pathProvider: PathProvider!
    private var shareableContent: ShareableContentCache!
    private var hotkeys: HotkeyRegistrar!
    private var cropperWindow: CropperWindow!
    private var recordingOverlay: RecordingOverlayWindow!
    private var coordinator: MenubarCoordinator!

    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem!  // placeholder; Task 19 replaces with MenubarController

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1) Sync sweep of partial files (spec §4 step 2)
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        PartialFileSweeper.sweep(directory: desktop)

        // 2) Component graph (spec §4 step 3)
        regionStore      = RegionStore()
        scaleStore       = ScalePresetStore()
        recentsStore     = RecentRecordingsStore()
        permissions      = PermissionsCoordinator()
        pasteboard       = PasteboardWriter()
        notifier         = NotificationPresenter()
        pathProvider     = PathProvider()
        pipeline         = ScreenRecordingPipeline()
        session          = RecordingSession(pipeline: pipeline, regionStore: regionStore)
        shareableContent = ShareableContentCache()
        cropperWindow    = makeHiddenCropperWindow()
        recordingOverlay = makeHiddenRecordingOverlay()

        _ = permissions.preflight()

        coordinator = MenubarCoordinator(
            session: session,
            cropperWindow: cropperWindow,
            recordingOverlay: recordingOverlay,
            regionStore: regionStore,
            scaleStore: scaleStore,
            recentsStore: recentsStore,
            permissions: permissions,
            pasteboard: pasteboard,
            notifier: notifier,
            pathProvider: pathProvider,
            shareableContent: shareableContent
        )

        hotkeys = HotkeyRegistrar(handler: { [weak coordinator] in
            coordinator?.handleHotkey()
        })
        hotkeys.registerGlobal()

        // 3) Placeholder NSStatusItem so the user sees launch happened
        // (real MenubarController arrives in Task 19).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                            accessibilityDescription: "Snatch")

        // 4) Async pre-warm
        Task.detached { [shareableContent] in
            await shareableContent?.refresh()
        }

        // 5) Notification authorization (best-effort)
        Task { await self.notifier.requestAuthorizationIfNeeded() }

        // 6) OS notification subscriptions
        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)

        Log.system.info("Snatch launched (sweep + graph + hotkey done)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys?.unregisterAll()
        Task { await session?.cancel() }
    }

    @objc private func displaysChanged() {
        Task { await shareableContent?.refresh() }
    }

    @objc private func workspaceActivated() {
        Task { await shareableContent?.refresh() }
    }

    @objc private func appBecameActive() {
        permissions?.observeRevocation()
    }

    private func makeHiddenCropperWindow() -> CropperWindow {
        // CropperWindow.init takes (screen: NSScreen, initialRegion: CGRect?).
        // Use main screen (or first available). The window will be resized and
        // reconfigured by MenubarCoordinator when actually shown (Task 17).
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let win = CropperWindow(screen: screen, initialRegion: nil)
        return win
    }

    private func makeHiddenRecordingOverlay() -> RecordingOverlayWindow {
        // RecordingOverlayWindow is a coordinator (not an NSWindow subclass).
        // Its init takes (regionInScreenCoords: CGRect). Pass .zero as a
        // placeholder; MenubarCoordinator will tear this down and create a new
        // one with the real region when recording begins (Task 17).
        let overlay = RecordingOverlayWindow(regionInScreenCoords: .zero)
        return overlay
    }
}
