import AppKit
import SwiftUI

final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PalettePanelController {
    private let store: AppStore
    private var panel: PalettePanel?
    private var model: PaletteModel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var targetPID: pid_t?
    private var shouldRestoreFocus = false

    init(store: AppStore) {
        self.store = store
    }

    func show(target: PaletteTarget) {
        close(restoreFocus: false)

        let model = PaletteModel(store: store, target: target)
        model.onClose = { [weak self] in
            self?.close()
        }

        let hosting = NSHostingController(
            rootView: PaletteView(model: model).environmentObject(store)
        )

        let panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 468),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: 620, height: 468))

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen {
            let origin = NSPoint(
                x: screen.frame.midX - panel.frame.width / 2,
                y: screen.frame.midY - panel.frame.height / 2 + 30
            )
            panel.setFrameOrigin(origin)
        }

        self.panel = panel
        self.model = model
        self.targetPID = target.pid

        NSApp.activate()

        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()

        shouldRestoreFocus = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    func close(restoreFocus: Bool = true) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        model = nil

        let pid = targetPID
        targetPID = nil
        let restore = shouldRestoreFocus && restoreFocus
        shouldRestoreFocus = false

        if restore, let pid, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let panel, panel.isKeyWindow, let model else { return event }

        switch event.keyCode {
        case 53: // Esc
            model.close()
            return nil
        case 48: // Tab
            model.cycleTag(1)
            return nil
        case 123: // ←
            model.cycleTag(-1)
            return nil
        case 124: // →
            model.cycleTag(1)
            return nil
        case 36, 76: // Return / Enter
            if let index = model.hoveredIndex {
                model.assign(index)
            }
            return nil
        default:
            if let index = Self.frameIndex(for: event.keyCode) {
                model.assign(index)
                return nil
            }
            return event
        }
    }

    private static let digitMap: [UInt16: Int] = [
        18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
        22: 5, 26: 6, 28: 7, 25: 8,
        83: 0, 84: 1, 85: 2, 86: 3, 87: 4,
        88: 5, 89: 6, 91: 7, 92: 8
    ]

    private static func frameIndex(for keyCode: UInt16) -> Int? {
        digitMap[keyCode]
    }
}
