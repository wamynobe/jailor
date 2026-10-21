import Foundation
import CoreGraphics

// MARK: - Labels

/// A label used to classify windows.
struct Tag: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

// MARK: - Frames & layouts

/// A frame rect normalized to 0...1 within the screen's visible frame.
/// The origin (0,0) is the top-left corner.
struct NormRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    static let zero = NormRect(x: 0, y: 0, width: 0, height: 0)

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func clamped(minWidth: Double = 0.06, minHeight: Double = 0.07) -> NormRect {
        let w = min(max(width, minWidth), 1)
        let h = min(max(height, minHeight), 1)
        let nx = min(max(x, 0), 1 - w)
        let ny = min(max(y, 0), 1 - h)
        return NormRect(x: nx, y: ny, width: w, height: h)
    }
}

struct FrameZone: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var rect: NormRect
    /// Suggested label for this frame. When a window is dragged into the frame
    /// or assigned through a direct hotkey, this label is used if the app has
    /// no remembered label yet.
    var preferredTagID: UUID?

    init(id: UUID = UUID(), name: String, rect: NormRect, preferredTagID: UUID? = nil) {
        self.id = id
        self.name = name
        self.rect = rect
        self.preferredTagID = preferredTagID
    }
}

struct WorkspaceLayout: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var frames: [FrameZone]
    var screenName: String?

    init(id: UUID = UUID(), name: String, frames: [FrameZone], screenName: String? = nil) {
        self.id = id
        self.name = name
        self.frames = frames
        self.screenName = screenName
    }
}

// MARK: - Assignments

/// A window assigned to a frame in a layout.
/// Windows are matched by stable CGWindowID first, then by title.
struct WindowAssignment: Identifiable, Codable, Hashable {
    var id: UUID
    var layoutID: UUID
    var frameID: UUID
    var bundleID: String
    var appName: String
    var windowTitle: String
    var tagID: UUID?
    var updatedAt: Date
    /// CGWindowID is stable for the lifetime of a window, which prevents
    /// matching a different window when an app has multiple windows with
    /// changing titles. Optional for backward compatibility with old state.
    var windowID: UInt32?

    init(
        id: UUID = UUID(),
        layoutID: UUID,
        frameID: UUID,
        bundleID: String,
        appName: String,
        windowTitle: String,
        tagID: UUID?,
        updatedAt: Date = Date(),
        windowID: UInt32? = nil
    ) {
        self.id = id
        self.layoutID = layoutID
        self.frameID = frameID
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.tagID = tagID
        self.updatedAt = updatedAt
        self.windowID = windowID
    }

    var windowKey: String {
        if let windowID { return "id:\(windowID)" }
        return "\(bundleID)|\(windowTitle)"
    }
}

// MARK: - Settings & persisted state

struct AppSettings: Codable, Hashable {
    var autoRestoreOnLaunch: Bool
    var launchMissingApps: Bool
    var activeLayoutID: UUID?
    var tagMemory: [String: UUID]
    /// Workspace mode: hide the dashboard on launch and reveal assigned
    /// windows when the Dock icon is clicked.
    /// Optional for backward compatibility with older state.json files.
    var workspaceMode: Bool?

    static var `default`: AppSettings {
        AppSettings(
            autoRestoreOnLaunch: true,
            launchMissingApps: true,
            activeLayoutID: nil,
            tagMemory: [:],
            workspaceMode: true
        )
    }
}

struct PersistedState: Codable {
    var version: Int
    var tags: [Tag]
    var layouts: [WorkspaceLayout]
    var assignments: [WindowAssignment]
    var settings: AppSettings

    static func initial() -> PersistedState {
        let tags = [
            Tag(name: "Work", colorHex: "#5B8CFF"),
            Tag(name: "Comms", colorHex: "#FF8A4C"),
            Tag(name: "Research", colorHex: "#35C759"),
            Tag(name: "Entertainment", colorHex: "#BF5AF2")
        ]

        let preset = LayoutPresets.all.first { $0.id == "focus-side" } ?? LayoutPresets.all[0]
        let frames = preset.rects.enumerated().map { index, rect in
            FrameZone(name: "Frame \(index + 1)", rect: rect)
        }
        let layout = WorkspaceLayout(name: preset.name, frames: frames)

        var settings = AppSettings.default
        settings.activeLayoutID = layout.id

        return PersistedState(
            version: 1,
            tags: tags,
            layouts: [layout],
            assignments: [],
            settings: settings
        )
    }
}

// MARK: - Runtime window model

struct AXWindowInfo: Identifiable, Hashable {
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
    let index: Int
    let isMinimized: Bool
    let windowID: UInt32?
    let bounds: CGRect?

    var id: String {
        if let windowID { return "cg-\(windowID)" }
        return "\(pid)|\(bundleID)|\(index)|\(title)"
    }
}

struct PaletteTarget: Hashable {
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
    let windowIndex: Int

    init(pid: pid_t, bundleID: String, appName: String, title: String, windowIndex: Int) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.windowIndex = windowIndex
    }

    init(window: AXWindowInfo) {
        self.init(
            pid: window.pid,
            bundleID: window.bundleID,
            appName: window.appName,
            title: window.title,
            windowIndex: window.index
        )
    }
}

struct ApplyReport: Equatable {
    var moved: Int = 0
    var launched: Int = 0
    var failed: [String] = []
    var missing: [String] = []

    @MainActor
    var summary: String {
        var parts: [String] = []
        if moved > 0 { parts.append(L("Arranged %d windows", moved)) }
        if launched > 0 { parts.append(L("launched %d apps", launched)) }
        if !missing.isEmpty { parts.append(L("%d windows not found", missing.count)) }
        if !failed.isEmpty { parts.append(L("%d windows could not be moved", failed.count)) }
        if parts.isEmpty { return L("Nothing to arrange.") }
        return parts.joined(separator: " · ")
    }
}

struct Toast: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case success
        case warning
    }

    let id = UUID()
    var text: String
    var kind: Kind
}

// MARK: - Layout presets

struct LayoutPreset: Identifiable, Hashable {
    var id: String
    var name: String
    var detail: String
    var rects: [NormRect]
}

enum LayoutPresets {
    static let all: [LayoutPreset] = [
        LayoutPreset(
            id: "focus-side",
            name: "Focus + two",
            detail: "One main window on the left, two smaller windows on the right",
            rects: [
                NormRect(x: 0, y: 0, width: 0.62, height: 1),
                NormRect(x: 0.62, y: 0, width: 0.38, height: 0.5),
                NormRect(x: 0.62, y: 0.5, width: 0.38, height: 0.5)
            ]
        ),
        LayoutPreset(
            id: "two-columns",
            name: "Two columns",
            detail: "Two windows split the screen",
            rects: [
                NormRect(x: 0, y: 0, width: 0.5, height: 1),
                NormRect(x: 0.5, y: 0, width: 0.5, height: 1)
            ]
        ),
        LayoutPreset(
            id: "three-columns",
            name: "Three columns",
            detail: "Three windows in columns",
            rects: [
                NormRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1),
                NormRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1),
                NormRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
            ]
        ),
        LayoutPreset(
            id: "grid-2x2",
            name: "Grid 2 × 2",
            detail: "Four evenly sized windows",
            rects: [
                NormRect(x: 0, y: 0, width: 0.5, height: 0.5),
                NormRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                NormRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                NormRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            ]
        ),
        LayoutPreset(
            id: "three-rows",
            name: "Three rows",
            detail: "Three stacked windows",
            rects: [
                NormRect(x: 0, y: 0, width: 1, height: 1.0 / 3.0),
                NormRect(x: 0, y: 1.0 / 3.0, width: 1, height: 1.0 / 3.0),
                NormRect(x: 0, y: 2.0 / 3.0, width: 1, height: 1.0 / 3.0)
            ]
        ),
        LayoutPreset(
            id: "single",
            name: "Full screen",
            detail: "A single full-screen frame",
            rects: [
                NormRect(x: 0, y: 0, width: 1, height: 1)
            ]
        )
    ]
}
