import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = AppStore()

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var hotKeys: HotKeyManager?
    private var paletteController: PalettePanelController?
    private let launchedAt = Date()
    private var activationRevealTask: Task<Void, Never>?
    private var lastRevealTime = Date.distantPast
    private var globalKeyMonitor: Any?
    private var lastShortcutFire: (keyCode: UInt16, time: Date)?
    private var suppressActivationRevealUntil = Date.distantPast
    private var backgroundActivity: NSObjectProtocol?
    private var languageObserver: NSObjectProtocol?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Jailor must keep running in the background so global hotkeys work
        // even after the dashboard is hidden and no visible window remains.
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Jailor runs in the background to keep global hotkeys and layout management alive"
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiatedAllowingIdleSystemSleep,
                .automaticTerminationDisabled,
                .suddenTerminationDisabled
            ],
            reason: "Jailor global hotkeys and workspace"
        )

        buildMainMenu()
        setupStatusItem()
        setupHotKeys()
        paletteController = PalettePanelController(store: store)

        languageObserver = NotificationCenter.default.addObserver(
            forName: .jailorLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Let the language picker finish its closing animation before
                // rebuilding AppKit menus on the main thread.
                try? await Task.sleep(nanoseconds: 80_000_000)
                self?.buildMainMenu()
                self?.settingsWindow?.title = L("Jailor Settings")
                self?.statusItem?.button?.toolTip = L("Jailor — workspace for Mac")
            }
        }

        // Workspace mode: keep the dashboard hidden on launch and only show
        // the windows assigned to the layout. Only do this when reveal can
        // actually run (permission granted, assignments exist, auto-restore on).
        let hideDashboardOnLaunch =
            store.isWorkspaceMode &&
            store.isTrusted &&
            !store.activeAssignments.isEmpty &&
            store.state.settings.autoRestoreOnLaunch

        if !hideDashboardOnLaunch {
            createMainWindow()
        }

        store.bootstrap(revealOnAutoRestore: hideDashboardOnLaunch)

        if !hideDashboardOnLaunch {
            NSApp.activate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.persistNow()
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
            self.languageObserver = nil
        }
        if let backgroundActivity {
            ProcessInfo.processInfo.endActivity(backgroundActivity)
            self.backgroundActivity = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if store.isWorkspaceMode {
            // Option-click the Dock icon opens the dashboard for configuration.
            if NSEvent.modifierFlags.contains(.option) {
                showDashboard()
            } else {
                revealWorkspaceAndHideDashboard()
            }
            return true
        }

        showDashboard()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleActivationReveal()
    }

    /// Cmd+Tab or a Dock click while the app is in the background may only
    /// activate the app and does not always call applicationShouldHandleReopen.
    /// Schedule a short reveal after the app becomes active.
    private func scheduleActivationReveal() {
        guard store.isWorkspaceMode else { return }
        guard Date().timeIntervalSince(launchedAt) > 1.2 else { return }
        guard Date() >= suppressActivationRevealUntil else { return }
        guard store.isTrusted, !store.activeAssignments.isEmpty else { return }
        guard mainWindow?.isVisible != true else { return }
        if let settingsWindow, settingsWindow.isVisible { return }
        if NSApp.windows.contains(where: { $0 is PalettePanel && $0.isVisible }) { return }

        activationRevealTask?.cancel()
        activationRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            guard Date() >= suppressActivationRevealUntil else { return }
            guard store.isWorkspaceMode, store.isTrusted, !store.activeAssignments.isEmpty else { return }
            guard mainWindow?.isVisible != true else { return }
            if let settingsWindow, settingsWindow.isVisible { return }
            if NSApp.windows.contains(where: { $0 is PalettePanel && $0.isVisible }) { return }
            guard Date().timeIntervalSince(lastRevealTime) > 0.55 else { return }
            revealWorkspaceAndHideDashboard()
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let reveal = NSMenuItem(
            title: L("Reveal workspace"),
            action: #selector(revealWorkspaceAction),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)

        let dashboard = NSMenuItem(
            title: L("Open dashboard"),
            action: #selector(showDashboardAction),
            keyEquivalent: ""
        )
        dashboard.target = self
        menu.addItem(dashboard)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: L("Settings…"),
            action: #selector(openSettingsAction),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)

        return menu
    }

    // MARK: Main window

    private func createMainWindow() {
        let root = ContentView(
            openSettings: { [weak self] in self?.openSettings() },
            openPalette: { [weak self] in self?.openPalette() },
            revealWorkspace: { [weak self] in self?.revealWorkspaceAndHideDashboard() }
        )
        .environmentObject(store)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Jailor"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.minSize = NSSize(width: 980, height: 640)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("JailorMainWindow")
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func showDashboard() {
        suppressActivationReveal(for: 1.2)
        if mainWindow == nil {
            createMainWindow()
        }
        if mainWindow?.isMiniaturized == true {
            mainWindow?.deminiaturize(nil)
        }
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func hideDashboard() {
        mainWindow?.orderOut(nil)
    }

    /// Prevents opening the dashboard/settings/palette from triggering a
    /// reveal that would immediately close the UI again.
    private func suppressActivationReveal(for seconds: TimeInterval) {
        suppressActivationRevealUntil = Date().addingTimeInterval(seconds)
        activationRevealTask?.cancel()
    }

    /// Hides the Jailor UI and brings the windows assigned to the layout to the
    /// front. If permission or assignments are missing, open the dashboard so
    /// the user can resolve it.
    private func revealWorkspaceAndHideDashboard() {
        store.refreshTrust()

        guard store.isTrusted else {
            showDashboard()
            store.showToast(
                L("Accessibility permission is required before revealing the workspace."),
                kind: .warning
            )
            return
        }

        guard !store.activeAssignments.isEmpty else {
            showDashboard()
            store.showToast(
                L("No windows are assigned to this layout. Drag a window into a frame first."),
                kind: .info
            )
            return
        }

        // Do not drop this while an apply is running: Store queues the reveal
        // and runs it immediately after the current apply finishes.
        lastRevealTime = Date()
        paletteController?.close(restoreFocus: false)
        settingsWindow?.orderOut(nil)
        hideDashboard()
        store.revealWorkspace()
    }

    private func openSettings() {
        suppressActivationReveal(for: 1.2)
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(store)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = L("Jailor Settings")
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 660, height: 620))
            window.minSize = NSSize(width: 620, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Palette

    private func openPalette() {
        guard let target = store.capturePaletteTarget() else {
            store.showToast(
                L("No focused window found. Open the window you want to assign and try again."),
                kind: .warning
            )
            NSSound.beep()
            return
        }
        suppressActivationReveal(for: 1.2)
        paletteController?.show(target: target)
    }

    // MARK: Hotkeys

    private enum ShortcutAction {
        case palette
        case reveal
        case frame(Int)
    }

    private static let frameKeyCodes: [UInt16] = [
        18, 19, 20, 21, 23, 22, 26, 28, 25
    ]

    private static let keypadFrameKeyCodes: [UInt16: Int] = [
        83: 0, 84: 1, 85: 2, 86: 3, 87: 4,
        88: 5, 89: 6, 91: 7, 92: 8
    ]

    private func setupHotKeys() {
        let manager = HotKeyManager()

        manager.onPalette = { [weak self] in
            Task { @MainActor in
                self?.performShortcut(.palette, keyCode: 49) // ⌃⌥Space
            }
        }
        manager.onFrame = { [weak self] index in
            Task { @MainActor in
                let keyCode = Self.frameKeyCodes.indices.contains(index)
                    ? Self.frameKeyCodes[index]
                    : 0
                self?.performShortcut(.frame(index), keyCode: keyCode)
            }
        }
        manager.onReveal = { [weak self] in
            Task { @MainActor in
                self?.performShortcut(.reveal, keyCode: 15) // ⌃⌥R
            }
        }
        hotKeys = manager

        // Fallback: Carbon hotkeys may not receive events while the app is
        // inactive on some macOS configurations. The global monitor requires
        // Accessibility permission, which Jailor already needs.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalShortcut(event)
            }
        }
    }

    private func handleGlobalShortcut(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control), flags.contains(.option) else { return }
        guard !flags.contains(.command), !flags.contains(.shift) else { return }
        guard !event.isARepeat else { return }

        let keyCode = event.keyCode
        let action: ShortcutAction?

        switch keyCode {
        case 49:
            action = .palette
        case 15:
            action = .reveal
        default:
            if let index = Self.frameKeyCodes.firstIndex(of: keyCode) {
                action = .frame(index)
            } else if let index = Self.keypadFrameKeyCodes[keyCode] {
                action = .frame(index)
            } else {
                action = nil
            }
        }

        if let action {
            performShortcut(action, keyCode: keyCode)
        }
    }

    private func performShortcut(_ action: ShortcutAction, keyCode: UInt16) {
        let now = Date()
        if let last = lastShortcutFire,
           last.keyCode == keyCode,
           now.timeIntervalSince(last.time) < 0.25 {
            return
        }
        lastShortcutFire = (keyCode, now)

        switch action {
        case .palette:
            openPalette()
        case .reveal:
            revealWorkspaceAndHideDashboard()
        case .frame(let index):
            store.assignFocusedWindow(toFrameIndex: index)
        }
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "rectangle.split.2x1",
                accessibilityDescription: "Jailor"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = L("Jailor — workspace for Mac")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let reveal = NSMenuItem(
            title: L("Reveal workspace"),
            action: #selector(revealWorkspaceAction),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)

        let dashboard = NSMenuItem(
            title: L("Open dashboard"),
            action: #selector(showDashboardAction),
            keyEquivalent: ""
        )
        dashboard.target = self
        menu.addItem(dashboard)
        menu.addItem(.separator())

        let palette = NSMenuItem(
            title: L("Assign focused window…"),
            action: #selector(showPaletteAction),
            keyEquivalent: ""
        )
        palette.target = self
        menu.addItem(palette)

        let apply = NSMenuItem(
            title: L("Apply layout (without changing focus)"),
            action: #selector(applyLayoutAction),
            keyEquivalent: ""
        )
        apply.target = self
        menu.addItem(apply)

        let fill = NSMenuItem(
            title: L("Fill empty frames"),
            action: #selector(fillFramesAction),
            keyEquivalent: ""
        )
        fill.target = self
        menu.addItem(fill)

        menu.addItem(.separator())

        let layoutRoot = NSMenuItem(title: L("Layouts"), action: nil, keyEquivalent: "")
        let layoutMenu = NSMenu()
        for layout in store.layouts {
            let item = NSMenuItem(
                title: layout.name,
                action: #selector(selectLayoutAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = layout.id.uuidString
            item.state = layout.id == store.activeLayout?.id ? .on : .off
            layoutMenu.addItem(item)
        }
        layoutRoot.submenu = layoutMenu
        menu.addItem(layoutRoot)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: L("Settings…"),
            action: #selector(openSettingsAction),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: L("Quit Jailor"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        menu.addItem(quit)
    }

    // MARK: Menu actions

    @objc private func revealWorkspaceAction() {
        revealWorkspaceAndHideDashboard()
    }

    @objc private func showDashboardAction() {
        showDashboard()
    }

    @objc private func showPaletteAction() {
        openPalette()
    }

    @objc private func applyLayoutAction() {
        store.refreshTrust()
        store.refreshWindows()
        store.applyLayout()
    }

    @objc private func fillFramesAction() {
        store.refreshTrust()
        store.refreshWindows()
        store.fillEmptyFrames()
    }

    @objc private func selectLayoutAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw) else { return }
        store.setActiveLayout(id)
        showDashboard()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    // MARK: Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()

        let about = NSMenuItem(
            title: L("About Jailor"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(
            title: L("Settings…"),
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        appMenu.addItem(
            withTitle: L("Hide Jailor"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: L("Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(
            withTitle: L("Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L("Quit Jailor"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        // Edit menu (needed for TextField shortcuts)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: L("Edit Menu"))
        editMenu.addItem(withTitle: L("Undo"), action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = NSMenuItem(title: L("Redo"), action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Cut"), action: NSSelectorFromString("cut:"), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy"), action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste"), action: NSSelectorFromString("paste:"), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All"), action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
        editItem.submenu = editMenu

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(
            withTitle: L("Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: L("Zoom"),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: L("Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        // Layout menu
        let layoutItem = NSMenuItem()
        mainMenu.addItem(layoutItem)
        let layoutMenu = NSMenu(title: L("Layouts"))

        let reveal = NSMenuItem(
            title: L("Reveal workspace"),
            action: #selector(revealWorkspaceAction),
            keyEquivalent: "r"
        )
        reveal.keyEquivalentModifierMask = [.command, .shift]
        reveal.target = self
        layoutMenu.addItem(reveal)

        let dashboard = NSMenuItem(
            title: L("Open dashboard"),
            action: #selector(showDashboardAction),
            keyEquivalent: "0"
        )
        dashboard.target = self
        layoutMenu.addItem(dashboard)

        layoutMenu.addItem(.separator())

        let apply = NSMenuItem(
            title: L("Apply layout (without changing focus)"),
            action: #selector(applyLayoutAction),
            keyEquivalent: "\r"
        )
        apply.target = self
        layoutMenu.addItem(apply)

        let fill = NSMenuItem(
            title: L("Fill empty frames"),
            action: #selector(fillFramesAction),
            keyEquivalent: ""
        )
        fill.target = self
        layoutMenu.addItem(fill)

        layoutMenu.addItem(.separator())
        let palette = NSMenuItem(
            title: L("Assign focused window…"),
            action: #selector(showPaletteAction),
            keyEquivalent: ""
        )
        palette.target = self
        layoutMenu.addItem(palette)
        layoutItem.submenu = layoutMenu

        NSApp.mainMenu = mainMenu
    }
}
