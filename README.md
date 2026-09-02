# ClickyClo

A screen-aware AI desktop companion for macOS — a native Swift take on the "Hey Clicky"
idea: a transparent guidance layer that lives next to your cursor, sees your screen,
listens to your voice, and can drive the machine on your behalf.

Built in ten sequential stages. Each stage lands as complete, runnable code.

| Stage | Scope | Status |
| ----- | ----- | ------ |
| 1 | Transparent overlay canvas (borderless, click-through, multi-display, multi-Space) | ✅ Done |
| 2 | Global hotkey listener + animated fade | ⏳ Not started |
| 3 | ScreenCaptureKit snapshot pipeline | ⏳ Not started |
| 4 | AVAudioEngine microphone streaming | ⏳ Not started |
| 5 | Claude vision API layer with structured coordinate output | ⏳ Not started |
| 6 | CoreAnimation indicator movement + display-scale mapping | ⏳ Not started |
| 7 | `CGEvent` synthetic input (Agent Mode) | ⏳ Not started |
| 8 | Accessibility (`AXUIElement`) element inspection | ⏳ Not started |
| 9 | Shell + AppleScript tool bridge | ⏳ Not started |
| 10 | Menu bar control, safety guardrails, error handling | ⏳ Not started |

## Requirements

- macOS 13 Ventura or newer
- Swift 5.9 toolchain (Xcode 15+ command line tools)

## Build and run

```bash
./scripts/build_app.sh --run     # release build, bundle as .app, launch
./scripts/build_app.sh --debug   # unoptimised build with debug symbols
./scripts/build_app.sh --spm     # build through SwiftPM instead of swiftc
```

`build_app.sh` compiles the sources **directly with `swiftc`** and wraps the result
in a real `.app` bundle. ClickyClo has no external dependencies, so SwiftPM adds
nothing at build time — and a partially-installed Command Line Tools ships a
`PackageDescription` library that fails to link, which breaks `swift build` before
it ever reaches our code (`Invalid manifest ... Undefined symbols:
PackageDescription.Package.__allocating_init`). Compiling directly sidesteps that
entirely. `Package.swift` is kept for Xcode and healthy SwiftPM toolchains; use
`--spm` to go through it. That bundle is not
cosmetic: `Info.plist` carries `LSUIElement` (no Dock tile, no Cmd-Tab entry, never
steals focus) and, from Stage 3 onward, the TCC usage strings behind the Screen
Recording and Microphone prompts.

ClickyClo runs as a background accessory app with no window of its own, so quit it with:

```bash
pkill -x ClickyClo
```

Logs stream to the unified log:

```bash
log stream --predicate 'subsystem == "com.clickyclo.companion"' --level debug
```

## Stage 1 — the transparent overlay canvas

Launching the app draws a neon-blue target ring at global coordinate **(500, 400)**.
It floats above every window, follows you across Spaces without a Space switch, sits on
top of other apps' full-screen Spaces, and every click passes straight through it to
whatever is underneath.

### Architecture

```
main.swift                      NSApplication bootstrap, .accessory activation policy
App/AppDelegate.swift           Stage wiring: start the overlay, install the target
Overlay/OverlayController.swift Window fleet + single source of truth for content
Overlay/OverlayWindow.swift     One borderless click-through window per display
Overlay/OverlayView.swift       CoreGraphics renderer (halo, ring, ticks, core, label)
Overlay/OverlayTarget.swift     Value type describing one indicator + style + metrics
Support/ScreenGeometry.swift    Top-left ⇄ bottom-left coordinate conversion
Support/Log.swift               Category-scoped os.Logger instances
```

### Design decisions worth knowing

**One window per display, not one window spanning the desktop.** A window that straddles
a Retina laptop and a 1x external monitor renders at a single backing scale and looks
soft on one of them. Per-display windows each render natively, keep the window server's
damage rectangles small, and survive hot-plugging.

**Top-left coordinates are canonical.** macOS has two global coordinate spaces:
CoreGraphics (origin top-left, +y down — what `CGEvent`, `CGDisplayBounds`,
ScreenCaptureKit and any vision model reading a screenshot use) and AppKit (origin
bottom-left, +y up — what `NSScreen` and `NSWindow` use). ClickyClo speaks CoreGraphics
everywhere content crosses a boundary and converts to AppKit only at draw time, in
`ScreenGeometry`. This is why the Stage 1 ring at (500, 400) will land exactly where a
Stage 7 synthetic click at (500, 400) lands.

**Click-through is enforced twice.** The window sets `ignoresMouseEvents = true`, and the
view's `hitTest(_:)` returns `nil` unconditionally, so the canvas stays transparent to
input even if a later stage needs to flip the window flag for a hover interaction.

**The overlay excludes itself from capture.** `sharingType = .none` keeps the ring out of
screen sharing and out of Stage 3's own screenshots — the AI must see the user's desktop,
not ClickyClo's guidance layer.

### Collection behavior

`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]` — follow the user
across Spaces without triggering a switch, don't get shuffled by Mission Control, float
over full-screen apps, and stay out of window cycling.
