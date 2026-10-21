import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var l10n = Localization.shared
    let revealWorkspace: () -> Void

    @State private var showRenameAlert = false
    @State private var showDeleteAlert = false
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.5)

            if !store.isTrusted {
                permissionBanner
            }

            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if let report = store.applyReport {
                        reportBanner(report)
                    }
                }

            if store.isEditing, let layout = store.activeLayout {
                FrameInspector(layout: layout)
            }
        }
        .background(Theme.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(L("Rename layout"), isPresented: $showRenameAlert) {
            TextField(L("Layout name"), text: $renameDraft)
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Save")) {
                if let layout = store.activeLayout {
                    store.renameLayout(layout.id, name: renameDraft)
                }
            }
        }
        .confirmationDialog(
            L("Delete layout?"),
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button(L("Delete layout"), role: .destructive) {
                if let layout = store.activeLayout {
                    store.deleteLayout(layout.id)
                }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Windows assigned to this layout will be removed from their frames. The windows themselves will not be closed."))
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            layoutMenu

            if let layout = store.activeLayout, !store.isEditing {
                HStack(spacing: 4) {
                    Image(systemName: "display")
                        .font(.system(size: 9, weight: .medium))
                    Text(store.screenName(for: layout))
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(L("%d frames", layout.frames.count))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let filterID = store.tagFilter, let tag = store.tag(filterID) {
                Button {
                    store.setTagFilter(nil)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: tag.colorHex))
                            .frame(width: 5, height: 5)
                        Text(tag.name)
                            .font(.system(size: 9.5, weight: .medium))
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: tag.colorHex).opacity(0.14)))
                    .foregroundStyle(Color(hex: tag.colorHex))
                }
                .buttonStyle(.plain)
                .help(L("Remove label filter"))
            }

            Spacer(minLength: 8)

            if store.isEditing {
                Button {
                    store.addFrame()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text(L("Add frame"))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                revealWorkspace()
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                    .frame(width: 27, height: 27)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.teal.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.activeAssignments.isEmpty)
            .opacity(store.activeAssignments.isEmpty ? 0.4 : 1)
            .help(L("Hide the Jailor UI and reveal assigned windows (⌘⇧R)"))

            IconActionButton(systemName: "arrow.clockwise", help: L("Refresh window list")) {
                store.refreshTrust()
                store.refreshWindows()
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.isEditing.toggle()
                }
                if !store.isEditing {
                    store.selectedFrameID = nil
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: store.isEditing ? "checkmark" : "slider.horizontal.3")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(store.isEditing ? L("Done") : L("Edit"))
                        .font(.system(size: 10.5, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(store.isEditing ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.055))
                )
                .foregroundStyle(store.isEditing ? Theme.accent : Color.primary)
            }
            .buttonStyle(.plain)

            Button {
                store.applyLayout()
            } label: {
                HStack(spacing: 6) {
                    if store.isApplying {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                            .frame(width: 11, height: 11)
                    } else {
                        Image(systemName: "rectangle.split.3x1")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(store.isApplying ? L("Applying…") : L("Apply"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.accent)
                )
                .opacity(store.activeAssignments.isEmpty ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(store.isApplying || store.activeAssignments.isEmpty)
            .help(L("Arrange all assigned windows into their frames (⌘↩)"))
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(.ultraThinMaterial)
    }

    private var layoutMenu: some View {
        Menu {
            ForEach(store.layouts) { layout in
                Button {
                    store.setActiveLayout(layout.id)
                } label: {
                    if layout.id == store.activeLayout?.id {
                        Label(layout.name, systemImage: "checkmark")
                    } else {
                        Text(layout.name)
                    }
                }
            }

            Divider()

            Menu(L("Create new layout")) {
                ForEach(LayoutPresets.all) { preset in
                    Button(L(preset.name)) {
                        store.createLayout(from: preset)
                    }
                }
            }

            Button(L("Duplicate layout")) {
                store.duplicateActiveLayout()
            }

            Button(L("Fill empty frames")) {
                store.refreshTrust()
                store.refreshWindows()
                store.fillEmptyFrames()
            }

            Button(L("Rename…")) {
                renameDraft = store.activeLayout?.name ?? ""
                showRenameAlert = true
            }

            Button(L("Delete layout…"), role: .destructive) {
                showDeleteAlert = true
            }
            .disabled(store.layouts.count <= 1)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(store.activeLayout?.name ?? L("Layout"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Choose, create, or edit a layout"))
    }

    private var permissionBanner: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Theme.warning.opacity(0.16))
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.warning)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Jailor needs Accessibility"))
                    .font(.system(size: 12, weight: .semibold))
                Text(L("This permission lets Jailor read window titles and move windows from other apps. Enable it once in System Settings."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(L("Grant")) {
                store.requestAccessibility()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(L("Check again")) {
                store.refreshTrust()
                store.refreshWindows()
                if store.isTrusted, store.isWorkspaceMode, !store.activeAssignments.isEmpty {
                    revealWorkspace()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.warning.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Theme.warning.opacity(0.22), lineWidth: 0.8)
        )
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            if let layout = store.activeLayout {
                let screenSize = store.screenSize(for: layout)
                let aspect = screenSize.height > 0 ? screenSize.width / screenSize.height : 1.6
                let screenRect = ScreenGeometry.fittedRect(
                    aspect: aspect,
                    in: geometry.size,
                    padding: 34
                )

                ZStack(alignment: .topLeading) {
                    screenBackground(rect: screenRect)

                    ForEach(Array(layout.frames.enumerated()), id: \.element.id) { index, frame in
                        let rect = CGRect(
                            x: screenRect.minX + CGFloat(frame.rect.x) * screenRect.width,
                            y: screenRect.minY + CGFloat(frame.rect.y) * screenRect.height,
                            width: CGFloat(frame.rect.width) * screenRect.width,
                            height: CGFloat(frame.rect.height) * screenRect.height
                        )

                        FrameCardView(
                            layout: layout,
                            frame: frame,
                            index: index,
                            canvasSize: screenRect.size
                        )
                        .frame(
                            width: max(54, rect.width - 8),
                            height: max(42, rect.height - 8)
                        )
                        .offset(x: rect.minX + 4, y: rect.minY + 4)
                    }

                    if layout.frames.isEmpty {
                        emptyCanvas
                            .frame(width: screenRect.width, height: screenRect.height)
                            .offset(x: screenRect.minX, y: screenRect.minY)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.colorScheme, .dark)
            } else {
                Text(L("No layout"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func screenBackground(rect: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#0C101F"), Color(hex: "#161B2F"), Color(hex: "#101425")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Canvas { context, size in
                var path = Path()
                var x = 14.0
                while x < size.width {
                    var y = 14.0
                    while y < size.height {
                        path.addEllipse(in: CGRect(x: x, y: y, width: 1.1, height: 1.1))
                        y += 26
                    }
                    x += 26
                }
                context.fill(path, with: .color(.white.opacity(0.05)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.03), lineWidth: 5)
                .padding(2)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .shadow(color: .black.opacity(0.32), radius: 26, y: 14)
    }

    private var emptyCanvas: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.28))
            Text(L("This layout has no frames"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Button {
                store.addFrame()
            } label: {
                Text(L("Add the first frame"))
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func reportBanner(_ report: ApplyReport) -> some View {
        let isSuccess = report.missing.isEmpty && report.failed.isEmpty
        return HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSuccess ? Theme.success : Theme.warning)
            Text(report.summary)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 10)
            Button {
                store.dismissReport()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
    }
}

// MARK: - Toolbar icon button

struct IconActionButton: View {
    let systemName: String
    var help: String = ""
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 27, height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
