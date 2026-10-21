import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _JailorAXWindowID(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

/// All Accessibility API interaction lives here.
enum AccessibilityService {

    // MARK: Permission

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Attribute helpers

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success, let value else { return nil }
        return value as? T
    }

    @discardableResult
    private static func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    private static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let raw: AXValue = attribute(element, name) else { return nil }
        var value = CGPoint.zero
        return AXValueGetValue(raw, .cgPoint, &value) ? value : nil
    }

    private static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let raw: AXValue = attribute(element, name) else { return nil }
        var value = CGSize.zero
        return AXValueGetValue(raw, .cgSize, &value) ? value : nil
    }

    // MARK: Enumeration

    static func allWindows() -> [(info: AXWindowInfo, element: AXUIElement)] {
        var result: [(info: AXWindowInfo, element: AXUIElement)] = []
        let ourPID = ProcessInfo.processInfo.processIdentifier

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            guard pid != ourPID else { continue }
            guard let bundleID = app.bundleIdentifier else { continue }

            let windows = windowElements(pid: pid)
            let appName = app.localizedName ?? bundleID

            for (index, window) in windows.enumerated() {
                guard let info = windowInfo(
                    window,
                    pid: pid,
                    bundleID: bundleID,
                    appName: appName,
                    index: index
                ) else { continue }
                result.append((info, window))
            }
        }

        return result.sorted {
            if $0.info.appName == $1.info.appName {
                return $0.info.title.localizedStandardCompare($1.info.title) == .orderedAscending
            }
            return $0.info.appName.localizedStandardCompare($1.info.appName) == .orderedAscending
        }
    }

    static func allWindowInfos() -> [AXWindowInfo] {
        allWindows().map(\.info)
    }

    static func windowElements(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        return (attribute(app, kAXWindowsAttribute) as [AXUIElement]?) ?? []
    }

    private static func windowInfo(
        _ window: AXUIElement,
        pid: pid_t,
        bundleID: String,
        appName: String,
        index: Int
    ) -> AXWindowInfo? {
        let role: String? = attribute(window, kAXRoleAttribute)
        guard role == nil || role == kAXWindowRole else { return nil }

        let subrole: String? = attribute(window, kAXSubroleAttribute)
        if let subrole, subrole != kAXStandardWindowSubrole {
            return nil
        }

        guard let windowSize = size(window, kAXSizeAttribute),
              windowSize.width > 24,
              windowSize.height > 24 else {
            return nil
        }

        let position = point(window, kAXPositionAttribute) ?? .zero
        let rawTitle: String = attribute(window, kAXTitleAttribute) ?? ""
        let title = rawTitle.isEmpty ? appName : rawTitle
        let minimized: Bool = attribute(window, kAXMinimizedAttribute) ?? false
        let windowID = windowID(for: window)

        return AXWindowInfo(
            pid: pid,
            bundleID: bundleID,
            appName: appName,
            title: title,
            index: index,
            isMinimized: minimized,
            windowID: windowID,
            bounds: CGRect(origin: position, size: windowSize)
        )
    }

    static func windowID(for window: AXUIElement) -> UInt32? {
        var id: CGWindowID = 0
        if _JailorAXWindowID(window, &id) == .success, id != 0 {
            return id
        }
        if let number: NSNumber = attribute(window, "AXWindowNumber"), number.uint32Value != 0 {
            return number.uint32Value
        }
        return nil
    }

    static func focusedWindow() -> PaletteTarget? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        guard front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard let bundleID = front.bundleIdentifier else { return nil }

        let pid = front.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.35)

        guard let focused: AXUIElement = attribute(appElement, kAXFocusedWindowAttribute) else {
            return nil
        }

        let windows = windowElements(pid: pid)
        let index = windows.firstIndex(where: { CFEqual($0, focused) }) ?? 0

        let rawTitle: String = attribute(focused, kAXTitleAttribute) ?? ""
        let appName = front.localizedName ?? bundleID
        let title = rawTitle.isEmpty ? appName : rawTitle

        return PaletteTarget(
            pid: pid,
            bundleID: bundleID,
            appName: appName,
            title: title,
            windowIndex: index
        )
    }

    // MARK: Resolve

    static func resolve(_ target: PaletteTarget) -> AXUIElement? {
        var app = NSRunningApplication(processIdentifier: target.pid)
        if app == nil || app?.isTerminated == true {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first
        }
        guard let app else { return nil }

        let windows = windowElements(pid: app.processIdentifier)
        guard !windows.isEmpty else { return nil }

        if target.windowIndex >= 0, target.windowIndex < windows.count {
            let candidate = windows[target.windowIndex]
            let rawTitle: String = attribute(candidate, kAXTitleAttribute) ?? ""
            let title = rawTitle.isEmpty ? target.appName : rawTitle
            if title == target.title {
                return candidate
            }
        }

        if let matched = windows.first(where: {
            let rawTitle: String = attribute($0, kAXTitleAttribute) ?? ""
            let title = rawTitle.isEmpty ? target.appName : rawTitle
            return title == target.title
        }) {
            return matched
        }

        return windows.first
    }

    static func element(for info: AXWindowInfo) -> AXUIElement? {
        var pid = info.pid
        var app = NSRunningApplication(processIdentifier: pid)
        if app == nil || app?.isTerminated == true {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: info.bundleID).first
            if let app { pid = app.processIdentifier }
        }
        guard app != nil else { return nil }

        let windows = windowElements(pid: pid)
        guard !windows.isEmpty else { return nil }

        if info.index >= 0, info.index < windows.count {
            let candidate = windows[info.index]
            let rawTitle: String = attribute(candidate, kAXTitleAttribute) ?? ""
            let title = rawTitle.isEmpty ? info.appName : rawTitle
            if title == info.title {
                return candidate
            }
        }

        return windows.first(where: {
            let rawTitle: String = attribute($0, kAXTitleAttribute) ?? ""
            let title = rawTitle.isEmpty ? info.appName : rawTitle
            return title == info.title
        }) ?? windows.first
    }

    static func title(of window: AXUIElement) -> String? {
        let raw: String? = attribute(window, kAXTitleAttribute)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    // MARK: Move / focus

    @discardableResult
    static func move(_ window: AXUIElement, to rect: CGRect) -> Bool {
        _ = setAttribute(window, kAXMinimizedAttribute, kCFBooleanFalse)

        if let fullscreen: Bool = attribute(window, "AXFullScreen"), fullscreen {
            _ = setAttribute(window, "AXFullScreen", kCFBooleanFalse)
            Thread.sleep(forTimeInterval: 0.3)
        }

        var origin = CGPoint(x: rect.minX, y: rect.minY)
        var newSize = CGSize(width: rect.width, height: rect.height)
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &newSize) else {
            return false
        }

        var didSetSomething = false
        if setAttribute(window, kAXPositionAttribute, positionValue) {
            didSetSomething = true
        }
        if setAttribute(window, kAXSizeAttribute, sizeValue) {
            didSetSomething = true
        }

        Thread.sleep(forTimeInterval: 0.05)

        // Some apps (Electron, Java) require a second set after resizing.
        if let actualPosition = point(window, kAXPositionAttribute),
           let actualSize = size(window, kAXSizeAttribute) {
            let deltaPosition = abs(actualPosition.x - rect.minX) + abs(actualPosition.y - rect.minY)
            let deltaSize = abs(actualSize.width - rect.width) + abs(actualSize.height - rect.height)
            if deltaPosition > 4 || deltaSize > 4 {
                _ = setAttribute(window, kAXSizeAttribute, sizeValue)
                _ = setAttribute(window, kAXPositionAttribute, positionValue)
            }
        }

        return didSetSomething
    }

    static func focus(_ window: AXUIElement, pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
        Thread.sleep(forTimeInterval: 0.02)
        makeKey(window, pid: pid)
    }

    /// Makes the given window the key window. Activating an application alone
    /// can show a different window (for example, the newest VS Code window),
    /// so the app's focused window and the window's main/focused attributes
    /// must be set on the exact window afterwards.
    static func makeKey(_ window: AXUIElement, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        _ = setAttribute(app, kAXFocusedWindowAttribute, window)
        _ = setAttribute(window, kAXMinimizedAttribute, kCFBooleanFalse)
        _ = setAttribute(window, kAXMainAttribute, kCFBooleanTrue)
        _ = setAttribute(window, kAXFocusedAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Raises a window without activating its app. Used for the final
    /// cross-app pass to avoid repeated focus changes.
    static func raise(_ window: AXUIElement) {
        _ = setAttribute(window, kAXMinimizedAttribute, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}
