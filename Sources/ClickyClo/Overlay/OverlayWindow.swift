//
//  OverlayWindow.swift
//  ClickyClo
//
//  A borderless, click-through, always-on-top window that covers exactly one
//  display. One window per display (rather than a single window spanning the whole
//  desktop) is deliberate:
//
//    • Each window renders at its own display's backing scale, so the ring is
//      crisp on a Retina laptop and a 1x external monitor simultaneously.
//    • A window is never larger than a single display, which keeps the window
//      server's damage rectangles small.
//    • Displays can be hot-plugged without resizing a giant shared surface.
//

import AppKit

final class OverlayWindow: NSWindow {

    /// The display this window is pinned to. Stable across `NSScreen` object churn.
    let displayID: CGDirectDisplayID

    private let overlayView: OverlayView

    // MARK: - Init

    init(screen: NSScreen) {
        self.displayID = ScreenGeometry.displayID(for: screen)
        self.overlayView = OverlayView(screenFrame: screen.frame)

        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false,
                   screen: screen)

        configureWindow()
        contentView = overlayView
        setFrame(screen.frame, display: false)
    }

    private func configureWindow() {
        // --- Transparency -------------------------------------------------
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // --- Click-through --------------------------------------------------
        // The window never becomes key or main, never accepts mouse events, and
        // never steals focus from the app the user is actually working in.
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false

        // --- Stacking -------------------------------------------------------
        // `.screenSaver` sits above normal windows, floating panels, and the menu
        // bar, which is what a guidance overlay needs.
        level = .screenSaver

        // --- Spaces and full-screen ------------------------------------------
        // `.canJoinAllSpaces` makes the window follow the user across Spaces
        // instantly instead of triggering a Space switch;
        // `.fullScreenAuxiliary` lets it float over another app's full-screen
        // Space; `.stationary` stops Mission Control from animating it around;
        // `.ignoresCycle` keeps it out of Cmd-` window cycling.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // --- Housekeeping -----------------------------------------------------
        isMovable = false
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        tabbingMode = .disallowed

        // No implicit AppKit fade — Stage 2 drives visibility explicitly and a
        // system animation would fight it.
        animationBehavior = .none

        // Keep the overlay out of screen sharing and out of our own screenshots
        // (Stage 3 must capture the user's desktop, not our own ring).
        sharingType = .none
    }

    // MARK: - Focus policy

    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    // MARK: - Geometry

    /// Re-pins the window to a display after a resolution change, arrangement
    /// change, or dock/menu-bar layout change.
    func fit(to screen: NSScreen) {
        let frame = screen.frame
        if self.frame != frame {
            setFrame(frame, display: true)
        }
        overlayView.frame = CGRect(origin: .zero, size: frame.size)
        overlayView.screenFrame = frame
    }

    // MARK: - Content

    func update(targets: [OverlayTarget]) {
        overlayView.update(targets: targets)
    }

    /// Forces a full repaint — used after a display reconfiguration, where the
    /// global-to-local mapping changed for every target at once.
    func redraw() {
        overlayView.needsDisplay = true
    }
}
