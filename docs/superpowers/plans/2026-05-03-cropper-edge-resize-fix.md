# Cropper edge-resize fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the borderless `.screenSaver`-level `CropperWindow` immune to the macOS edge-drag resize gesture, by identifying the AppKit path that triggers the resize and surgically blocking it.

**Architecture:** Two phases. Phase 1 is throwaway diagnostic logging on `CropperWindow` to identify which AppKit selector AppKit calls during a screen-edge drag. Phase 2 applies the *minimum* override per the spec's decision tree — most likely a `setFrame(_:display:)` clamp pinned to the screen frame captured at init.

**Tech Stack:** Swift 5.10, AppKit. No new tests — verification is by manual smoke check, per spec.

**Spec:** `docs/superpowers/specs/2026-05-03-cropper-edge-resize-fix-design.md` (commit `84f1c40`)

**Note on TDD:** This plan deliberately omits TDD. The spec's verification section explicitly chose manual smoke testing over unit / XCUITest infrastructure, because the bug lives at the AppKit/window-server boundary where a unit test of `CropperWindow` would either need to mock NSWindow (not meaningful) or drive a real AppKit gesture (XCUITest, out of scope per spec). Steps below have explicit reproduction and verification commands instead of test runs.

---

## File map

### Modified files

| Path | Change |
|---|---|
| `Sources/SnatchAppKit/CropperWindow.swift` | Phase 1: temporarily add 4 diagnostic overrides (throwaway, never committed). Phase 2: add the chosen mechanism (most likely a `setFrame(_:display:)` clamp + a `private let initialScreenFrame: CGRect`). |
| `CLAUDE.md` | Remove the "Surfaced one out-of-scope follow-up" sentence at the end of the pre-M6 cursor affordances status line; add a new status line for this fix. |

### Deleted files (after fix lands)

| Path | Action |
|---|---|
| `~/.claude/projects/-Users-starship-src/memory/snatch_cropper_window_edge_resize_bug.md` | Delete. The memory exists only to flag a pending bug; once fixed it has no further use. |
| `~/.claude/projects/-Users-starship-src/memory/MEMORY.md` | Remove the line `- [Snatch cropper window edge-resize bug](snatch_cropper_window_edge_resize_bug.md) — borderless …`. |

### Untouched (verify by inspection if anything looks off)

- `Sources/SnatchAppKit/RecordingOverlayWindow.swift` — out of scope per spec §Non-goals (`BorderOverlayWindow` is `ignoresMouseEvents = true`; `StopButtonOverlayWindow` is too small to drag-edge).
- `Sources/SnatchAppKit/CropperView.swift` — bug is at the window layer, not the view.
- All `SnatchKit` files — pure logic, not involved.

---

## Task 0: Preflight

**Files:** none.

Verify the repo is in the expected state before starting.

- [ ] **Step 1: Confirm clean working tree on `main`.**

Run: `git status --short && git rev-parse --abbrev-ref HEAD`
Expected: empty status output, branch name `main` (or your working branch).

- [ ] **Step 2: Confirm spec is committed.**

Run: `git log --oneline -1 docs/superpowers/specs/2026-05-03-cropper-edge-resize-fix-design.md`
Expected: prints `84f1c40 docs: cropper edge-resize fix design` (or a later commit if the spec was amended).

- [ ] **Step 3: Verify build is green.**

Run: `swift build 2>&1 | tail -3`
Expected: no errors. (Warnings about Sendable etc. that already exist are OK.)

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Read the spec end-to-end.**

Open `docs/superpowers/specs/2026-05-03-cropper-edge-resize-fix-design.md`. The spec is the authoritative source for *what* and *why*; this plan is the authoritative source for *how* and *in what order*.

- [ ] **Step 5: Read `Sources/SnatchAppKit/CropperWindow.swift`.**

It is 49 lines. Note the existing structure — `init(screen:initialRegion:)` captures `let frame = screen.frame` locally and uses it for `super.init(contentRect: frame, ...)`. The `frame` is *not* preserved as a property today; Phase 2 will add `private let initialScreenFrame: CGRect` for that purpose.

---

## Task 1: Add Phase 1 diagnostic overrides (throwaway — DO NOT commit)

**Files:**
- Modify: `Sources/SnatchAppKit/CropperWindow.swift`

Add overrides for the four selectors most likely to be on the edge-drag path. Each prints a single line and forwards to `super`. These exist solely to identify which AppKit method AppKit calls when the user drags a screen edge.

**Critical:** these changes are **never committed**. Task 4 reverts them via `git checkout`.

- [ ] **Step 1: Add diagnostic overrides to `CropperWindow`.**

In `Sources/SnatchAppKit/CropperWindow.swift`, immediately above the closing `}` of `class CropperWindow` (after `becomeKey()` at line 47), insert:

```swift

    // MARK: - DIAGNOSTIC (throwaway, do not commit)

    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        print("[CROPDIAG] setFrame(_:display:) frameRect=\(frameRect) flag=\(flag) currentFrame=\(self.frame)")
        super.setFrame(frameRect, display: flag)
    }

    public override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        print("[CROPDIAG] setFrame(_:display:animate:) frameRect=\(frameRect) display=\(displayFlag) animate=\(animateFlag) currentFrame=\(self.frame)")
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
    }

    public override func mouseDown(with event: NSEvent) {
        print("[CROPDIAG] mouseDown locInWindow=\(event.locationInWindow) locInScreen=\(NSEvent.mouseLocation)")
        super.mouseDown(with: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        print("[CROPDIAG] mouseDragged locInWindow=\(event.locationInWindow) locInScreen=\(NSEvent.mouseLocation) currentFrame=\(self.frame)")
        super.mouseDragged(with: event)
    }
```

- [ ] **Step 2: Verify it compiles.**

Run: `swift build 2>&1 | tail -3`
Expected: succeeds.

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Confirm changes are uncommitted (sanity check).**

Run: `git status --short`
Expected: shows `M Sources/SnatchAppKit/CropperWindow.swift` (modified, unstaged). Do **not** stage or commit.

---

## Task 2: Reproduce the bug and capture diagnostic output

**Files:** none (manual reproduction).

The goal is to identify which `[CROPDIAG]` line(s) print *and report a frame change* when the user drags a screen edge to shrink the cropper window.

- [ ] **Step 1: Build a fresh dev `.app`.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. Note the `BUILT_PRODUCTS_DIR` path printed earlier in the output.

- [ ] **Step 2: Find the built app.**

Run: `find ~/Library/Developer/Xcode/DerivedData -path '*Snatch*/Build/Products/Debug/Snatch.app' -maxdepth 8 -type d 2>/dev/null | head -1`
Expected: prints a path ending in `…/Build/Products/Debug/Snatch.app`. Save this path; you will launch from it in step 3.

- [ ] **Step 3: Launch with stdout/stderr captured.**

Quit any running Snatch first (right-click menubar icon → Quit, or `pkill -x Snatch`).

Run, replacing `<APP_PATH>` with the path from step 2:
```
"<APP_PATH>/Contents/MacOS/Snatch" 2>&1 | tee /tmp/cropdiag.log
```
Expected: app launches, menubar icon appears, terminal shows initial `[CROPDIAG]` lines (likely none yet — overrides only fire when the cropper is shown and interacted with).

- [ ] **Step 4: Open the cropper.**

Press ⇧⌘6 (or click the menubar icon → Snatch Region). Cropper overlay appears (dim screen with no selection).

In the terminal, you may see `[CROPDIAG] setFrame…` lines from the cropper's initial layout — that's normal. Note the frame they report; that's the screen frame.

- [ ] **Step 5: Trigger the bug.**

Drag from any screen edge (try the top edge first; the menu bar area). Drag inward several hundred pixels. The cropper window should visibly shrink — wallpaper/desktop appears where the dim used to be.

- [ ] **Step 6: Quit and inspect the log.**

Quit Snatch (menubar → Quit, or Ctrl-C in the terminal).

Read the diagnostic log:
```
grep -n CROPDIAG /tmp/cropdiag.log | tail -40
```
Expected: a sequence of `[CROPDIAG]` lines from the drag period.

- [ ] **Step 7: Identify the offending path.**

Look for **a `setFrame(_:display:)` (or `…animate:`) call where `frameRect` is *smaller than* the initial screen frame**. That is the path the fix needs to block.

Record findings explicitly. Pick exactly one:

- **Result A — `setFrame(_:display:)` fires with shrinking frame.** Most common case. Proceed to Task 4 → branch A.
- **Result B — `setFrame(_:display:animate:)` fires (with or without the non-animate variant).** Proceed to Task 4 → branch A (the override on `setFrame(_:display:)` is the canonical one; `…animate:` calls into it via super in most NSWindow internals — verify in the smoke test).
- **Result C — Only `mouseDown` / `mouseDragged` fire; no `setFrame` log line accompanies the visible shrink.** AppKit is changing the frame via a path that doesn't go through `setFrame`. Proceed to Task 4 → branch B.
- **Result D — None of the four fire during the visible shrink.** The resize comes from a path we haven't enumerated. Proceed to Task 3.

Write your finding (A / B / C / D) into a scratch note for use in Tasks 3 and 4.

---

## Task 3: Expand diagnostics if Result D (skip if Result A/B/C)

**Files:**
- Modify: `Sources/SnatchAppKit/CropperWindow.swift`

Per the spec's risk note: if none of the four selectors fire, the resize comes from a path we haven't enumerated. Add three more selectors and re-run. **Do not guess a fix.**

If Task 2 yielded Result A, B, or C, **skip this entire task** and go to Task 4.

- [ ] **Step 1: Add three more diagnostic overrides.**

In `Sources/SnatchAppKit/CropperWindow.swift`, inside the same `// MARK: - DIAGNOSTIC` block as Task 1, append:

```swift

    public override func setContentSize(_ size: NSSize) {
        print("[CROPDIAG] setContentSize size=\(size) currentFrame=\(self.frame)")
        super.setContentSize(size)
    }

    public override func setFrameOrigin(_ point: NSPoint) {
        print("[CROPDIAG] setFrameOrigin point=\(point) currentFrame=\(self.frame)")
        super.setFrameOrigin(point)
    }

    public override func setFrameTopLeftPoint(_ point: NSPoint) {
        print("[CROPDIAG] setFrameTopLeftPoint point=\(point) currentFrame=\(self.frame)")
        super.setFrameTopLeftPoint(point)
    }
```

- [ ] **Step 2: Verify it compiles.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Re-run Task 2 steps 1–7 with the expanded selector set.**

If a new selector now fires with a shrinking dimension, that's the path. Branch A becomes "override that selector to clamp." Branch B becomes "consume the upstream mouse event."

If *still* no selector fires, stop and escalate to the user. Do not proceed to Task 4. The fix needs additional research (private SkyLight gesture handler, accessibility APIs, etc.) which is beyond this plan's scope.

---

## Task 4: Apply the fix (branch on Task 2 result)

**Files:**
- Modify: `Sources/SnatchAppKit/CropperWindow.swift`

This task has two branches. Pick **one** based on Task 2's result. Do not do both.

- [ ] **Step 1: Revert all diagnostic code.**

Run: `git checkout Sources/SnatchAppKit/CropperWindow.swift`
Expected: file returns to its committed state (no `[CROPDIAG]` overrides remain).

Confirm:
```
git diff Sources/SnatchAppKit/CropperWindow.swift
```
Expected: empty output.

- [ ] **Step 2: Branch on Task 2 result.**

Go to **Step 3a (branch A)** if Task 2 yielded Result A or B (`setFrame` fires with a shrinking frame).

Go to **Step 3b (branch B)** if Task 2 yielded Result C (mouse events fire without `setFrame`).

If Task 3 was needed and identified a different selector, adapt branch A to that selector by analogy (override the discovered method, clamp its parameter to the equivalent of the screen frame).

### Step 3a — Branch A: `setFrame` clamp

- [ ] **Step 3a.1: Add `initialScreenFrame` property and clamping override.**

In `Sources/SnatchAppKit/CropperWindow.swift`:

(i) Add the property declaration immediately after `public let cropperView: CropperView` (currently line 12):

```swift
    /// The screen frame captured at init. Used by `setFrame(_:display:)` to
    /// clamp away macOS's edge-drag resize gesture, which can shrink a
    /// borderless `.screenSaver` window despite no `.resizable` in the
    /// style mask.
    private let initialScreenFrame: CGRect
```

(ii) In `init(screen:initialRegion:)`, assign the property *before* `super.init`. Replace:

```swift
    public init(screen: NSScreen, initialRegion: CGRect?) {
        let frame = screen.frame
        self.cropperView = CropperView(frame: NSRect(origin: .zero, size: frame.size), initialRegion: initialRegion)

        // 4-arg designated initializer; see Task 9 note on why the
        // 5-arg `…:screen:` convenience form can't be called here.
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
```

with:

```swift
    public init(screen: NSScreen, initialRegion: CGRect?) {
        let frame = screen.frame
        self.cropperView = CropperView(frame: NSRect(origin: .zero, size: frame.size), initialRegion: initialRegion)
        self.initialScreenFrame = frame

        // 4-arg designated initializer; see Task 9 note on why the
        // 5-arg `…:screen:` convenience form can't be called here.
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
```

(iii) Add the clamping override immediately above the closing `}` of `class CropperWindow` (after `becomeKey()` at line 47):

```swift

    /// Clamp away macOS's edge-drag resize gesture. The cropper is sized to
    /// `screen.frame` at init and must stay there for its lifetime — but on
    /// macOS 14+ a borderless `.screenSaver`-level window still accepts the
    /// system edge-drag resize gesture, which calls into here with a smaller
    /// rect. Forwarding the original frame keeps the legitimate init-time
    /// call working while squashing the gesture.
    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if frameRect == initialScreenFrame {
            super.setFrame(frameRect, display: flag)
        } else {
            super.setFrame(initialScreenFrame, display: flag)
        }
    }
```

- [ ] **Step 3a.2: Verify it compiles.**

Run: `swift build 2>&1 | tail -3`
Expected: succeeds.

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3a.3: Smoke-test the fix.**

Quit any running Snatch (`pkill -x Snatch`), then launch the freshly-built `.app` (use the path from Task 2 step 2):

```
open -n "<APP_PATH>"
```

Run the full smoke matrix from spec §Verification:

1. ⇧⌘6 to open the cropper. Expected: cropper appears.
2. Drag from each of the four screen edges. **Expected: nothing visible changes. No shrink, no exposed wallpaper.**
3. Drag inside the rect on a resize handle. Expected: still resizes the selection normally.
4. Drag inside the rect body. Expected: still moves the selection normally.
5. Drag from empty area to create a new selection. Expected: works normally.
6. Press Esc / Enter / Space. Expected: cancels / records / records, respectively.
7. Click Record. Expected: transitions to recording overlay normally.

If step 2 still shrinks the window, the clamp didn't catch it. Skip to Step 3b (branch B). If steps 3–7 regress, the clamp is too aggressive — see "Fallback" note at the end of this task.

If all 7 pass, proceed to Task 5.

### Step 3b — Branch B: mouse-event consumption

Use this branch only if `setFrame` does *not* fire during the shrink (Task 2 Result C, or if branch A's smoke test failed step 2).

- [ ] **Step 3b.1: Add `isMovable = false`.**

In `Sources/SnatchAppKit/CropperWindow.swift`, in `init(screen:initialRegion:)`, immediately after `self.acceptsMouseMovedEvents = true` (currently line 33), add:

```swift
        // The cropper is a fixed-size overlay pinned to `screen.frame`. macOS
        // 14+ accepts the system edge-drag resize gesture on borderless
        // `.screenSaver` windows even without `.resizable` in the style mask.
        // `isMovable = false` declines that gesture at the window layer.
        self.isMovable = false
```

- [ ] **Step 3b.2: Verify it compiles.**

Run: `xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3b.3: Smoke-test the fix.**

Quit any running Snatch (`pkill -x Snatch`), then launch the freshly-built `.app` (use the path from Task 2 step 2):

```
open -n "<APP_PATH>"
```

Run the full smoke matrix from spec §Verification:

1. ⇧⌘6 to open the cropper. Expected: cropper appears.
2. Drag from each of the four screen edges. **Expected: nothing visible changes. No shrink, no exposed wallpaper.**
3. Drag inside the rect on a resize handle. Expected: still resizes the selection normally.
4. Drag inside the rect body. Expected: still moves the selection normally.
5. Drag from empty area to create a new selection. Expected: works normally.
6. Press Esc / Enter / Space. Expected: cancels / records / records, respectively.
7. Click Record. Expected: transitions to recording overlay normally.

If step 2 still shrinks the window, escalate to the user — neither single mechanism worked, and per spec §Non-goals we do not stack guards without revisiting the design.

If all 7 pass, proceed to Task 5.

### Fallback (rare)

If Step 3a's smoke test passes step 2 but breaks one of steps 3–7 (e.g., the clamp also blocks some legitimate frame call we didn't anticipate), back out the clamp (`git checkout Sources/SnatchAppKit/CropperWindow.swift`) and try branch B instead. The spec's decision tree explicitly allows this swap.

---

## Task 5: Final cleanliness check + commit the fix

**Files:**
- `Sources/SnatchAppKit/CropperWindow.swift` (already modified by Task 4)

- [ ] **Step 1: Confirm no `[CROPDIAG]` strings remain.**

Run: `grep -n CROPDIAG Sources/SnatchAppKit/CropperWindow.swift || echo CLEAN`
Expected: prints `CLEAN`.

- [ ] **Step 2: Review the final diff.**

Run: `git diff Sources/SnatchAppKit/CropperWindow.swift`
Expected: shows only the chosen Phase 2 change (branch A: `initialScreenFrame` property + assignment + `setFrame` override; or branch B: a single `self.isMovable = false` line).

If the diff includes anything else (stray prints, unrelated formatting), clean it up before committing.

- [ ] **Step 3: One more clean build.**

Run: `swift build 2>&1 | tail -3 && xcodebuild -project Snatch.xcodeproj -scheme Snatch build 2>&1 | tail -3`
Expected: both succeed.

- [ ] **Step 4: Commit.**

Run, picking the message that matches your branch:

**For branch A (setFrame clamp):**
```
git add Sources/SnatchAppKit/CropperWindow.swift
git commit -m "fix(cropper): clamp setFrame to initial screen frame

Closes the long-standing AppKit/window-server quirk where the borderless
.screenSaver-level CropperWindow could be edge-resized via macOS system
gesture despite no .resizable in styleMask. Phase 1 diagnostics confirmed
the resize gesture lands in setFrame(_:display:) with a shrinking rect;
we forward the initial screen frame instead. Pre-existing bug, verified
on df20ba4."
```

**For branch B (isMovable = false):**
```
git add Sources/SnatchAppKit/CropperWindow.swift
git commit -m "fix(cropper): set isMovable = false to decline edge-drag resize

Closes the long-standing AppKit/window-server quirk where the borderless
.screenSaver-level CropperWindow could be edge-resized via macOS system
gesture despite no .resizable in styleMask. Phase 1 diagnostics showed
mouse events drove the resize without going through setFrame; declining
the move/resize gesture at the window layer is the cleanest block.
Pre-existing bug, verified on df20ba4."
```

- [ ] **Step 5: Verify commit landed.**

Run: `git log --oneline -1`
Expected: prints the new commit's hash and your chosen message's first line.

---

## Task 6: Bookkeeping — CLAUDE.md status update

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read the current line 44.**

Run: `sed -n '44p' CLAUDE.md`
Expected: starts with `- **Pre-M6 cursor affordances ✅ Complete**` and ends with `…verified by rebuilding 'df20ba4' and reproducing).`

- [ ] **Step 2: Trim the trailing follow-up sentence from line 44.**

In `CLAUDE.md` at the end of line 44, find the sentence:

```
 Surfaced one out-of-scope follow-up: the borderless `.screenSaver`-level cropper window can be edge-resized via macOS system gesture even though the style mask is just `.borderless` (pre-existing, predates pre-M6 cursor affordances — verified by rebuilding `df20ba4` and reproducing).
```

Delete that whole sentence (including the leading space). The line should now end with `…cursorIsOverRecordButton\` now feeds the override at every cursor case (not just crosshair).` (or whatever immediately preceded the deleted sentence — confirm by reading).

- [ ] **Step 3: Add a new status line for this fix.**

Immediately above the line that begins `- **M6 — Smoke + ship** is next:`, insert a new bullet. Use the variant matching your Task 4 branch:

**For branch A (setFrame clamp):**
```
- **Pre-M6 cropper edge-resize fix ✅ Complete** (commit `<HASH>`). Closes the long-standing AppKit/window-server quirk where the borderless `.screenSaver`-level `CropperWindow` accepted the macOS edge-drag resize gesture despite no `.resizable` in styleMask. Phase 1 diagnostic logging on `setFrame`/`mouseDown`/`mouseDragged` identified the AppKit path as `setFrame(_:display:)`; Phase 2 added a `setFrame(_:display:)` clamp pinned to a new `initialScreenFrame` property captured at init. Verified by manual smoke matrix (4 screen-edge drags + handles + body-drag + Esc/Enter/Space + Record); all pass.
```

**For branch B (`isMovable = false`):**
```
- **Pre-M6 cropper edge-resize fix ✅ Complete** (commit `<HASH>`). Closes the long-standing AppKit/window-server quirk where the borderless `.screenSaver`-level `CropperWindow` accepted the macOS edge-drag resize gesture despite no `.resizable` in styleMask. Phase 1 diagnostic logging on `setFrame`/`mouseDown`/`mouseDragged` showed mouse events drove the resize without going through `setFrame`; Phase 2 declined the gesture at the window layer with `self.isMovable = false` in `init`. Verified by manual smoke matrix (4 screen-edge drags + handles + body-drag + Esc/Enter/Space + Record); all pass.
```

Replace `<HASH>` with the short hash from `git log --oneline -1` (the commit from Task 5 step 4).

- [ ] **Step 4: Verify the edit reads correctly.**

Run: `sed -n '44,46p' CLAUDE.md`
Expected: line 44 ends without the trailing follow-up sentence; new "Pre-M6 cropper edge-resize fix" line follows; "M6 — Smoke + ship" line follows that.

---

## Task 7: Bookkeeping — delete project memory entry

**Files:**
- Delete: `~/.claude/projects/-Users-starship-src/memory/snatch_cropper_window_edge_resize_bug.md`
- Modify: `~/.claude/projects/-Users-starship-src/memory/MEMORY.md`

The memory entry exists only to flag a pending bug. With the bug fixed, it has no further use.

- [ ] **Step 1: Delete the memory file.**

Run: `rm ~/.claude/projects/-Users-starship-src/memory/snatch_cropper_window_edge_resize_bug.md`
Expected: file removed silently.

- [ ] **Step 2: Remove the index entry from MEMORY.md.**

In `~/.claude/projects/-Users-starship-src/memory/MEMORY.md`, find and delete the line:

```
- [Snatch cropper window edge-resize bug](snatch_cropper_window_edge_resize_bug.md) — borderless `.screenSaver` window resizes via system gesture; pre-existing, out of scope for pre-M6 cursor affordances
```

- [ ] **Step 3: Verify the index reflects the deletion.**

Run: `grep -c snatch_cropper_window_edge_resize_bug ~/.claude/projects/-Users-starship-src/memory/MEMORY.md || echo NONE`
Expected: prints `0` or `NONE`.

Note: memory files live outside the Snatch git repo and are not committed; no `git add` is needed for Task 7.

---

## Task 8: Commit bookkeeping

**Files:**
- `CLAUDE.md` (already modified by Task 6)

- [ ] **Step 1: Commit the CLAUDE.md status update.**

```
git add CLAUDE.md
git commit -m "docs: cropper edge-resize fix complete in CLAUDE.md status"
```

- [ ] **Step 2: Verify commit landed.**

Run: `git log --oneline -2`
Expected: shows the docs commit on top, the fix commit from Task 5 below it.

- [ ] **Step 3: Final smoke re-run.**

Quit and relaunch the app from the freshly-built `.app` (use Xcode's Run, or the `open -n "<APP_PATH>"` command from earlier). Run the 7-step smoke matrix one more time to make sure neither the bookkeeping nor any background change broke anything. All 7 must still pass.

If all pass, the plan is complete.

---

## Plan summary (after execution)

When this plan finishes successfully:
- `Sources/SnatchAppKit/CropperWindow.swift` has the chosen Phase 2 override (branch A or B).
- `CLAUDE.md` line 44's trailing follow-up sentence is gone; a new "Pre-M6 cropper edge-resize fix ✅ Complete" line sits above the M6 status line.
- The project-memory file `snatch_cropper_window_edge_resize_bug.md` is deleted; `MEMORY.md` no longer references it.
- Two new commits sit on `main`: one `fix(cropper): …`, one `docs: …`.
- The smoke matrix passes end-to-end.
