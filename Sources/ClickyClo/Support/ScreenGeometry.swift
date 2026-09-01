//
//  ScreenGeometry.swift
//  ClickyClo
//
//  macOS has two competing global coordinate spaces and mixing them up is the
//  single most common source of "the ring is drawn 900 points too low" bugs:
//
//    • CoreGraphics / Quartz Display space — origin at the TOP-LEFT of the main
//      display, +y grows downward. This is what `CGEvent`, `CGDisplayBounds`,
//      ScreenCaptureKit and (crucially) any vision model reasoning about a
//      screenshot naturally speak.
//
//    • AppKit space — origin at the BOTTOM-LEFT of the main display, +y grows
//      upward. This is what `NSScreen.frame` and `NSWindow.setFrame` speak.
//
//  ClickyClo standardises on the CoreGraphics convention for everything that
//  crosses a boundary (AI payloads, synthetic clicks, capture rects) and converts
//  to AppKit only at the moment of drawing. All conversion lives here.
//

import AppKit
import CoreGraphics

enum ScreenGeometry {

    // MARK: - Displays

    /// The display that owns the menu bar. AppKit guarantees this is the screen
    /// whose `frame.origin` is `(0, 0)` and it anchors both coordinate spaces.
    static var mainDisplayScreen: NSScreen? {
        NSScreen.screens.first
    }

    /// Height of the main display in points. This is the pivot used to flip
    /// between the top-left and bottom-left origins.
    static var mainDisplayHeight: CGFloat {
        mainDisplayScreen?.frame.maxY ?? 0
    }

    /// The union of every attached display, expressed in AppKit space.
    static var desktopBoundsAppKit: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// The union of every attached display, expressed in top-left CoreGraphics space.
    static var desktopBoundsTopLeft: CGRect {
        let appKit = desktopBoundsAppKit
        guard !appKit.isNull else { return .null }
        return convertRectToTopLeft(appKit)
    }

    /// The `CGDirectDisplayID` backing an `NSScreen`, used to key overlay windows
    /// to physical displays across hot-plug events (screen objects are recreated,
    /// display IDs are stable while the display stays attached).
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            Log.geometry.error("NSScreen is missing NSScreenNumber; falling back to the main display ID")
            return CGMainDisplayID()
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Pixels-per-point for a display: 1.0 on a standard monitor, 2.0 on Retina.
    /// Stage 6 uses this to map model-reported pixel coordinates onto points.
    static func backingScale(for screen: NSScreen) -> CGFloat {
        screen.backingScaleFactor
    }

    // MARK: - Point conversion

    /// Top-left (CoreGraphics) global point → bottom-left (AppKit) global point.
    static func appKitPoint(fromTopLeft point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
    }

    /// Bottom-left (AppKit) global point → top-left (CoreGraphics) global point.
    static func topLeftPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
    }

    // MARK: - Rect conversion

    /// Top-left (CoreGraphics) rect → bottom-left (AppKit) rect.
    static func convertRectToAppKit(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: mainDisplayHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Bottom-left (AppKit) rect → top-left (CoreGraphics) rect.
    static func convertRectToTopLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: mainDisplayHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    // MARK: - Hit testing

    /// The display that contains a top-left global point, if any. Points that
    /// land in the dead space between mismatched displays return `nil`.
    static func screen(containingTopLeft point: CGPoint) -> NSScreen? {
        let appKit = appKitPoint(fromTopLeft: point)
        return NSScreen.screens.first { $0.frame.contains(appKit) }
    }

    /// Clamps a top-left global point into the nearest display so a bad AI
    /// coordinate can never park the indicator in unreachable dead space.
    static func clampToVisibleDesktop(topLeft point: CGPoint) -> CGPoint {
        if screen(containingTopLeft: point) != nil { return point }

        let appKit = appKitPoint(fromTopLeft: point)
        var best: (distance: CGFloat, point: CGPoint)?

        for screen in NSScreen.screens {
            let frame = screen.frame
            // `maxX`/`maxY` are exclusive; step one point inside so the result is
            // still `contains()`-true for the screen we clamped to.
            let clamped = CGPoint(
                x: min(max(appKit.x, frame.minX), frame.maxX - 1),
                y: min(max(appKit.y, frame.minY), frame.maxY - 1)
            )
            let dx = clamped.x - appKit.x
            let dy = clamped.y - appKit.y
            let distance = (dx * dx) + (dy * dy)
            if best == nil || distance < best!.distance {
                best = (distance, clamped)
            }
        }

        guard let winner = best else { return point }
        return topLeftPoint(fromAppKit: winner.point)
    }

    // MARK: - Diagnostics

    /// One-line-per-display summary, logged at launch and on every display change.
    static func describeDisplays() -> String {
        NSScreen.screens.enumerated().map { index, screen in
            let frame = screen.frame
            let topLeft = convertRectToTopLeft(frame)
            return String(
                format: "#%d id=%u appkit=(%.0f,%.0f %.0fx%.0f) topLeft=(%.0f,%.0f %.0fx%.0f) scale=%.1f",
                index,
                displayID(for: screen),
                frame.origin.x, frame.origin.y, frame.width, frame.height,
                topLeft.origin.x, topLeft.origin.y, topLeft.width, topLeft.height,
                screen.backingScaleFactor
            )
        }
        .joined(separator: " | ")
    }
}
