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
    let recentsStore: RecentRecordingsStore
    let permissions: PermissionsCoordinator
    let pasteboard: PasteboardWriter
    let notifier: NotificationPresenter
    let pathProvider: PathProvider
    let shareableContent: ShareableContentCache

    private var cancellables = Set<AnyCancellable>()
    private var lastCroppedRegion: CGRect = .zero

    init(session: RecordingSession,
         cropperWindow: CropperWindow,
         recordingOverlay: RecordingOverlayWindow,
         regionStore: RegionStore,
         scaleStore: ScalePresetStore,
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
        self.recentsStore = recentsStore
        self.permissions = permissions
        self.pasteboard = pasteboard
        self.notifier = notifier
        self.pathProvider = pathProvider
        self.shareableContent = shareableContent

        installSubscriptions()
        installCropperCallbacks()
        installRecordingOverlayCallback()
    }

    func handleHotkey() {
        // Permission gate
        guard permissions.cachedState != .denied else {
            // PermissionAlertPresenter call lands in Task 18.
            return
        }
        if permissions.cachedState == .notDetermined {
            // Permission request flow lands in Task 18.
            return
        }
        Task { @MainActor in
            switch session.state {
            case .idle:                           session.beginCropping()
            case .cropping:                       session.cancelCropping()
            case .recording:                      _ = try? await session.stop()
            case .finalizing, .cancelling:        break
            }
        }
    }

    private func installSubscriptions() {
        session.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.handleStateChange(newState)
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(_ state: RecordingSession.State) {
        switch state {
        case .cropping:
            showCropper()
        case .recording:
            cropperWindow.orderOut(nil)
            showRecordingOverlay(region: lastCroppedRegion)
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
        if let last = regionStore.lastRegion {
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

        cropperWindow.orderFrontRegardless()
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
                await self.handleStopRequested()
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

        // Pre-flight refresh so excludingWindows() is fresh.
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
            notifier.presentFailure("Recording failed to start: \(error.localizedDescription)")
            Log.coordinator.error("session.start failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func installRecordingOverlayCallback() {
        recordingOverlay.onStop = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.handleStopRequested()
            }
        }
    }

    private func handleStopRequested() async {
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
