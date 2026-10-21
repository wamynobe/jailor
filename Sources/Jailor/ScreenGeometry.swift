import AppKit

enum ScreenGeometry {
    /// Converts a normalized rect (top-left origin) to Cocoa coordinates
    /// within the screen's visible frame.
    static func cocoaRect(from norm: NormRect, in visible: CGRect) -> CGRect {
        let width = visible.width * CGFloat(norm.width)
        let height = visible.height * CGFloat(norm.height)
        let x = visible.minX + visible.width * CGFloat(norm.x)
        let y = visible.maxY - CGFloat(norm.y + norm.height) * visible.height
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    /// Converts a Cocoa rect within the visible frame to a normalized rect
    /// (top-left origin).
    static func normRect(from cocoa: CGRect, in visible: CGRect) -> NormRect {
        guard visible.width > 0, visible.height > 0 else { return .zero }
        return NormRect(
            x: Double((cocoa.minX - visible.minX) / visible.width),
            y: Double((visible.maxY - cocoa.maxY) / visible.height),
            width: Double(cocoa.width / visible.width),
            height: Double(cocoa.height / visible.height)
        )
    }

    /// Cocoa uses a bottom-left origin; Accessibility uses the top-left origin
    /// of the main screen.
    static func axRect(from cocoa: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: cocoa.minX,
            y: primaryHeight - cocoa.maxY,
            width: cocoa.width,
            height: cocoa.height
        ).integral
    }

    static func primaryScreenHeight() -> CGFloat {
        (NSScreen.screens.first ?? NSScreen.main)?.frame.maxY ?? 0
    }

    static func screen(named name: String?) -> NSScreen? {
        if let name, let screen = NSScreen.screens.first(where: { $0.localizedName == name }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func visibleFrame(named name: String?) -> CGRect {
        screen(named: name)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }

    static func fittedRect(aspect: CGFloat, in size: CGSize, padding: CGFloat = 0) -> CGRect {
        let safeAspect = max(aspect, 0.1)
        let available = CGSize(
            width: max(1, size.width - padding * 2),
            height: max(1, size.height - padding * 2)
        )
        var width = available.width
        var height = width / safeAspect
        if height > available.height {
            height = available.height
            width = height * safeAspect
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}
