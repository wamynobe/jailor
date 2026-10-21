import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {

    // MARK: Persisted state

    @Published private(set) var state: PersistedState {
        didSet { scheduleSave() }
    }

    // MARK: Runtime state

    @Published var runningWindows: [AXWindowInfo] = []
    @Published var isTrusted: Bool = AccessibilityService.isTrusted
    @Published var isEditing: Bool = false
    @Published var selectedFrameID: UUID?
    @Published var selectedWindowID: AXWindowInfo.ID?
    @Published var tagFilter: UUID?
    @Published var toast: Toast?
    @Published var applyReport: ApplyReport?
    @Published var isApplying: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var statusText: String?
    @Published var searchText: String = ""

    private var saveWorkItem: DispatchWorkItem?
    private var activationObserver: NSObjectProtocol?
    private var pendingReveal = false

    // MARK: Init

    init() {
        state = Self.loadState() ?? PersistedState.initial()
        normalizeState()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleActivation()
            }
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func bootstrap(revealOnAutoRestore: Bool = false) {
        isTrusted = AccessibilityService.isTrusted
        normalizeState()
        refreshWindows()
        autoRestoreIfNeeded(reveal: revealOnAutoRestore)
    }

    private func normalizeState() {
        if state.layouts.isEmpty {
            state = PersistedState.initial()
            return
        }
        if state.settings.activeLayoutID == nil ||
            !state.layouts.contains(where: { $0.id == state.settings.activeLayoutID }) {
            state.settings.activeLayoutID = state.layouts.first?.id
        }
        let layoutIDs = Set(state.layouts.map(\.id))
        state.assignments.removeAll { !layoutIDs.contains($0.layoutID) }

        // Remove orphaned assignments whose frame no longer exists.
        state.assignments.removeAll { assignment in
            guard let layout = state.layouts.first(where: { $0.id == assignment.layoutID }) else {
                return true
            }
            return !layout.frames.contains(where: { $0.id == assignment.frameID })
        }

        let tagIDs = Set(state.tags.map(\.id))
        state.assignments = state.assignments.map { assignment in
            var copy = assignment
            if let tagID = copy.tagID, !tagIDs.contains(tagID) { copy.tagID = nil }
            return copy
        }
        for layoutIndex in state.layouts.indices {
            for frameIndex in state.layouts[layoutIndex].frames.indices {
                let preferred = state.layouts[layoutIndex].frames[frameIndex].preferredTagID
                if let preferred, !tagIDs.contains(preferred) {
                    state.layouts[layoutIndex].frames[frameIndex].preferredTagID = nil
                }
            }
        }
        if let filter = tagFilter, !tagIDs.contains(filter) {
            tagFilter = nil
        }
    }

    // MARK: Derived

    var tags: [Tag] { state.tags }
    var layouts: [WorkspaceLayout] { state.layouts }

    var activeLayout: WorkspaceLayout? {
        state.layouts.first(where: { $0.id == state.settings.activeLayoutID }) ?? state.layouts.first
    }

    var activeAssignments: [WindowAssignment] {
        guard let layout = activeLayout else { return [] }
        return state.assignments.filter { $0.layoutID == layout.id }
    }

    func tag(_ id: UUID?) -> Tag? {
        guard let id else { return nil }
        return state.tags.first(where: { $0.id == id })
    }

    func tagCount(_ id: UUID) -> Int {
        activeAssignments.filter { $0.tagID == id }.count
    }

    func assignment(for frameID: UUID) -> WindowAssignment? {
        activeAssignments.first(where: { $0.frameID == frameID })
    }

    func frameNumber(for assignment: WindowAssignment) -> Int? {
        guard let layout = activeLayout,
              let index = layout.frames.firstIndex(where: { $0.id == assignment.frameID }) else { return nil }
        return index + 1
    }

    func assignment(for window: AXWindowInfo) -> WindowAssignment? {
        if let windowID = window.windowID,
           let exact = activeAssignments.first(where: { $0.windowID == windowID }) {
            return exact
        }

        let titleMatches = activeAssignments.filter {
            $0.bundleID == window.bundleID && $0.windowTitle == window.title
        }
        return titleMatches.count == 1 ? titleMatches[0] : nil
    }

    func runningWindow(for assignment: WindowAssignment) -> AXWindowInfo? {
        if let windowID = assignment.windowID,
           let exact = runningWindows.first(where: { $0.windowID == windowID }) {
            return exact
        }

        if let exact = runningWindows.first(where: {
            $0.bundleID == assignment.bundleID && $0.title == assignment.windowTitle
        }) {
            return exact
        }

        let sameApp = runningWindows.filter { $0.bundleID == assignment.bundleID }
        return sameApp.count == 1 ? sameApp.first : nil
    }

    func isRunning(_ assignment: WindowAssignment) -> Bool {
        runningWindow(for: assignment) != nil
    }

    func filteredWindows() -> [AXWindowInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return runningWindows }
        return runningWindows.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.appName.localizedCaseInsensitiveContains(query)
        }
    }

    func screenName(for layout: WorkspaceLayout) -> String {
        if let name = layout.screenName, NSScreen.screens.contains(where: { $0.localizedName == name }) {
            return name
        }
        return NSScreen.main?.localizedName ?? L("Main screen")
    }

    func screenSize(for layout: WorkspaceLayout) -> CGSize {
        ScreenGeometry.visibleFrame(named: layout.screenName).size
    }

    func recommendedTag(for target: PaletteTarget) -> UUID? {
        if let remembered = state.settings.tagMemory[target.bundleID],
           state.tags.contains(where: { $0.id == remembered }) {
            return remembered
        }
        return tagFilter
    }

    // MARK: Windows

    func refreshTrust() {
        isTrusted = AccessibilityService.isTrusted
    }

    func refreshWindows() {
        guard isTrusted else {
            runningWindows = []
            return
        }
        isRefreshing = true
        runningWindows = AccessibilityService.allWindowInfos()
        isRefreshing = false
        if let selected = selectedWindowID,
           !runningWindows.contains(where: { $0.id == selected }) {
            selectedWindowID = nil
        }
    }

    func requestAccessibility() {
        AccessibilityService.requestAccess()
        AccessibilityService.openAccessibilitySettings()
        showToast(L("Enable Jailor in System Settings → Privacy & Security → Accessibility."), kind: .info)
    }

    func openAccessibilitySettings() {
        AccessibilityService.openAccessibilitySettings()
    }

    private func handleActivation() {
        isTrusted = AccessibilityService.isTrusted
        if isTrusted {
            refreshWindows()
        }
    }

    func capturePaletteTarget() -> PaletteTarget? {
        if let focused = AccessibilityService.focusedWindow() {
            return focused
        }
        if let id = selectedWindowID,
           let window = runningWindows.first(where: { $0.id == id }) {
            return PaletteTarget(window: window)
        }
        return nil
    }

    func selectWindow(_ window: AXWindowInfo) {
        selectedWindowID = window.id
    }

    func focus(window: AXWindowInfo) {
        guard let element = AccessibilityService.element(for: window) else {
            showToast(L("Window not found. Refresh the list."), kind: .warning)
            return
        }
        AccessibilityService.focus(element, pid: window.pid)
    }

    func focus(assignmentID: UUID) {
        guard let assignment = state.assignments.first(where: { $0.id == assignmentID }) else { return }
        guard let window = runningWindow(for: assignment),
              let element = AccessibilityService.element(for: window) else {
            showToast(L("Window is not running. Press Apply to reopen and arrange it."), kind: .warning)
            return
        }
        AccessibilityService.focus(element, pid: window.pid)
    }

    // MARK: Assignment

    func assignFocusedWindow(toFrameIndex index: Int) {
        guard isTrusted else {
            showToast(L("Accessibility permission is required to move windows."), kind: .warning)
            NSSound.beep()
            return
        }
        guard let layout = activeLayout, index >= 0, index < layout.frames.count else { return }
        guard let target = capturePaletteTarget() else {
            showToast(L("No focused window found. Select a window in the list."), kind: .warning)
            NSSound.beep()
            return
        }
        let frame = layout.frames[index]
        let tagID = state.settings.tagMemory[target.bundleID]
            ?? frame.preferredTagID
            ?? tagFilter
        assign(target: target, toFrame: frame.id, tagID: tagID)
    }

    @discardableResult
    func assign(target: PaletteTarget, toFrame frameID: UUID, tagID: UUID?) -> Bool {
        guard isTrusted else {
            showToast(L("Accessibility permission is required to move windows."), kind: .warning)
            return false
        }
        guard let element = AccessibilityService.resolve(target) else {
            showToast(L("Window %@ not found.", target.appName), kind: .warning)
            return false
        }
        let title = AccessibilityService.title(of: element) ?? target.title
        return commitAssignment(
            bundleID: target.bundleID,
            appName: target.appName,
            title: title,
            pid: target.pid,
            element: element,
            frameID: frameID,
            tagID: tagID
        )
    }

    @discardableResult
    func assign(window: AXWindowInfo, toFrame frameID: UUID, tagID: UUID?) -> Bool {
        guard isTrusted else {
            showToast(L("Accessibility permission is required to move windows."), kind: .warning)
            return false
        }
        guard let element = AccessibilityService.element(for: window) else {
            showToast(L("Window not found. Refresh the list."), kind: .warning)
            return false
        }
        let title = AccessibilityService.title(of: element) ?? window.title
        return commitAssignment(
            bundleID: window.bundleID,
            appName: window.appName,
            title: title,
            pid: window.pid,
            element: element,
            frameID: frameID,
            tagID: tagID
        )
    }

    /// Assigns using the suggested label: the app's remembered label, or the
    /// frame's preferred label if none is remembered.
    func assignSuggested(window: AXWindowInfo, toFrame frameID: UUID) {
        guard let frame = activeLayout?.frames.first(where: { $0.id == frameID }) else { return }
        let tagID = state.settings.tagMemory[window.bundleID] ?? frame.preferredTagID
        assign(window: window, toFrame: frameID, tagID: tagID)
    }

    func assignDragPayload(_ payload: WindowDragPayload, toFrame frameID: UUID) {
        guard isTrusted else {
            showToast(L("Accessibility permission is required to move windows."), kind: .warning)
            return
        }
        guard let frame = activeLayout?.frames.first(where: { $0.id == frameID }) else { return }
        guard let element = AccessibilityService.resolve(payload.paletteTarget) else {
            showToast(L("Window %@ not found.", payload.appName), kind: .warning)
            return
        }
        let title = AccessibilityService.title(of: element) ?? payload.title
        let tagID = state.settings.tagMemory[payload.bundleID] ?? frame.preferredTagID
        commitAssignment(
            bundleID: payload.bundleID,
            appName: payload.appName,
            title: title,
            pid: payload.pid,
            element: element,
            frameID: frameID,
            tagID: tagID
        )
    }

    @discardableResult
    private func commitAssignment(
        bundleID: String,
        appName: String,
        title: String,
        pid: pid_t,
        element: AXUIElement,
        frameID: UUID,
        tagID: UUID?
    ) -> Bool {
        guard let layout = activeLayout,
              let frame = layout.frames.first(where: { $0.id == frameID }) else { return false }

        let windowID = AccessibilityService.windowID(for: element)

        state.assignments.removeAll { assignment in
            guard assignment.layoutID == layout.id else { return false }
            if assignment.frameID == frameID { return true }

            if let existingID = assignment.windowID, let windowID {
                return existingID == windowID
            }
            return assignment.bundleID == bundleID && assignment.windowTitle == title
        }

        let assignment = WindowAssignment(
            layoutID: layout.id,
            frameID: frameID,
            bundleID: bundleID,
            appName: appName,
            windowTitle: title,
            tagID: tagID,
            windowID: windowID
        )
        state.assignments.append(assignment)

        if let tagID {
            state.settings.tagMemory[bundleID] = tagID
        } else {
            state.settings.tagMemory.removeValue(forKey: bundleID)
        }

        let visible = ScreenGeometry.visibleFrame(named: layout.screenName)
        let cocoa = ScreenGeometry.cocoaRect(from: frame.rect, in: visible)
        let axRect = ScreenGeometry.axRect(
            from: cocoa,
            primaryHeight: ScreenGeometry.primaryScreenHeight()
        )

        let moved = AccessibilityService.move(element, to: axRect)
        let frameNumber = (layout.frames.firstIndex(where: { $0.id == frameID }) ?? 0) + 1

        if moved {
            showToast(L("Assigned %@ to frame %d.", appName, frameNumber), kind: .success)
        } else {
            showToast(L("Saved, but could not move %@.", appName), kind: .warning)
        }

        selectedFrameID = frameID
        scheduleSave()
        return true
    }

    /// Refresh the stable window identity after a successful match. This also
    /// repairs assignments created before CGWindowID support existed.
    private func updateAssignmentWindow(_ id: UUID, windowID: UInt32, title: String) {
        guard let index = state.assignments.firstIndex(where: { $0.id == id }) else { return }
        var changed = false
        if state.assignments[index].windowID != windowID {
            state.assignments[index].windowID = windowID
            changed = true
        }
        if state.assignments[index].windowTitle != title {
            state.assignments[index].windowTitle = title
            changed = true
        }
        if changed {
            scheduleSave()
        }
    }

    func removeAssignment(_ id: UUID) {
        state.assignments.removeAll { $0.id == id }
        if let frame = selectedFrameID, assignment(for: frame) == nil {
            selectedFrameID = nil
        }
    }

    /// Removes whatever is assigned to a frame in the active layout.
    /// Used by the frame-level X button so a stale assignment ID can never
    /// prevent removal.
    func removeAssignment(forFrame frameID: UUID) {
        guard let layout = activeLayout else { return }
        state.assignments.removeAll { $0.layoutID == layout.id && $0.frameID == frameID }
        if selectedFrameID == frameID {
            selectedFrameID = nil
        }
    }

    func setAssignmentTag(_ id: UUID, tagID: UUID?) {
        guard let index = state.assignments.firstIndex(where: { $0.id == id }) else { return }
        state.assignments[index].tagID = tagID
        state.assignments[index].updatedAt = Date()
        if let tagID {
            state.settings.tagMemory[state.assignments[index].bundleID] = tagID
        } else {
            state.settings.tagMemory.removeValue(forKey: state.assignments[index].bundleID)
        }
    }

    func fillEmptyFrames() {
        guard isTrusted else {
            showToast(L("Accessibility permission is required to arrange windows."), kind: .warning)
            return
        }
        guard let layout = activeLayout else { return }
        let assignments = activeAssignments
        let occupied = Set(assignments.map(\.frameID))
        let emptyFrames = layout.frames.filter { !occupied.contains($0.id) }
        guard !emptyFrames.isEmpty else {
            showToast(L("All frames already have windows."), kind: .info)
            return
        }
        let assignedIDs = Set(assignments.compactMap(\.windowID))
        let assignedTitles = Set(assignments.map { "\($0.bundleID)|\($0.windowTitle)" })
        let candidates = runningWindows.filter { window in
            if let windowID = window.windowID, assignedIDs.contains(windowID) {
                return false
            }
            return !assignedTitles.contains("\(window.bundleID)|\(window.title)")
        }
        guard !candidates.isEmpty else {
            showToast(L("There are no unassigned windows."), kind: .info)
            return
        }

        var count = 0
        for (frame, window) in zip(emptyFrames, candidates) {
            let tagID = state.settings.tagMemory[window.bundleID] ?? frame.preferredTagID
            assign(window: window, toFrame: frame.id, tagID: tagID)
            count += 1
        }
        refreshWindows()
        if count > 0 {
            showToast(L("Assigned %d windows to empty frames.", count), kind: .success)
        }
    }

    func removeWindowAssignment(_ window: AXWindowInfo) {
        guard let assignment = assignment(for: window) else { return }
        removeAssignment(assignment.id)
    }

    // MARK: Apply layout

    func applyLayout(launchMissing: Bool? = nil, reveal: Bool = false) {
        guard isTrusted else {
            showToast(L("Accessibility permission is required to arrange windows."), kind: .warning)
            return
        }
        guard let layout = activeLayout else { return }
        let assignments = activeAssignments
        guard !assignments.isEmpty else {
            showToast(L("No windows are assigned to this layout."), kind: .info)
            return
        }
        guard !isApplying else {
            if reveal { pendingReveal = true }
            return
        }

        let shouldLaunch = launchMissing ?? state.settings.launchMissingApps
        let visible = ScreenGeometry.visibleFrame(named: layout.screenName)
        let primaryHeight = ScreenGeometry.primaryScreenHeight()

        isApplying = true
        applyReport = nil
        statusText = L("Preparing…")

        Task { @MainActor in
            let report = await LayoutEngine.apply(
                layout: layout,
                assignments: assignments,
                visibleFrame: visible,
                primaryHeight: primaryHeight,
                launchMissing: shouldLaunch,
                reveal: reveal,
                onMatch: { [weak self] assignmentID, windowID, title in
                    self?.updateAssignmentWindow(assignmentID, windowID: windowID, title: title)
                },
                progress: { [weak self] text in
                    self?.statusText = text
                }
            )
            isApplying = false
            statusText = nil
            applyReport = report
            refreshWindows()

            if !report.missing.isEmpty || !report.failed.isEmpty {
                showToast(report.summary, kind: .warning)
            } else if report.moved > 0 {
                showToast(report.summary, kind: .success)
            }

            if pendingReveal {
                pendingReveal = false
                // If the current apply already reveals windows, there is no
                // need to run it again; it will raise at the end.
                if !reveal {
                    applyLayout(launchMissing: shouldLaunch, reveal: true)
                }
            }
        }
    }

    /// Applies the layout and brings assigned windows to the front so the user
    /// sees the workspace immediately. Used on launch/Dock click in workspace mode.
    func revealWorkspace() {
        applyLayout(launchMissing: state.settings.launchMissingApps, reveal: true)
    }

    func autoRestoreIfNeeded(reveal: Bool = false) {
        guard state.settings.autoRestoreOnLaunch else { return }
        Task { @MainActor in
            let delay: UInt64 = reveal ? 500_000_000 : 1_200_000_000
            try? await Task.sleep(nanoseconds: delay)
            isTrusted = AccessibilityService.isTrusted
            guard isTrusted else { return }
            refreshWindows()
            guard let layout = activeLayout else { return }
            guard state.assignments.contains(where: { $0.layoutID == layout.id }) else { return }
            applyLayout(
                launchMissing: state.settings.launchMissingApps,
                reveal: reveal
            )
        }
    }

    func dismissReport() {
        applyReport = nil
    }

    // MARK: Layouts

    func setActiveLayout(_ id: UUID) {
        guard state.layouts.contains(where: { $0.id == id }) else { return }
        state.settings.activeLayoutID = id
        isEditing = false
        selectedFrameID = nil
        selectedWindowID = nil
    }

    func createLayout(from preset: LayoutPreset) {
        var name = L(preset.name)
        var suffix = 2
        while state.layouts.contains(where: { $0.name == name }) {
            name = "\(L(preset.name)) \(suffix)"
            suffix += 1
        }
        let frames = preset.rects.enumerated().map { index, rect in
            FrameZone(name: L("Frame %d", index + 1), rect: rect)
        }
        let layout = WorkspaceLayout(
            name: name,
            frames: frames,
            screenName: activeLayout?.screenName ?? NSScreen.main?.localizedName
        )
        state.layouts.append(layout)
        state.settings.activeLayoutID = layout.id
        selectedFrameID = frames.first?.id
        isEditing = true
        showToast(L("Created layout %@.", name), kind: .success)
    }

    func duplicateActiveLayout() {
        guard let layout = activeLayout else { return }
        var frameMap: [UUID: UUID] = [:]
        let frames = layout.frames.map { frame -> FrameZone in
            let newID = UUID()
            frameMap[frame.id] = newID
            return FrameZone(id: newID, name: frame.name, rect: frame.rect, preferredTagID: frame.preferredTagID)
        }
        let copy = WorkspaceLayout(
            name: uniqueLayoutName(base: L("%@ copy", layout.name)),
            frames: frames,
            screenName: layout.screenName
        )
        let copiedAssignments = state.assignments
            .filter { $0.layoutID == layout.id }
            .compactMap { assignment -> WindowAssignment? in
                guard let newFrameID = frameMap[assignment.frameID] else { return nil }
                return WindowAssignment(
                    layoutID: copy.id,
                    frameID: newFrameID,
                    bundleID: assignment.bundleID,
                    appName: assignment.appName,
                    windowTitle: assignment.windowTitle,
                    tagID: assignment.tagID
                )
            }
        state.layouts.append(copy)
        state.assignments.append(contentsOf: copiedAssignments)
        state.settings.activeLayoutID = copy.id
        selectedFrameID = nil
    }

    private func uniqueLayoutName(base: String) -> String {
        var name = base
        var suffix = 2
        while state.layouts.contains(where: { $0.name == name }) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        return name
    }

    func renameLayout(_ id: UUID, name: String) {
        guard let index = state.layouts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.layouts[index].name = trimmed
    }

    func deleteLayout(_ id: UUID) {
        guard state.layouts.count > 1 else {
            showToast(L("Keep at least one layout."), kind: .warning)
            return
        }
        state.layouts.removeAll { $0.id == id }
        state.assignments.removeAll { $0.layoutID == id }
        if state.settings.activeLayoutID == id {
            state.settings.activeLayoutID = state.layouts.first?.id
        }
        selectedFrameID = nil
        isEditing = false
    }

    func setLayoutScreen(_ id: UUID, screenName: String?) {
        guard let index = state.layouts.firstIndex(where: { $0.id == id }) else { return }
        state.layouts[index].screenName = screenName
    }

    // MARK: Frames

    func addFrame() {
        guard let layout = activeLayout,
              let layoutIndex = state.layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        let count = state.layouts[layoutIndex].frames.count
        let step = Double(count % 5) * 0.04
        let rect = NormRect(x: 0.22 + step, y: 0.18 + step, width: 0.4, height: 0.4)
        let frame = FrameZone(name: L("Frame %d", count + 1), rect: rect)
        state.layouts[layoutIndex].frames.append(frame)
        selectedFrameID = frame.id
        isEditing = true
    }

    func updateFrameRect(_ frameID: UUID, rect: NormRect) {
        guard let layoutIndex = layoutIndexForActive(),
              let frameIndex = state.layouts[layoutIndex].frames.firstIndex(where: { $0.id == frameID }) else { return }
        state.layouts[layoutIndex].frames[frameIndex].rect = rect.clamped()
    }

    func renameFrame(_ frameID: UUID, name: String) {
        guard let layoutIndex = layoutIndexForActive(),
              let frameIndex = state.layouts[layoutIndex].frames.firstIndex(where: { $0.id == frameID }) else { return }
        state.layouts[layoutIndex].frames[frameIndex].name = name
    }

    func setFramePreferredTag(_ frameID: UUID, tagID: UUID?) {
        guard let layoutIndex = layoutIndexForActive(),
              let frameIndex = state.layouts[layoutIndex].frames.firstIndex(where: { $0.id == frameID }) else { return }
        state.layouts[layoutIndex].frames[frameIndex].preferredTagID = tagID
    }

    func deleteFrame(_ frameID: UUID) {
        guard let layoutIndex = layoutIndexForActive() else { return }
        state.layouts[layoutIndex].frames.removeAll { $0.id == frameID }
        state.assignments.removeAll { $0.frameID == frameID }
        if selectedFrameID == frameID {
            selectedFrameID = state.layouts[layoutIndex].frames.first?.id
        }
    }

    private func layoutIndexForActive() -> Int? {
        guard let layout = activeLayout else { return nil }
        return state.layouts.firstIndex(where: { $0.id == layout.id })
    }

    // MARK: Tags

    func addTag() {
        let palette = ["#5B8CFF", "#FF8A4C", "#35C759", "#BF5AF2", "#FFD60A", "#64D2FF", "#FF375F", "#AC8E68"]
        let color = palette[state.tags.count % palette.count]
        var name = L("New label")
        var suffix = 2
        while state.tags.contains(where: { $0.name == name }) {
            name = L("New label %d", suffix)
            suffix += 1
        }
        state.tags.append(Tag(name: name, colorHex: color))
    }

    func updateTagName(_ id: UUID, name: String) {
        guard let index = state.tags.firstIndex(where: { $0.id == id }) else { return }
        state.tags[index].name = name
    }

    func updateTagColor(_ id: UUID, colorHex: String) {
        guard let index = state.tags.firstIndex(where: { $0.id == id }) else { return }
        state.tags[index].colorHex = colorHex
    }

    func deleteTag(_ id: UUID) {
        state.tags.removeAll { $0.id == id }
        for index in state.assignments.indices where state.assignments[index].tagID == id {
            state.assignments[index].tagID = nil
        }
        for layoutIndex in state.layouts.indices {
            for frameIndex in state.layouts[layoutIndex].frames.indices
            where state.layouts[layoutIndex].frames[frameIndex].preferredTagID == id {
                state.layouts[layoutIndex].frames[frameIndex].preferredTagID = nil
            }
        }
        state.settings.tagMemory = state.settings.tagMemory.filter { $0.value != id }
        if tagFilter == id { tagFilter = nil }
    }

    func setTagFilter(_ id: UUID?) {
        tagFilter = id
    }

    // MARK: Settings

    func setAutoRestore(_ enabled: Bool) {
        state.settings.autoRestoreOnLaunch = enabled
    }

    func setLaunchMissingApps(_ enabled: Bool) {
        state.settings.launchMissingApps = enabled
    }

    /// Enabled by default for legacy state.json files without workspaceMode.
    var isWorkspaceMode: Bool {
        state.settings.workspaceMode ?? true
    }

    func setWorkspaceMode(_ enabled: Bool) {
        state.settings.workspaceMode = enabled
    }

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
        } catch {
            showToast(L("Could not change launch at login: %@", error.localizedDescription), kind: .warning)
            objectWillChange.send()
        }
    }

    // MARK: Toast

    func showToast(_ text: String, kind: Toast.Kind = .info) {
        let newToast = Toast(text: text, kind: kind)
        toast = newToast
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if toast?.id == newToast.id {
                toast = nil
            }
        }
    }

    // MARK: Persistence

    private static var stateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Jailor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.json")
    }

    private static func loadState() -> PersistedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PersistedState.self, from: data)
        } catch {
            NSLog("Jailor: failed to read state.json — \(error)")
            return nil
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.persistNow()
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    func persistNow() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(state)
            try data.write(to: Self.stateURL, options: .atomic)
        } catch {
            NSLog("Jailor: failed to write state.json — \(error)")
        }
    }
}
