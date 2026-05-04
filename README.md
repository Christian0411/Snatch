# Snatch

Fast, native macOS GIF recorder. Select a region, record, get a GIF — instantly.

## Install

1. Download the latest `Snatch-X.Y.Z.dmg` from the [Releases page](https://github.com/Christian0411/Snatch/releases).
2. Open the DMG and drag `Snatch.app` to `Applications`.
3. Launch Snatch — the camera-viewfinder icon appears in your menubar.
4. Grant Screen Recording: **System Settings → Privacy & Security → Screen Recording**, enable Snatch, then re-launch when prompted.

## Usage

- Press **⇧⌘6** anywhere to open the cropper.
- Drag a rectangle. Resize via the 8 handles or move it by dragging the body.
- Press **Space**, **Return**, or click the **Record** button to start.
- Press **⇧⌘6** again, click **Stop**, or click the menubar icon to stop.
- The GIF saves to `~/Desktop/`. The file URL is also copied to your clipboard — paste straight into Slack, Discord, or Notes to share the animation.
- Press **Esc** at any time to cancel without saving.

## Requirements

- macOS 14 (Sonoma) or later.
- Apple Silicon recommended; Intel is supported (universal binary) but untested at scale.

## Updating

Download the new DMG and drag the app to `Applications`, replacing the old copy.

## Known issues

- After granting Screen Recording in System Settings, you may need to **quit and re-launch Snatch** from the menubar before recording works — macOS doesn't propagate permission changes into running processes. ([#1](https://github.com/Christian0411/Snatch/issues/1))

## License

MIT — see [LICENSE](LICENSE).
