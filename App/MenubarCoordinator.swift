import AppKit
import Combine
import os
import SnatchKit
import SnatchAppKit

/// Mediates between the RecordingSession state machine and the AppKit
/// shells. Owns no business logic — just plumbing. Subsequent tasks
/// flesh out the show/hide and permission paths.
@MainActor
final class MenubarCoordinator {

    let session: RecordingSession
    let cropperWindow: CropperWindow
    var recordingOverlay: RecordingOverlayWindow
    let regionStore: RegionStore
    let scaleStore: ScalePresetStore
    let rememberRegionStore: RememberRegionPreferenceStore
    let autoStartStore: AutoStartRecordingPreferenceStore
    let recentsStore: RecentRecordingsStore
    let permissions: PermissionsCoordinator
    let permissionAlerts: PermissionAlertPresenter
    let pasteboard: PasteboardWriter
    let notifier: NotificationPresenter
    let pathProvider: PathProvider
    let shareableContent: ShareableContentCache

    private var cancellables = Set<AnyCancellable>()
    private var lastCroppedRegion: CGRect = .zero
    private weak var hotkeyRegistrar: HotkeyRegistrar?

    init(session: RecordingSession,
         cropperWindow: CropperWindow,
         recordingOverlay: RecordingOverlayWindow,
         regionStore: RegionStore,
         scaleStore: ScalePresetStore,
         rememberRegionStore: RememberRegionPreferenceStore,
         autoStartStore: AutoStartRecordingPreferenceStore,
         recentsStore: RecentRecordingsStore,
         permissions: PermissionsCoordinator,
         pasteboard: PasteboardWriter,
         notifier: NotificationPresenter,
         pathProvider: PathProvider,
         shareableContent: ShareableContentCache) {
        self.session = session
        self.cropperWindow = cropperWindow
        self.recordingOverlay = recordingOverlay
        self.regionStore = regionStore
        self.scaleStore = scaleStore
        self.rememberRegionStore = rememberRegionStore
        self.autoStartStore = autoStartStore
        self.recentsStore = recentsStore
        self.permissions = permissions
        self.permissionAlerts = PermissionAlertPresenter()
        self.pasteboard = pasteboard
        self.notifier = notifier
        self.pathProvider = pathProvider
        self.shareableContent = shareableContent

        installSubscriptions()
        installCropperCallbacks()
        installRecordingOverlayCallback()
    }

    func handleHotkey() {
        if permissions.cachedState == .denied {
            permissionAlerts.showDeniedAlert()
            return
        }
        if permissions.cachedState == .notDetermined {
            Task { @MainActor in
                let result = await permissions.request()
                switch result {
                case .granted:        self.permissionAlerts.showRelaunchAlert()
                case .denied:         self.permissionAlerts.showDeniedAlert()
                case .notDetermined:  self.permissionAlerts.showDeniedAlert()  // dismissed prompt
                }
            }
            return
        }
        // Permission OK — route by session state:
        Task { @MainActor in
            switch session.state {
            case .idle:                           session.beginCropping()
            case .cropping:                       session.cancelCropping()
            case .recording:                      await self.requestStop()
            case .finalizing, .cancelling:        break
            }
        }
    }

    func handleEscDuringRecording() {
        Task { @MainActor in
            await session.cancel()
        }
    }

    func attach(hotkeyRegistrar: HotkeyRegistrar) {
        self.hotkeyRegistrar = hotkeyRegistrar
    }

    private func installSubscriptions() {
        session.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.handleStateChange(newState)
                self?.updateEscHotkey(for: newState)
            }
            .store(in: &cancellables)
    }

    private func updateEscHotkey(for state: RecordingSession.State) {
        guard let hotkeyRegistrar else { return }
        if state == .recording {
            hotkeyRegistrar.registerEsc()
        } else {
            hotkeyRegistrar.unregisterEsc()
        }
    }

    private func handleStateChange(_ state: RecordingSession.State) {
        switch state {
        case .cropping:
            showCropper()
        case .recording:
            // Overlay + cropper hide were already done in handleRecordRequested,
            // before session.start. Nothing else to do here.
            break
        case .finalizing, .cancelling:
            recordingOverlay.orderOut(nil)
        case .idle:
            cropperWindow.orderOut(nil)
            recordingOverlay.orderOut(nil)
        }
    }

    private func showCropper() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main!

        // Resize the window to fill the target screen.
        cropperWindow.setFrame(screen.frame, display: false)

        // Pre-draw the last region in view-local coordinates.
        // CropperView uses a flipped coordinate system with origin at the
        // window's top-left. screen.frame.origin must be subtracted to convert
        // from screen-space (CG) to view-local coords.
        if rememberRegionStore.isEnabled, let last = regionStore.lastRegion {
            let viewLocal = CGRect(
                x: last.origin.x - screen.frame.origin.x,
                y: last.origin.y - screen.frame.origin.y,
                width: last.width,
                height: last.height
            )
            cropperWindow.cropperView.state = CropperState(initial: viewLocal)
        } else {
            cropperWindow.cropperView.state = CropperState(initial: nil)
        }

        cropperWindow.cropperView.autoStartOnCommit =
            !rememberRegionStore.isEnabled && autoStartStore.isEnabled

        cropperWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        cropperWindow.makeKey()

        // Register for SCStream exclusion after ordering front (windowNumber
        // is only valid once on-screen).
        if !shareableContent.contains(cropperWindow) {
            shareableContent.addOurWindow(cropperWindow)
        }
    }

    private func showRecordingOverlay(region: CGRect) {
        // RecordingOverlayWindow positions its children from the region
        // supplied at init; create a fresh instance for this recording.
        recordingOverlay.orderOut(nil)
        let overlay = RecordingOverlayWindow(regionInScreenCoords: region)
        overlay.onStop = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.requestStop()
            }
        }
        recordingOverlay = overlay

        overlay.orderFrontRegardless()

        // Register the new overlay's windows for SCStream exclusion.
        if !shareableContent.containsWindowNumbers(overlay.windowNumbers) {
            shareableContent.addWindowNumbers(overlay.windowNumbers)
        }
    }

    private func installCropperCallbacks() {
        cropperWindow.cropperView.onRecord = { [weak self] region in
            guard let self else { return }
            Task { @MainActor in
                await self.handleRecordRequested(region: region)
            }
        }
        cropperWindow.cropperView.onCancel = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.session.cancelCropping()
            }
        }
    }

    private func handleRecordRequested(region: CGRect) async {
        // Convert view-local region back to screen-space by adding the
        // window's screen origin (the window frame origin IS the screen origin
        // because showCropper sets the window frame to screen.frame).
        let screenOrigin = cropperWindow.frame.origin
        let screenRegion = CGRect(
            x: region.origin.x + screenOrigin.x,
            y: region.origin.y + screenOrigin.y,
            width: region.width,
            height: region.height
        )
        lastCroppedRegion = screenRegion

        let url = pathProvider.nextOutputURL()

        // Show the recording overlay and hide the cropper BEFORE starting
        // capture so the overlay's windows are in the SCContentFilter
        // exclusion list. SCContentFilter is locked-in at SCStream.start, so
        // any windows shown after start-time leak into the recording.
        cropperWindow.orderOut(nil)
        showRecordingOverlay(region: screenRegion)

        await shareableContent.refresh()
        let excluding = shareableContent.excludingWindows()

        do {
            try await session.start(
                region: screenRegion,
                scale: scaleStore.current,
                fps: 30,
                outputURL: url,
                excludingWindows: excluding
            )
        } catch {
            // Roll back the UI: hide the overlay since recording never started,
            // and re-show the cropper so the user can retry.
            recordingOverlay.orderOut(nil)
            cropperWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            cropperWindow.makeKey()
            notifier.presentFailure("Recording failed to start: \(error.localizedDescription)")
            Log.coordinator.error("session.start failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func installRecordingOverlayCallback() {
        recordingOverlay.onStop = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.requestStop()
            }
        }
    }

    func requestStop() async {
        do {
            let result = try await session.stop()
            pasteboard.copy(fileURL: result.outputURL)
            recentsStore.add(result.outputURL)
            notifier.present(savedURL: result.outputURL)
            Log.coordinator.info("saved \(result.outputURL.lastPathComponent, privacy: .public) drops=\(result.droppedFrames) latency=\(String(format: "%.1f", result.stopLatencyMs))ms")
        } catch {
            notifier.presentFailure("Recording failed: \(error.localizedDescription)")
            Log.coordinator.error("session.stop failed: \(String(describing: error), privacy: .public)")
        }
    }
}
