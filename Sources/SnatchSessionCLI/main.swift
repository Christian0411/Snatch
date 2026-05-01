// Sources/SnatchSessionCLI/main.swift
//
// snatch-session-cli — interactive cropper + GIF recorder.
//
// On launch:
//   1. Parses args (--output, --scale, --fps).
//   2. Shows the M3 transparent cropper overlay.
//   3. On Record (button or Space/Enter): hides cropper, shows the
//      red-border recording overlay with a Stop button, drives a
//      RecordingSession through the M2 capture pipeline + M1 encoder.
//   4. On Stop: saves the GIF, prints "SAVED <url> (drops=N, stop-latency=Xms)",
//      and terminates.
//   5. On Esc during cropping: prints "CANCELLED" and terminates.
//
// Run:
//   swift run snatch-session-cli --output /tmp/m4-smoke.gif
//
// M5 will lift these files into Snatch.xcodeproj when LSUIElement,
// hotkey, and notifications all need a bundle simultaneously.

import AppKit

let parsedArgs = parseSessionArgs()

let app = NSApplication.shared
let delegate = AppDelegate(args: parsedArgs)
app.delegate = delegate

// Foreground the process so the cropper window is key + frontmost. SPM
// executables otherwise launch as ".Background" and may not become key.
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

app.run()
