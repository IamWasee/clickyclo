//
//  OverlayTarget.swift
//  ClickyClo
//
//  The value type that describes one thing drawn on the canvas. Everything the
//  renderer needs lives here, so later stages (an AI response, a cursor follower,
//  an accessibility bounding box) only have to produce `OverlayTarget` values —
//  they never touch drawing code.
//

import AppKit
import CoreGraphics

struct OverlayTarget: Identifiable, Equatable {

    // MARK: - Style

    /// A palette for one indicator. Colours are built in sRGB explicitly so the
    /// neon stays identical on a P3 Retina panel and an external sRGB monitor.
    struct Style: Equatable {

        let ringColor: NSColor
        let glowColor: NSColor
        let coreColor: NSColor
        let labelTextColor: NSColor
        let labelBackgroundColor: NSColor

        /// The default "Clicky" look: an electric cyan-blue ring with a soft bloom.
        static let neonBlue = Style(
            ringColor: NSColor(srgbRed: 0.16, green: 0.78, blue: 1.00, alpha: 1.00),
            glowColor: NSColor(srgbRed: 0.11, green: 0.62, blue: 1.00, alpha: 1.00),
            coreColor: NSColor(srgbRed: 0.85, green: 0.97, blue: 1.00, alpha: 1.00),
            labelTextColor: NSColor(srgbRed: 0.92, green: 0.98, blue: 1.00, alpha: 1.00),
            labelBackgroundColor: NSColor(srgbRed: 0.02, green: 0.05, blue: 0.09, alpha: 0.78)
        )

        /// Reserved for destructive or "agent is about to click" confirmations in
        /// later stages; defined now so the palette lives in exactly one place.
        static let alertAmber = Style(
            ringColor: NSColor(srgbRed: 1.00, green: 0.72, blue: 0.23, alpha: 1.00),
            glowColor: NSColor(srgbRed: 1.00, green: 0.52, blue: 0.10, alpha: 1.00),
            coreColor: NSColor(srgbRed: 1.00, green: 0.94, blue: 0.82, alpha: 1.00),
            labelTextColor: NSColor(srgbRed: 1.00, green: 0.97, blue: 0.90, alpha: 1.00),
            labelBackgroundColor: NSColor(srgbRed: 0.09, green: 0.05, blue: 0.01, alpha: 0.78)
        )
    }

    // MARK: - Stored properties

    let id: UUID

    /// Centre of the indicator in **top-left global (CoreGraphics) points**.
    /// See `ScreenGeometry` for why this convention is the canonical one.
    var position: CGPoint

    /// Radius of the primary ring, in points.
    var radius: CGFloat

    /// Optional caption rendered in a capsule beneath the ring.
    var label: String?

    var style: Style

    /// Lets a target be parked without being destroyed, so its identity (and in
    /// Stage 6, its animation state) survives a hide/show cycle.
    var isVisible: Bool

    // MARK: - Init

    init(id: UUID = UUID(),
         position: CGPoint,
         radius: CGFloat = OverlayMetrics.defaultRingRadius,
         label: String? = nil,
         style: Style = .neonBlue,
         isVisible: Bool = true) {
        self.id = id
        self.position = position
        self.radius = radius
        self.label = label
        self.style = style
        self.isVisible = isVisible
    }
}

/// Layout constants for the indicator. Tuned as multiples of the ring radius so a
/// target scales coherently when the AI asks for a larger or smaller highlight.
enum OverlayMetrics {

    static let defaultRingRadius: CGFloat = 26

    /// Stroke width of the primary ring.
    static let ringLineWidth: CGFloat = 2.5

    /// Radius of the faint inner ring, as a fraction of the primary radius.
    static let innerRingScale: CGFloat = 0.68

    /// Blur radius of the bloom drawn behind the primary ring.
    static let bloomBlur: CGFloat = 12

    /// Outer edge of the radial halo, as a multiple of the primary radius.
    static let haloScale: CGFloat = 2.15

    /// Radius of the solid centre dot.
    static let coreRadius: CGFloat = 3.0

    /// Crosshair ticks run from `tickInnerScale` to `tickOuterScale` × radius.
    static let tickInnerScale: CGFloat = 1.20
    static let tickOuterScale: CGFloat = 1.46
    static let tickLineWidth: CGFloat = 2.0

    /// Label capsule geometry.
    static let labelFontSize: CGFloat = 11.5
    static let labelPaddingHorizontal: CGFloat = 9
    static let labelPaddingVertical: CGFloat = 4
    static let labelGap: CGFloat = 12

    /// Slack added to a target's dirty rect so bloom, shadow and antialiasing are
    /// never clipped by a partial redraw.
    static let redrawPadding: CGFloat = 8
}
