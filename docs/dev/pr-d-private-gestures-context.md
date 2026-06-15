# PR D handoff — advanced private-API gestures (context export)

> Purpose: hand this to Claude Code (or any dev) in a **macOS + Xcode**
> environment to implement PR D. It was deferred from the gesture-support work
> because the private gesture-event constants cannot be verified on Linux
> (wrong constants silently no-op or crash). A/B/C shipped on branch
> `claude/logi-m337-gesture-support-fu2978`; D continues on the same branch.

## Goal
Add "advanced" gesture actions that feel like a trackpad, using private/
undocumented macOS APIs (the user explicitly opted into private APIs):

1. **Continuous Spaces swipe** — dragging left/right on a held button drives a
   follow-finger Spaces switch (BetterMouse style), not a one-shot ⌃←/⌃→.
2. **Smart Zoom** — the two-finger double-tap smart zoom.
3. **Pinch zoom in / out** — magnify gesture.
4. **3-finger swipes** — up (Mission Control), down (App Exposé), left/right.
5. **Look Up — NATIVE, not the ⌃⌘D keystroke.** The user rejects keystrokes
   because they get intercepted/remapped (e.g. Rectangle Pro grabs ⌃⌘), and a
   user who wants keystroke behavior can already bind a key to a button. Must
   trigger the inline dictionary popover via the gesture/native path.

## How the existing gesture + action plumbing works (reuse this)

### Discrete actions (Smart Zoom, Look Up, pinch, 3-finger one-shots)
Mirror the **media-key** pattern added in PR C — it's the cleanest template:
- `Mos/Shortcut/SystemShortcut.swift`
  - Add `Shortcut("smartZoom", 0xFFFA, .init(rawValue: N))` style entries
    (pick an unused placeholder code; existing placeholders: 0xFFFF mouse,
    0xFFFE logi, 0xFFFD modifier, 0xFFFC mosScroll, 0xFFFB media — use **0xFFFA**).
  - Add to `allShortcuts`, add `symbolName` cases, add a category tuple
    (e.g. `advancedGesturesCategory`) like `mediaKeysCategory`.
- `Mos/Shortcut/ShortcutManager.swift` (`buildShortcutMenu`) — add the category
  via `addCategoryToMenu(...)` next to the media-keys block.
- `Mos/Shortcut/ShortcutExecutor.swift`
  - Add an action-kind enum like `MediaKeyActionKind` (e.g. `GestureSynthKind`).
  - Add `case gestureSynth(kind:)` to `ResolvedAction` (executionMode `.trigger`).
  - Add a branch in `resolveAction(named:)` and a `case` in `execute(action:phase:)`.
  - Add `executeGestureSynth(_:)` that calls into the facade (below).
- `Mos/Localizable.xcstrings` — add names + category (en + zh-Hans/Hant/HK/TW).
  Insert textually after the `  "strings": {` line to preserve Xcode format
  (see how PR C's media keys were inserted; the file uses `"key" : value`).
- Tests: mirror `testResolveAction_mediaKeysResolveToMediaKeyActionAndAreTrigger`
  in `MosTests/InputProcessorTests.swift`.

### Continuous swipe (drag-driven)
The runtime already has a drag stream:
- `Mos/InputEvent/MouseGestureController.swift`
  - `handleDown` creates a per-button `Session`; `handleMove(toCGLocation:)`
    feeds the recognizer; `handleScroll(dx:dy:)` (added in PR B) is the analogous
    consume path for the wheel.
  - For continuous swipe you want raw incremental drag deltas (not just the
    one-shot `dragLeft/Right` the recognizer emits). Options:
    a) Add a "continuous" armed flag on the session; while held + a continuous-
       swipe binding matches, forward each motion delta to the facade as swipe
       `phase: .began/.changed/.ended` with a cumulative fraction, and suppress
       the discrete drag emit.
    b) Simpler first cut: keep the discrete `dragLeft/Right` recognition but, on
       recognize, fire a *complete* swipe animation via the facade. Less
       "follow-finger" but far less fragile. Recommend starting here, then
       upgrading to (a) once the private swipe path is proven.
  - The motion tap is `setRealMotionTapActive` / `motionCallback`.

## Isolation (required)
Put **all** private/undocumented usage behind one facade so the blast radius is
contained and everything has a graceful fallback:

```
Mos/Integration/GestureSynth/
  GestureSynth.swift        // public-ish API: smartZoom(), lookUp(), pinch(_),
                            // missionControl(), appExpose(), spacesSwipe(phase:fraction:)
  GestureSynthPrivate.swift // the CGEvent/SkyLight calls, availability-gated
```
- Note the repo enforces a module boundary via `scripts/qa/lint-logi-boundary.sh`
  but that lint only governs **Logi** symbols. GestureSynth is self-contained and
  must NOT reference Logi internals, so it won't trip the lint. Keep it that way.
- Every facade method must degrade safely (no-op or documented fallback) if the
  private call is unavailable on the running macOS version.

## Private-API techniques to SPIKE (verify each on device — do not trust blindly)

These are starting points, not confirmed constants. Validate against the target
macOS version with a tiny harness app + Console before wiring into Mos.

- **Spaces / dock swipe (continuous):** synthesized "dock swipe" gesture events.
  Investigate `CGEventCreate(nil)` + setting the event type to the dock-swipe
  type and posting begin/changed/ended phases with a 0→1 fraction; or the
  SkyLight/`CGSConnection` `SLSGesture`-family calls. Reference implementations:
  BetterTouchTool / BetterMouse / `Hammerspoon`'s gesture code, and the
  open-source `swipe`/`dockSwipe` CGEvent experiments. This is the most fragile
  piece — prove it in isolation first.
- **Magnify / pinch:** `NSEvent.EventType.magnify` exists publicly but there is
  no public constructor that posts to other apps; spike a CGEvent with the
  magnify type + magnification field. Smart zoom maps to
  `NSEvent.EventType.smartMagnify`.
- **Mission Control / App Exposé / Spaces (discrete fallback):** these have
  RELIABLE public keystrokes already in the catalog (`missionControl` is a
  function-key shortcut; `moveSpaceLeft/Right` exist). Use them as the fallback
  when the private swipe path is unavailable.
- **Look Up (native):** the inline popover is driven by the three-finger-tap /
  force-touch "look up" gesture (private). Alternative, more public route:
  read the focused element's `AXSelectedText` via the Accessibility API and call
  Dictionary Services (`DCSCopyTextDefinition`) to fetch the definition, then
  present it in a Mos popover. That avoids the keystroke AND avoids the most
  fragile private gesture, at the cost of not using the system's own popover.
  Decide with the user which "native" they prefer. **Do NOT add a ⌃⌘D fallback
  for Look Up** — keep it native-only per the user's explicit instruction.

## Fallback policy
- Prefer another native path before any keystroke fallback.
- For actions with a safe public keystroke (Spaces, Mission Control, App Exposé)
  fall back to that keystroke when the private path is unavailable.
- Look Up: native-only, no keystroke fallback.

## Verification (on device, M337)
1. `xcodebuild -scheme Mos -configuration Debug build` then run the **Debug**
   build (bundle id `com.caldis.Mos.debug` — see `accessibility-and-state.md`
   for why; grant Accessibility to "Mos Debug").
2. `xcodebuild test` (MosTests) — pure logic tests must stay green.
3. Bind each new action to the M337 gesture button (record it) and confirm:
   - Smart Zoom toggles zoom in a Smart-Zoom-aware app (Safari/Preview).
   - Pinch in/out zooms.
   - 3-finger up/down/left/right hit Mission Control / App Exposé / Spaces.
   - Continuous "drag left/right while holding" animates Spaces following the
     drag (or, in the first cut, completes a Spaces switch).
   - Look Up shows the dictionary popover for the selected word, regardless of
     the user's keyboard-shortcut config (test with ⌃⌘ remapped by another app).
   - Each action degrades gracefully (no crash / no stuck state) if the private
     path is unavailable.

## Branch / process
- Work on `claude/logi-m337-gesture-support-fu2978` (all tracks on one branch,
  per the user's decision). Scoped commits, one concern each.
- Do NOT open a PR unless the user asks.
- Commit-message trailer used in this work:
  `https://claude.ai/code/session_01JFxYxEr7hhs1d8eCpM7cnj`

## Pointers (files touched by A/B/C, for reference)
- Model/recognizer: `Mos/InputEvent/MouseGesture.swift`,
  `MouseGestureRecognizer.swift`, `MouseGestureController.swift`,
  `MouseGestureCapture.swift`.
- Scroll integration: `Mos/ScrollCore/ScrollCore.swift` (`scrollEventCallBack`).
- Actions: `Mos/Shortcut/SystemShortcut.swift`, `ShortcutManager.swift`,
  `ShortcutExecutor.swift`.
- Recording: `Mos/Keys/KeyRecorder.swift`.
- Tests: `MosTests/InputProcessorTests.swift`.
