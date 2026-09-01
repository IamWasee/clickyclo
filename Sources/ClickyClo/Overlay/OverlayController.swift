//
//  OverlayController.swift
//  ClickyClo
//
//  Owns the fleet of overlay windows and the single source of truth for what is
//  drawn on them. Callers work exclusively in top-left global coordinates and
//  never see `NSWindow` — later stages (hotkey, AI response, agent execution)
//  talk to this object only.
//

import AppKit
import CoreGraphics

@MainActor
final class OverlayController {

    // MARK: - State

    /// Overlay windows keyed by the display they cover.
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]

    /// The single source of truth for on-screen content, in draw order.
    private(set) var targets: [OverlayTarget] = []

    private(set) var isRunning = false

    private(set) var isVisible = false

    private var screenObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// Creates a window per attached display and starts tracking display changes.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        synchronizeWindowsWithScreens()
        observeScreenChanges()

        Log.overlay.info("Overlay started across \(self.windows.count, privacy: .public) display(s)")
        Log.geometry.info("Displays: \(ScreenGeometry.describeDisplays(), privacy: .public)")
    }

    /// Tears every window down. Safe to call more than once.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        isVisible = false

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()

        Log.overlay.info("Overlay stopped")
    }

    // MARK: - Visibility

    /// Shows or hides every overlay window.
    ///
    /// Visibility is instantaneous here by design: Stage 2 layers a hotkey-driven
    /// `NSAnimationContext` fade on top of this primitive, and an implicit
    /// animation at this level would double up with it.
    func setVisible(_ visible: Bool) {
        guard isRunning else { return }
        guard visible != isVisible else { return }
        isVisible = visible

        for window in windows.values {
            if visible {
                window.alphaValue = 1
                // `orderFrontRegardless` is required for an accessory app: the
                // process is never "active", so a plain `orderFront` can be
                // ignored by the window server.
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }

        Log.overlay.debug("Overlay visibility -> \(visible, privacy: .public)")
    }

    /// Direct access to the window list, for stages that need to animate window
    /// properties (Stage 2's fade) without owning the fleet.
    var overlayWindows: [OverlayWindow] {
        Array(windows.values)
    }

    // MARK: - Targets

    /// Replaces every target on the canvas.
    func setTargets(_ newTargets: [OverlayTarget]) {
        targets = newTargets
        pushTargetsToWindows()
    }

    /// Adds a target, or replaces the existing one with the same identity.
    func upsert(_ target: OverlayTarget) {
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            targets[index] = target
        } else {
            targets.append(target)
        }
        pushTargetsToWindows()
    }

    @discardableResult
    func removeTarget(id: UUID) -> Bool {
        let countBefore = targets.count
        targets.removeAll { $0.id == id }
        guard targets.count != countBefore else { return false }
        pushTargetsToWindows()
        return true
    }

    func clearTargets() {
        guard !targets.isEmpty else { return }
        targets.removeAll()
        pushTargetsToWindows()
    }

    /// Moves an existing target to a new top-left global position, clamping it
    /// onto a real display so a bad coordinate can never strand the indicator.
    @discardableResult
    func moveTarget(id: UUID, to position: CGPoint) -> Bool {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return false }
        targets[index].position = ScreenGeometry.clampToVisibleDesktop(topLeft: position)
        pushTargetsToWindows()
        return true
    }

    private func pushTargetsToWindows() {
        for window in windows.values {
            window.update(targets: targets)
        }
    }

    // MARK: - Display management

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification is delivered on the main queue, but the closure is
            // not statically main-actor isolated; hop explicitly rather than
            // relying on a runtime assumption.
            Task { @MainActor in
                self?.handleScreenParametersChanged()
            }
        }
    }

    private func handleScreenParametersChanged() {
        guard isRunning else { return }
        Log.geometry.info("Display configuration changed: \(ScreenGeometry.describeDisplays(), privacy: .public)")
        synchronizeWindowsWithScreens()

        // Every target's global-to-local mapping may have shifted (the main
        // display's height is the pivot for the whole coordinate system), so force
        // a full repaint rather than trusting incremental dirty rects.
        for window in windows.values {
            window.redraw()
        }
    }

    /// Reconciles the window fleet with the currently attached displays: creates
    /// windows for new displays, re-fits surviving ones, and closes orphans.
    private func synchronizeWindowsWithScreens() {
        let screens = NSScreen.screens
        var liveDisplayIDs = Set<CGDirectDisplayID>()

        for screen in screens {
            let id = ScreenGeometry.displayID(for: screen)
            liveDisplayIDs.insert(id)

            if let existing = windows[id] {
                existing.fit(to: screen)
                existing.update(targets: targets)
                if isVisible {
                    existing.orderFrontRegardless()
                }
            } else {
                let window = OverlayWindow(screen: screen)
                window.update(targets: targets)
                windows[id] = window
                if isVisible {
                    window.alphaValue = 1
                    window.orderFrontRegardless()
                }
                Log.overlay.debug("Created overlay window for display \(id, privacy: .public)")
            }
        }

        for (id, window) in windows where !liveDisplayIDs.contains(id) {
            window.orderOut(nil)
            window.close()
            windows.removeValue(forKey: id)
            Log.overlay.debug("Removed overlay window for detached display \(id, privacy: .public)")
        }
    }
}
