# Cropper edge-resize fix — design

**Status:** Draft 2026-05-03.
**Goal:** Make the borderless `.screenSaver`-level `CropperWindow` immune to the macOS edge-drag resize gesture.

## Motivation

`CropperWindow` (`Sources/SnatchAppKit/CropperWindow.swift`) is created with `styleMask: [.borderless]` and never includes `.resizable`. Despite this, on macOS 14+ the user can drag a screen edge and the window itself shrinks, exposing wallpaper/desktop where the dim used to be. The bug triggers off the window edge alone — the selection rect doesn't need to be near the edge.

This was discovered while smoke-testing pre-M6 cursor affordances on 2026-05-03 and confirmed pre-existing by rebuilding `df20ba4` (the plan-commit, before any cursor changes) and reproducing. It is a long-standing AppKit/window-server quirk, not a regression from recent work.

The bug is user-visible and worth fixing in a dedicated polish PR before M6 (Developer ID signing + notarization + ship).

## Non-goals

- **Not M6 work.** This is a pre-M6 polish item. M6 (notarization + ship) does not depend on this fix.
- **Not a refactor.** Only `CropperWindow.swift` is modified, plus bookkeeping in `CLAUDE.md` and the project memory file.
- **Not a fix for the recording overlays.** `BorderOverlayWindow` is `ignoresMouseEvents = true` and `StopButtonOverlayWindow` is too small to drag-edge — neither exhibits the bug in practice.
- **No dynamic re-evaluation on resolution change.** The existing `CropperWindow` captures `screen.frame` once at init and never re-lays-out, so handling mid-session resolution changes would expand scope beyond a polish PR. The invariant we enforce uses the screen frame captured at init.
- **No new test target or XCUITest infrastructure.** Verification is by manual smoke check, consistent with the project's pattern for cropper UX (`CLAUDE.md` workflow note: "manual smoke-test gates where it doesn't pay off").
- **No belt-and-suspenders.** We add one mechanism, smoke-test, and stop. If the first mechanism doesn't hold, we replace it — we don't stack guards.

## Invariant

After this fix lands:

> `cropperWindow.frame` always equals the `screen.frame` captured at the window's init, regardless of any user gesture.

`setFrame(_:display:)` calls with that exact frame still pass through normally; only off-screen-frame calls (i.e., the system attempting to shrink it) are blocked.

## Approach — two phases in one plan

### Phase 1 — Investigate (throwaway diagnostic)

Add diagnostic overrides to `CropperWindow` for the AppKit selectors most likely to be on the edge-drag path:

- `setFrame(_:display:)`
- `setFrame(_:display:animate:)`
- `mouseDown(with:)`
- `mouseDragged(with:)`

Each override prints a single line identifying the selector + the frame/event, then calls `super`. Build, reproduce the edge-drag, capture the log.

**Expected outcome:** one or two of these fire during the drag. Whichever fires *and changes the frame* is the path the Phase 2 fix needs to block.

The diagnostic overrides are **deleted before commit**. They exist only to inform the fix; they do not ship.

### Phase 2 — Apply the minimum fix

Driven by Phase 1's finding. Decision tree:

| Phase 1 result | Phase 2 fix |
|---|---|
| `setFrame(_:display:)` (or `…animate:`) is called with a frame ≠ initial `screen.frame` | Override `setFrame(_:display:)` to clamp: if the incoming frame ≠ initial screen frame, call `super.setFrame(initialScreenFrame, display: display)` instead (or no-op if already correct). |
| A mouse event triggers an internal AppKit resize *without* going through `setFrame` | Set `cropperWindow.isMovable = false` and/or override `mouseDown(with:)` to consume edge events without forwarding. |
| Both | Start with the `setFrame` clamp (it catches everything downstream). Add `isMovable = false` only if the clamp alone doesn't hold. |

In all cases: **add one mechanism, smoke-test, stop.** No stacked guards "just in case."

### Frame storage

If the Phase 2 fix needs the initial screen frame, store it in a `private let initialScreenFrame: CGRect` set in `init` (we already capture `screen.frame` there as `frame`; this just preserves it for later use).

## Verification — manual smoke check

Added to the pre-M6 checklist:

1. Launch Snatch from the menubar app.
2. Press ⇧⌘6 to open the cropper.
3. Drag from each of the four screen edges in turn.
4. **Expect:** nothing visible changes. No window shrink, no exposed wallpaper.
5. Drag inside the rect on a resize handle. **Expect:** still resizes the selection normally.
6. Drag inside the rect body. **Expect:** still moves the selection normally.
7. Drag from empty area to create a new selection. **Expect:** works normally.
8. Press Esc / Enter / Space. **Expect:** still cancels / records / records, respectively.
9. Click Record. **Expect:** transitions to recording overlay normally.

If any of steps 5–9 regresses, the chosen mechanism is too aggressive — back out and try the alternate branch in the decision tree.

## Files touched

- `Sources/SnatchAppKit/CropperWindow.swift` — the chosen Phase 2 override(s).
- `CLAUDE.md` — update line 44 to reflect the fix landed (move the bug from "out-of-scope follow-up" to "fixed in pre-M6 …").
- `~/.claude/projects/-Users-starship-src/memory/snatch_cropper_window_edge_resize_bug.md` — delete. The memory exists only to flag a pending bug; once fixed it has no further use.
- `~/.claude/projects/-Users-starship-src/memory/MEMORY.md` — remove the corresponding index line.

## Risk / unknowns

- **The `setFrame` clamp could interfere with legitimate frame changes** (e.g., display reconfiguration). We mitigate by clamping rather than no-op'ing — `setFrame` with the initial screen frame still passes through; only off-screen-frame calls get squashed. The smoke check above does not cover display reconfiguration; we accept that risk because (a) the cropper is a transient overlay, not a long-lived window, and (b) display reconfiguration during an active cropper session is already not a supported path.
- **Phase 1 might find none of the four selectors fire,** which would mean the resize comes from a path we haven't enumerated (e.g., `setContentSize`, `setFrameOrigin`, or a private SkyLight gesture handler). In that case the plan's first task is "add three more selectors and re-run" rather than guessing a fix. We do not ship a guess.
