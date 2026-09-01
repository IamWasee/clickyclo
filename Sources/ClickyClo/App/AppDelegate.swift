//
//  AppDelegate.swift
//  ClickyClo
//
//  Stage 1 wiring: bring the transparent canvas up on every display and place the
//  Stage 1 verification target on it.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The Stage 1 acceptance target: a neon ring at exactly (500, 400) in
    /// top-left global coordinates — the same space a screenshot and a synthetic
    /// `CGEvent` click use, so what you see here is where later stages will click.
    static let stageOneTargetPosition = CGPoint(x: 500, y: 400)

    let overlayController = OverlayController()

    /// Identity of the Stage 1 target, retained so later stages can move or
    /// retire it instead of appending a second ring.
    private(set) var stageOneTargetID: UUID?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("ClickyClo launching (Stage 1: transparent overlay canvas)")

        overlayController.start()
        installStageOneTarget()
        overlayController.setVisible(true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController.stop()
        Log.app.info("ClickyClo terminated")
    }

    /// The overlay is not a document window; closing it must never quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Stage 1 content

    private func installStageOneTarget() {
        let position = ScreenGeometry.clampToVisibleDesktop(topLeft: Self.stageOneTargetPosition)

        if position != Self.stageOneTargetPosition {
            let clamped = String(format: "(%.0f, %.0f)", position.x, position.y)
            Log.overlay.notice(
                "Stage 1 target (500, 400) is off-screen on this display layout; clamped to \(clamped, privacy: .public)"
            )
        }

        let target = OverlayTarget(
            position: position,
            radius: OverlayMetrics.defaultRingRadius,
            label: String(format: "Target  %.0f, %.0f", position.x, position.y),
            style: .neonBlue
        )

        stageOneTargetID = target.id
        overlayController.upsert(target)
    }
}
