import AppKit
import ApplicationServices

@MainActor
enum LayoutEngine {

    static func apply(
        layout: WorkspaceLayout,
        assignments: [WindowAssignment],
        visibleFrame: CGRect,
        primaryHeight: CGFloat,
        launchMissing: Bool,
        reveal: Bool = false,
        onMatch: ((UUID, UInt32, String) -> Void)? = nil,
        progress: ((String) -> Void)? = nil
    ) async -> ApplyReport {
        var report = ApplyReport()
        var used = Set<String>()
        var launchedBundles = Set<String>()
        var matchedWindows: [(info: AXWindowInfo, element: AXUIElement)] = []
        var windows = AccessibilityService.allWindows()

        let frameOrder = Dictionary(
            uniqueKeysWithValues: layout.frames.enumerated().map { ($0.element.id, $0.offset) }
        )
        let ordered = assignments.sorted {
            (frameOrder[$0.frameID] ?? 999) < (frameOrder[$1.frameID] ?? 999)
        }

        for (index, assignment) in ordered.enumerated() {
            progress?(L("Tiling %@ — %d/%d…", assignment.appName, index + 1, ordered.count))

            guard let frame = layout.frames.first(where: { $0.id == assignment.frameID }) else { continue }

            let cocoa = ScreenGeometry.cocoaRect(from: frame.rect, in: visibleFrame)
            let axRect = ScreenGeometry.axRect(from: cocoa, primaryHeight: primaryHeight)

            var match = findMatch(
                assignment: assignment,
                in: windows,
                used: used,
                targetRect: axRect
            )

            if match == nil, launchMissing, !launchedBundles.contains(assignment.bundleID) {
                launchedBundles.insert(assignment.bundleID)
                let running = NSRunningApplication
                    .runningApplications(withBundleIdentifier: assignment.bundleID)
                    .first
                if let running {
                    if #available(macOS 14.0, *) {
                        running.activate()
                    } else {
                        running.activate(options: [.activateIgnoringOtherApps])
                    }
                } else if await launch(bundleID: assignment.bundleID) {
                    report.launched += 1
                }

                // Wait for a window to appear (up to ~4 seconds).
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    windows = AccessibilityService.allWindows()
                    match = findMatch(
                        assignment: assignment,
                        in: windows,
                        used: used,
                        targetRect: axRect
                    )
                    if match != nil { break }
                }
            }

            guard let match else {
                report.missing.append("\(assignment.appName) — \(assignment.windowTitle)")
                continue
            }

            used.insert(match.info.id)

            if let windowID = match.info.windowID {
                onMatch?(assignment.id, windowID, match.info.title)
            }

            if AccessibilityService.move(match.element, to: axRect) {
                report.moved += 1
            } else {
                report.failed.append("\(assignment.appName) — \(assignment.windowTitle)")
            }
            matchedWindows.append(match)

            try? await Task.sleep(nanoseconds: 35_000_000)
        }

        if reveal, !matchedWindows.isEmpty {
            progress?(L("Bringing windows to front…"))
            await bringToFront(matchedWindows)
        }

        progress?(L("Finished"))
        return report
    }

    private static func findMatch(
        assignment: WindowAssignment,
        in windows: [(info: AXWindowInfo, element: AXUIElement)],
        used: Set<String>,
        targetRect: CGRect
    ) -> (info: AXWindowInfo, element: AXUIElement)? {
        let candidates = windows.filter {
            $0.info.bundleID == assignment.bundleID && !used.contains($0.info.id)
        }
        guard !candidates.isEmpty else { return nil }

        // Stable identity: CGWindowID is unique per open window.
        if let windowID = assignment.windowID,
           let exactID = candidates.first(where: { $0.info.windowID == windowID }) {
            return exactID
        }

        // If the window was relaunched, its CGWindowID changed. A unique
        // title match is safe to use and lets us refresh the stored ID.
        let titleMatches = candidates.filter { $0.info.title == assignment.windowTitle }
        if titleMatches.count == 1 {
            return titleMatches[0]
        }

        // A stale CGWindowID must not silently select another window of the
        // same app. Report it as missing so the user can reassign.
        if assignment.windowID != nil {
            return nil
        }

        let pool = titleMatches.isEmpty ? candidates : titleMatches
        if pool.count == 1 {
            return pool[0]
        }

        // Legacy assignments have no window ID. Prefer the window closest to
        // the frame it was last tiled into, with a confidence margin.
        let scored = pool.compactMap { candidate -> (candidate: (info: AXWindowInfo, element: AXUIElement), distance: CGFloat)? in
            guard let bounds = candidate.info.bounds else { return nil }
            return (candidate, frameDistance(bounds, targetRect))
        }
        .sorted { $0.distance < $1.distance }

        if let best = scored.first, best.distance < 160 {
            if scored.count == 1 { return best.candidate }
            if best.distance + 80 < scored[1].distance { return best.candidate }
        }

        return nil
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    /// Brings every assigned window to the front.
    ///
    /// Raising a background app's window often only affects that app. Activate
    /// each app in reverse frame order (last frame → first frame), make the
    /// assigned window key, then run a final raise pass. The first frame's app
    /// is activated last so it receives focus.
    private static func bringToFront(
        _ matches: [(info: AXWindowInfo, element: AXUIElement)]
    ) async {
        guard !matches.isEmpty else { return }

        var order: [pid_t] = []
        var groups: [pid_t: [(info: AXWindowInfo, element: AXUIElement)]] = [:]

        for match in matches {
            let pid = match.info.pid
            if groups[pid] == nil {
                order.append(pid)
            }
            groups[pid, default: []].append(match)
        }

        for pid in order.reversed() {
            if let app = NSRunningApplication(processIdentifier: pid) {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
            }

            // Give AppKit a moment to activate the app, then make the exact
            // assigned window key. Without this, an app with multiple windows
            // (for example VS Code) can show its newest window instead.
            try? await Task.sleep(nanoseconds: 30_000_000)
            for match in groups[pid] ?? [] {
                AccessibilityService.makeKey(match.element, pid: pid)
            }

            try? await Task.sleep(nanoseconds: 45_000_000)
        }

        // Final raise pass without activating more apps, so every assigned
        // window stays above unrelated application windows.
        for match in matches.reversed() {
            AccessibilityService.raise(match.element)
        }

        // Focus the first frame's window again, after all raises.
        if let first = matches.first {
            AccessibilityService.makeKey(first.element, pid: first.info.pid)
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    static func launch(bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        } catch {
            NSLog("Jailor: failed to open \(bundleID) — \(error)")
            return false
        }
    }
}
