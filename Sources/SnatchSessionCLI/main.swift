// Sources/SnatchSessionCLI/main.swift
//
// snatch-cropper-cli — full-screen cropper UI smoke harness for M3.
//
// On launch, presents the transparent cropper overlay. On Record (button or
// Space/Enter), writes the chosen region to stdout in the form:
//
//     RECORD region=(x,y,w,h)
//
// then persists it via RegionStore and exits 0. On Esc, writes:
//
//     CANCELLED
//
// and exits 0.
//
// Run:
//   swift run snatch-cropper-cli
//
// Note (M3 build-system decision, see plan): this is an SPM executable, not
// a bundled .app. It runs a normal NSApplication; macOS will give it a Dock
// icon and a default app menu. M5 will lift these files into the new
// Snatch.xcodeproj when LSUIElement / hotkey / notifications all need a
// bundle simultaneously.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Foreground the process so the cropper window is key + frontmost. Without
// this, an SPM executable launches as a "background" .Background process
// and the window may not become key.
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

app.run()
