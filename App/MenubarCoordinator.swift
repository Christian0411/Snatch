import AppKit
import Combine
import SnatchKit
import SnatchAppKit

/// Mediates between the RecordingSession state machine and the AppKit
/// shells. Owns no business logic — just plumbing. Subsequent tasks
/// flesh out the show/hide and permission paths.
@MainActor
final class MenubarCoordinator {

    let session: RecordingSession
    let cropperWindow: CropperWindow
    let recordingOverlay: RecordingOverlayWindow
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
        // Task 17 fills this in.
    }

    private func installCropperCallbacks() {
        // Task 17 fills this in.
    }

    private func installRecordingOverlayCallback() {
        // Task 17 fills this in.
    }
}
