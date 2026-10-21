import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var l10n = Localization.shared
    let openSettings: () -> Void
    let openPalette: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            paletteButton
            Divider().opacity(0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tagsSection
                    windowsSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 278)
        .background(Theme.sidebar)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 0) {
                Text("Jailor")
                    .font(.system(size: 16, weight: .bold))
                Text(L("Workspace for Mac"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help(L("Settings"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var paletteButton: some View {
        Button(action: openPalette) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(L("Quick assign"))
                    .font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    KeyCap(text: "⌃")
                    KeyCap(text: "⌥")
                    KeyCap(text: "Space")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Theme.accent.opacity(0.22), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .help(L("Open the quick-assign palette"))
    }

    // MARK: Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(
                title: L("Labels"),
                trailing: AnyView(
                    Button(action: openSettings) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(L("Add or edit labels in Settings"))
                )
            )

            TagFilterRow(
                color: Color.secondary,
                name: L("All windows"),
                count: store.activeAssignments.count,
                selected: store.tagFilter == nil,
                action: { store.setTagFilter(nil) }
            )

            ForEach(store.tags) { tag in
                TagFilterRow(
                    color: Color(hex: tag.colorHex),
                    name: tag.name,
                    count: store.tagCount(tag.id),
                    selected: store.tagFilter == tag.id,
                    action: {
                        store.setTagFilter(store.tagFilter == tag.id ? nil : tag.id)
                    }
                )
            }
        }
    }

    // MARK: Windows

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(
                title: L("Open windows"),
                trailing: AnyView(
                    HStack(spacing: 6) {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        }
                        Button {
                            store.refreshTrust()
                            store.refreshWindows()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        .help(L("Refresh window list"))
                    }
                )
            )

            searchField

            if !store.isTrusted {
                permissionHint
            } else if store.filteredWindows().isEmpty {
                Text(store.searchText.isEmpty ? L("No windows found.\nOpen an application.") : L("No results."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(store.filteredWindows()) { window in
                        windowRow(window)
                    }
                }
            }

            if store.isTrusted {
                Text(L("Drag a window into a frame on the dashboard."))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField(L("Search windows…"), text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func windowRow(_ window: AXWindowInfo) -> some View {
        let assignment = store.assignment(for: window)
        let number = assignment.flatMap { store.frameNumber(for: $0) }
        return WindowRowView(
            window: window,
            assignment: assignment,
            frameNumber: number,
            tag: store.tag(assignment?.tagID),
            frames: store.activeLayout?.frames ?? [],
            isSelected: store.selectedWindowID == window.id,
            onSelect: { store.selectWindow(window) },
            onFocus: { store.focus(window: window) },
            onAssign: { frameID in store.assignSuggested(window: window, toFrame: frameID) },
            onRemove: { store.removeWindowAssignment(window) }
        )
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warning)
                Text(L("Accessibility required"))
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(L("Jailor needs this permission to read window titles and move windows from other apps."))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button(L("Grant")) { store.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                Button(L("Check again")) {
                    store.refreshTrust()
                    store.refreshWindows()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.warning.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.warning.opacity(0.22), lineWidth: 0.8)
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.isTrusted ? Theme.success : Theme.warning)
                    .frame(width: 6, height: 6)
                Text(store.isTrusted ? L("Accessibility is on") : L("Accessibility not granted"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.isTrusted {
                    Button(L("Grant")) { store.requestAccessibility() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            if store.isTrusted {
                Text(L("⌃ ⌥ 1–9 assigns the focused window to the matching frame."))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }
}

// MARK: - Tag filter row

private struct TagFilterRow: View {
    let color: Color
    let name: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(name)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.08) : (hovered ? Color.primary.opacity(0.04) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Window row

private struct WindowRowView: View {
    @ObservedObject private var l10n = Localization.shared

    let window: AXWindowInfo
    let assignment: WindowAssignment?
    let frameNumber: Int?
    let tag: Tag?
    let frames: [FrameZone]
    let isSelected: Bool
    let onSelect: () -> Void
    let onFocus: () -> Void
    let onAssign: (UUID) -> Void
    let onRemove: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 7) {
            AppIconBadge(bundleID: window.bundleID, size: 19)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(window.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if window.isMinimized {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(window.appName)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if let tag {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 5, height: 5)
            }

            if let frameNumber {
                Text("\(frameNumber)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Theme.accent.opacity(0.16)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.12) : (hovered ? Color.primary.opacity(0.045) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { onFocus() }
        .onTapGesture { onSelect() }
        .draggable(window.dragPayloadJSON) {
            HStack(spacing: 8) {
                AppIconBadge(bundleID: window.bundleID, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.appName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(window.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
        }
        .contextMenu {
            Button(L("Jump to window"), action: onFocus)

            if !frames.isEmpty {
                Menu(L("Assign to frame")) {
                    ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                        Button("\(index + 1). \(frame.name)") {
                            onAssign(frame.id)
                        }
                    }
                }
            }

            if assignment != nil {
                Divider()
                Button(L("Remove from frame"), role: .destructive, action: onRemove)
            }
        }
        .help(L("Drag into a frame · double-click to focus"))
    }
}
