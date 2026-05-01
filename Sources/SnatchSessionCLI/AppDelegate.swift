// Sources/SnatchSessionCLI/AppDelegate.swift
import AppKit
import ScreenCaptureKit
import SnatchKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let args: Args
    private let regionStore = RegionStore()

    private let pipeline: ScreenRecordingPipeline
    private let session: RecordingSession

    private var cropperWindow: CropperWindow?
    private var overlayWindow: RecordingOverlayWindow?

    /// Coordinate-space conversion is per primary display — multi-display lands in M5.
    private weak var primaryScreen: NSScreen?

    init(args: Args) {
        self.args = args
        let pipeline = ScreenRecordingPipeline()
        self.pipeline = pipeline
        let store = regionStore
        // RecordingSession is @MainActor. AppDelegate is always constructed on
        // the main thread (NSApplicationDelegate requirement), so assumeIsolated
        // is safe here.
        self.session = MainActor.assumeIsolated {
            RecordingSession(pipeline: pipeline, regionStore: store)
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else {
            Self.printAndExit("CANCELLED", code: 0)
            return
        }
        self.primaryScreen = screen

        // Pre-draw the persisted region (in screen coords) translated to view-local.
        let initialViewLocal = regionStore.lastRegion.map { region -> CGRect in
            CGRect(
                x: region.origin.x - screen.frame.origin.x,
                y: region.origin.y - screen.frame.origin.y,
                width: region.size.width,
                height: region.size.height
            )
        }

        let w = CropperWindow(screen: screen, initialRegion: initialViewLocal)
        w.cropperView.onRecord = { [weak self] viewRect in
            // Outbound: view-local → screen-space (CG coords).
            let screenRect = CGRect(
                x: viewRect.origin.x + screen.frame.origin.x,
                y: viewRect.origin.y + screen.frame.origin.y,
                width: viewRect.size.width,
                height: viewRect.size.height
            )
            self?.cropperRecordRequested(region: screenRect)
        }
        w.cropperView.onCancel = { [weak self] in
            self?.cropperCancelled()
        }
        self.cropperWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: - Cropper callbacks

    private func cropperRecordRequested(region: CGRect) {
        Task { @MainActor [weak self] in
            await self?.runRecordingFlow(region: region)
        }
    }

    private func cropperCancelled() {
        Task { @MainActor [weak self] in
            await self?.session.cancel()
            Self.printAndExit("CANCELLED", code: 0)
        }
    }

    // MARK: - Recording flow

    @MainActor
    private func runRecordingFlow(region: CGRect) async {
        guard let cropperWindow = self.cropperWindow else {
            Self.printAndExit("ERROR: cropper window missing", code: 1, toStderr: true)
            return
        }

        // 1. Show the recording overlay first so it has a windowNumber assigned
        //    by WindowServer before we ask SCShareableContent to enumerate windows.
        let overlay = RecordingOverlayWindow(regionInScreenCoords: region)
        overlay.onStop = { [weak self] in
            self?.stopRequested()
        }
        overlay.orderFrontRegardless()
        self.overlayWindow = overlay

        // 2. Resolve [SCWindow] for cropper + both overlay sub-windows.
        let windowNumbers: [Int] = [cropperWindow.windowNumber] + overlay.windowNumbers
        let scWindows: [SCWindow]
        do {
            scWindows = try await Self.resolveSCWindows(forNumbers: windowNumbers)
        } catch {
            Self.printAndExit("ERROR resolving SCWindows: \(error)", code: 1, toStderr: true)
            return
        }
        if scWindows.count != windowNumbers.count {
            Log.coordinator.error(
                "expected \(windowNumbers.count, privacy: .public) SCWindows, got \(scWindows.count, privacy: .public); overlay or cropper may leak into capture"
            )
        }

        // 3. Hide the cropper now (after SCWindow resolution — cropper must still
        //    be onscreen for the WindowServer to enumerate it).
        cropperWindow.orderOut(nil)

        // 4. Drive the session.
        do {
            try await session.start(
                region: region,
                scale: args.scale,
                fps: args.fps,
                outputURL: args.output,
                excludingWindows: scWindows
            )
        } catch RecordingSessionError.pipelineStartFailed(let underlying) {
            if case SCStreamWrapperError.permissionDenied = underlying {
                Self.printAndExit(
                    "Snatch needs Screen Recording permission. Open System Settings → Privacy & Security → Screen Recording.",
                    code: 3, toStderr: true
                )
            } else {
                Self.printAndExit("ERROR: \(String(describing: underlying))", code: 1, toStderr: true)
            }
            return
        } catch {
            Self.printAndExit("ERROR: \(error.localizedDescription)", code: 1, toStderr: true)
            return
        }

        // Now in .recording — wait for stopRequested() (Stop button click) to
        // call session.stop(). The flow continues there.
    }

    private func stopRequested() {
        Task { @MainActor [weak self] in
            await self?.runStopFlow()
        }
    }

    @MainActor
    private func runStopFlow() async {
        do {
            let result = try await session.stop()
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
            print("SAVED \(result.outputURL.path) (drops=\(result.droppedFrames), stop-latency=\(String(format: "%.1f", result.stopLatencyMs))ms)")
            NSApplication.shared.terminate(nil)
        } catch {
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
            Self.printAndExit("RECORDING FAILED: \(error.localizedDescription)", code: 1, toStderr: true)
        }
    }

    // MARK: - SCWindow resolution

    /// Look up `[SCWindow]` for the given AppKit `NSWindow.windowNumber` values.
    /// Retries once after 50 ms if any are missing (race with WindowServer
    /// registration). Falls back to whatever it found after the retry.
    private static func resolveSCWindows(forNumbers numbers: [Int]) async throws -> [SCWindow] {
        let targetIDs = Set(numbers.map { CGWindowID($0) })

        let firstTry = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ).windows.filter { targetIDs.contains($0.windowID) }

        if firstTry.count == numbers.count {
            return firstTry
        }

        // Retry once.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let secondTry = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ).windows.filter { targetIDs.contains($0.windowID) }
        return secondTry
    }

    // MARK: - Termination helper

    @MainActor
    private static func printAndExit(_ message: String, code: Int32, toStderr: Bool = false) {
        if toStderr {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        } else {
            print(message)
        }
        NSApplication.shared.terminate(nil)
    }
}
