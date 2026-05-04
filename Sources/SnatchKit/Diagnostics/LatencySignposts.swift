// Sources/SnatchKit/Diagnostics/LatencySignposts.swift
import Foundation
import os

/// Two latency intervals instrumented for Snatch's M6 ship gate:
///
///   - **HotkeyToPaint**: ⇧⌘6 hotkey-press → first paint of the cropper. Target < 100 ms.
///   - **StopToNotification**: stop-trigger → save notification. Target < 500 ms.
///
/// Each interval emits both an `os_signpost` (visible in Instruments → Points
/// of Interest) and a single `os_log .info` line carrying the elapsed
/// milliseconds (visible in Console.app, filter `subsystem:co.snatch.app
/// category:Latency`).
///
/// Always-on; cost is tens of nanoseconds per signpost + one log line per user
/// action.
public enum LatencySignposts {

    private static let log = OSLog(subsystem: "co.snatch.app", category: "Latency")
    private static let signposter = OSSignposter(logHandle: log)
    private static let logger = Logger(subsystem: "co.snatch.app", category: "Latency")

    /// Opaque per-interval state passed from `begin*` to the matching `end*`.
    public struct Interval {
        let state: OSSignpostIntervalState
        let started: ContinuousClock.Instant
        let name: StaticString
    }

    public static func beginHotkeyToPaint() -> Interval {
        let name: StaticString = "HotkeyToPaint"
        let state = signposter.beginInterval(name)
        return Interval(state: state, started: .now, name: name)
    }

    public static func endHotkeyToPaint(_ interval: Interval) {
        signposter.endInterval(interval.name, interval.state)
        logger.info("HotkeyToPaint: \(String(format: "%.1f", elapsedMs(since: interval.started)), privacy: .public) ms")
    }

    public static func beginStopToNotification() -> Interval {
        let name: StaticString = "StopToNotification"
        let state = signposter.beginInterval(name)
        return Interval(state: state, started: .now, name: name)
    }

    public static func endStopToNotification(_ interval: Interval) {
        signposter.endInterval(interval.name, interval.state)
        logger.info("StopToNotification: \(String(format: "%.1f", elapsedMs(since: interval.started)), privacy: .public) ms")
    }

    /// Convert an elapsed `ContinuousClock.Duration` to milliseconds.
    ///
    /// `Duration.components` returns `(seconds: Int64, attoseconds: Int64)`;
    /// 1 ms = 1e15 attoseconds. We sum both components so an elapsed time
    /// > 1 second is still measured correctly.
    private static func elapsedMs(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
    }
}
