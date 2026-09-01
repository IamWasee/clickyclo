//
//  OverlayView.swift
//  ClickyClo
//
//  The canvas. One instance backs one physical display, and it renders every
//  target whose geometry intersects that display. Two hard rules govern this view:
//
//    1. It must never consume an event. `hitTest` returns nil unconditionally, so
//       even if the window's `ignoresMouseEvents` were flipped off by a later
//       stage, clicks still fall through to whatever is underneath.
//    2. It must never paint an opaque pixel outside a target. The context is
//       cleared to transparent on every pass; the desktop shows through.
//

import AppKit
import CoreGraphics

final class OverlayView: NSView {

    // MARK: - State

    private(set) var targets: [OverlayTarget] = []

    /// Frame of the display this view covers, in AppKit global coordinates.
    /// Used to translate global target positions into view-local points.
    var screenFrame: CGRect {
        didSet {
            guard screenFrame != oldValue else { return }
            needsDisplay = true
        }
    }

    // MARK: - Init

    init(screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        // The canvas is mostly empty; drawing asynchronously keeps a full-screen
        // invalidation off the critical path of the window server.
        layer?.drawsAsynchronously = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlayView is created programmatically only")
    }

    // MARK: - Event transparency

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

    override var isOpaque: Bool { false }

    override var mouseDownCanMoveWindow: Bool { false }

    /// AppKit's default (bottom-left origin) coordinate space is retained so the
    /// conversion from `ScreenGeometry` is a single subtraction with no flip.
    override var isFlipped: Bool { false }

    // MARK: - Target updates

    /// Replaces the target list and invalidates only the affected regions.
    func update(targets newTargets: [OverlayTarget]) {
        let previous = targets
        targets = newTargets

        guard previous != newTargets else { return }

        var dirty = CGRect.null
        for target in previous where target.isVisible {
            dirty = dirty.union(drawingBounds(for: target))
        }
        for target in newTargets where target.isVisible {
            dirty = dirty.union(drawingBounds(for: target))
        }

        if dirty.isNull {
            // Nothing was visible before and nothing is visible now, but the model
            // changed (e.g. a hidden target moved). A cheap full invalidation keeps
            // the view honest without special-casing every field.
            needsDisplay = true
            return
        }

        // Beyond roughly a third of the canvas, per-rect invalidation costs more in
        // bookkeeping than it saves in fill rate.
        let dirtyArea = dirty.width * dirty.height
        let totalArea = bounds.width * bounds.height
        if totalArea > 0, dirtyArea / totalArea > 0.33 {
            needsDisplay = true
            return
        }

        // A target that lives entirely on another display produces an empty
        // intersection here; nothing on this canvas needs repainting.
        let visibleDirty = dirty.intersection(bounds)
        if !visibleDirty.isEmpty {
            setNeedsDisplay(visibleDirty)
        }
    }

    // MARK: - Coordinate conversion

    /// Top-left global point → view-local point on this display.
    private func viewPoint(fromGlobalTopLeft point: CGPoint) -> CGPoint {
        let appKit = ScreenGeometry.appKitPoint(fromTopLeft: point)
        return CGPoint(x: appKit.x - screenFrame.minX,
                       y: appKit.y - screenFrame.minY)
    }

    /// The full invalidation rect for a target, including bloom and label.
    private func drawingBounds(for target: OverlayTarget) -> CGRect {
        let center = viewPoint(fromGlobalTopLeft: target.position)
        let halo = max(target.radius * OverlayMetrics.haloScale,
                       target.radius * OverlayMetrics.tickOuterScale + OverlayMetrics.bloomBlur)

        var rect = CGRect(x: center.x - halo,
                          y: center.y - halo,
                          width: halo * 2,
                          height: halo * 2)

        if let label = target.label, !label.isEmpty {
            rect = rect.union(labelRect(for: label, target: target, center: center))
        }

        return rect.insetBy(dx: -OverlayMetrics.redrawPadding, dy: -OverlayMetrics.redrawPadding)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Start from genuine transparency: the window is non-opaque, so anything we
        // do not paint is the live desktop.
        context.clear(dirtyRect)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        for target in targets where target.isVisible {
            let bounds = drawingBounds(for: target)
            guard bounds.intersects(dirtyRect) else { continue }
            draw(target, in: context)
        }
    }

    private func draw(_ target: OverlayTarget, in context: CGContext) {
        let center = viewPoint(fromGlobalTopLeft: target.position)
        let radius = target.radius
        let style = target.style

        drawHalo(around: center, radius: radius, style: style, in: context)
        drawPrimaryRing(around: center, radius: radius, style: style, in: context)
        drawInnerRing(around: center, radius: radius, style: style, in: context)
        drawCrosshairTicks(around: center, radius: radius, style: style, in: context)
        drawCore(at: center, style: style, in: context)

        if let label = target.label, !label.isEmpty {
            drawLabel(label, for: target, center: center, in: context)
        }
    }

    /// Soft radial falloff that sells the "light source on glass" look.
    private func drawHalo(around center: CGPoint,
                          radius: CGFloat,
                          style: OverlayTarget.Style,
                          in context: CGContext) {
        let outerRadius = radius * OverlayMetrics.haloScale
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }

        let colors = [
            style.glowColor.withAlphaComponent(0.34).cgColor,
            style.glowColor.withAlphaComponent(0.14).cgColor,
            style.glowColor.withAlphaComponent(0.0).cgColor
        ] as CFArray

        guard let gradient = CGGradient(colorsSpace: colorSpace,
                                        colors: colors,
                                        locations: [0.0, 0.55, 1.0]) else { return }

        context.saveGState()
        context.addEllipse(in: CGRect(x: center.x - outerRadius,
                                      y: center.y - outerRadius,
                                      width: outerRadius * 2,
                                      height: outerRadius * 2))
        context.clip()
        context.drawRadialGradient(gradient,
                                   startCenter: center,
                                   startRadius: radius * 0.55,
                                   endCenter: center,
                                   endRadius: outerRadius,
                                   options: [])
        context.restoreGState()
    }

    /// The main ring, stroked twice: once as a wide blurred bloom, once crisp.
    private func drawPrimaryRing(around center: CGPoint,
                                 radius: CGFloat,
                                 style: OverlayTarget.Style,
                                 in context: CGContext) {
        let rect = CGRect(x: center.x - radius,
                          y: center.y - radius,
                          width: radius * 2,
                          height: radius * 2)

        context.saveGState()
        context.setShadow(offset: .zero,
                          blur: OverlayMetrics.bloomBlur,
                          color: style.glowColor.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(OverlayMetrics.ringLineWidth)
        context.setStrokeColor(style.ringColor.cgColor)
        context.strokeEllipse(in: rect)
        context.restoreGState()

        // Second pass without the shadow so the stroke itself stays sharp on top
        // of its own bloom.
        context.saveGState()
        context.setLineWidth(OverlayMetrics.ringLineWidth)
        context.setStrokeColor(style.ringColor.cgColor)
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    private func drawInnerRing(around center: CGPoint,
                               radius: CGFloat,
                               style: OverlayTarget.Style,
                               in context: CGContext) {
        let innerRadius = radius * OverlayMetrics.innerRingScale
        context.saveGState()
        context.setLineWidth(1)
        context.setStrokeColor(style.ringColor.withAlphaComponent(0.38).cgColor)
        context.strokeEllipse(in: CGRect(x: center.x - innerRadius,
                                         y: center.y - innerRadius,
                                         width: innerRadius * 2,
                                         height: innerRadius * 2))
        context.restoreGState()
    }

    /// Four ticks at the compass points, which read as "aiming" far better than a
    /// bare circle and give the eye an anchor while the ring animates in Stage 6.
    private func drawCrosshairTicks(around center: CGPoint,
                                    radius: CGFloat,
                                    style: OverlayTarget.Style,
                                    in context: CGContext) {
        let inner = radius * OverlayMetrics.tickInnerScale
        let outer = radius * OverlayMetrics.tickOuterScale

        context.saveGState()
        context.setLineWidth(OverlayMetrics.tickLineWidth)
        context.setLineCap(.round)
        context.setStrokeColor(style.ringColor.withAlphaComponent(0.85).cgColor)
        context.setShadow(offset: .zero,
                          blur: OverlayMetrics.bloomBlur * 0.5,
                          color: style.glowColor.withAlphaComponent(0.7).cgColor)

        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: 1),
            CGPoint(x: 0, y: -1),
            CGPoint(x: 1, y: 0),
            CGPoint(x: -1, y: 0)
        ]

        for offset in offsets {
            context.move(to: CGPoint(x: center.x + offset.x * inner,
                                     y: center.y + offset.y * inner))
            context.addLine(to: CGPoint(x: center.x + offset.x * outer,
                                        y: center.y + offset.y * outer))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawCore(at center: CGPoint,
                          style: OverlayTarget.Style,
                          in context: CGContext) {
        let coreRadius = OverlayMetrics.coreRadius
        context.saveGState()
        context.setShadow(offset: .zero,
                          blur: OverlayMetrics.bloomBlur * 0.75,
                          color: style.glowColor.withAlphaComponent(0.95).cgColor)
        context.setFillColor(style.coreColor.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - coreRadius,
                                       y: center.y - coreRadius,
                                       width: coreRadius * 2,
                                       height: coreRadius * 2))
        context.restoreGState()
    }

    // MARK: - Label

    private func labelAttributes(for style: OverlayTarget.Style) -> [NSAttributedString.Key: Any] {
        [
            .font: OverlayView.labelFont,
            .foregroundColor: style.labelTextColor,
            .kern: 0.2
        ]
    }

    /// Rounded system font when available (matches the macOS control look), plain
    /// system font otherwise.
    private static let labelFont: NSFont = {
        let base = NSFont.systemFont(ofSize: OverlayMetrics.labelFontSize, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: OverlayMetrics.labelFontSize) else {
            return base
        }
        return rounded
    }()

    private func labelRect(for text: String,
                           target: OverlayTarget,
                           center: CGPoint) -> CGRect {
        let attributes = labelAttributes(for: target.style)
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = CGSize(width: ceil(textSize.width) + OverlayMetrics.labelPaddingHorizontal * 2,
                          height: ceil(textSize.height) + OverlayMetrics.labelPaddingVertical * 2)
        let origin = CGPoint(x: center.x - size.width / 2,
                             y: center.y - target.radius * OverlayMetrics.tickOuterScale
                                - OverlayMetrics.labelGap - size.height)
        return CGRect(origin: origin, size: size).integral
    }

    private func drawLabel(_ text: String,
                           for target: OverlayTarget,
                           center: CGPoint,
                           in context: CGContext) {
        let style = target.style
        let rect = labelRect(for: text, target: target, center: center)
        let path = CGPath(roundedRect: rect,
                          cornerWidth: rect.height / 2,
                          cornerHeight: rect.height / 2,
                          transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1),
                          blur: 8,
                          color: NSColor.black.withAlphaComponent(0.55).cgColor)
        context.addPath(path)
        context.setFillColor(style.labelBackgroundColor.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setLineWidth(1)
        context.setStrokeColor(style.ringColor.withAlphaComponent(0.55).cgColor)
        context.strokePath()
        context.restoreGState()

        let attributes = labelAttributes(for: style)
        let textOrigin = CGPoint(x: rect.minX + OverlayMetrics.labelPaddingHorizontal,
                                 y: rect.minY + OverlayMetrics.labelPaddingVertical)
        (text as NSString).draw(at: textOrigin, withAttributes: attributes)
    }
}
