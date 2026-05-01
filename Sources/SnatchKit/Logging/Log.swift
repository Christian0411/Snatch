import Foundation
import os

/// Snatch's unified-logging facade.
///
/// Subsystem: `co.snatch.app` (per spec §8).
/// Categories: capture, encoder, coordinator, ui, system.
///
/// Levels in use:
///   - `.info`  — state transitions, recording start/stop with region + scale
///   - `.debug` — frame drops, queue depth peaks
///   - `.error` — every error with full context
public enum Log {
    private static let subsystem = "co.snatch.app"

    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let encoder = Logger(subsystem: subsystem, category: "encoder")
    public static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let system = Logger(subsystem: subsystem, category: "system")
}
