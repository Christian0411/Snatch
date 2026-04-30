# Snatch

A fast, simple, native macOS GIF recorder. Select a screen region, record, get a GIF — instantly.

## North star

Two things matter, in this order:

1. **Speed** — sub-second from "stop recording" to "GIF saved". No H.264 intermediate, no FFmpeg round-trip. Frames stream into the encoder during capture.
2. **Simplicity** — single Xcode project, minimal dependencies, no Electron, no web tech.

## Stack

- **Language/UI**: Swift + SwiftUI (menubar, prefs) + AppKit (transparent cropper overlay window)
- **Capture**: ScreenCaptureKit (GPU-backed `CMSampleBuffer`s, hardware-accelerated cropping via `SCContentFilter`)
- **Encode**: gifski (Rust, via C FFI) — per-frame palette quantization, streams frames as they arrive
- **Min OS**: macOS 14 (Sonoma)

## Non-goals (v1)

- Cross-platform (macOS only — do not add Linux/Windows abstractions)
- Video output other than GIF
- Cloud upload, sharing integrations, plugin systems
- Audio recording

## Workflow

This project uses Superpowers (`obra/superpowers`). Design-first: brainstorm → write-plan → subagent-driven-development → TDD where it pays off (encoder, frame pipeline, file I/O), manual smoke-test gates where it doesn't (cropper UX, hotkeys, menubar feel).

Design docs and ADRs live in `docs/`.
