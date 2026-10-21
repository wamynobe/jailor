import Foundation

/// Drag payload for moving a window from the sidebar into a frame.
struct WindowDragPayload: Codable {
    let pid: Int32
    let bundleID: String
    let appName: String
    let title: String
    let index: Int

    init(window: AXWindowInfo) {
        self.pid = window.pid
        self.bundleID = window.bundleID
        self.appName = window.appName
        self.title = window.title
        self.index = window.index
    }

    init(pid: Int32, bundleID: String, appName: String, title: String, index: Int) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.index = index
    }

    var json: String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    var paletteTarget: PaletteTarget {
        PaletteTarget(
            pid: pid,
            bundleID: bundleID,
            appName: appName,
            title: title,
            windowIndex: index
        )
    }

    static func parse(_ text: String) -> WindowDragPayload? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WindowDragPayload.self, from: data)
    }
}

extension AXWindowInfo {
    var dragPayloadJSON: String {
        WindowDragPayload(window: self).json
    }
}
