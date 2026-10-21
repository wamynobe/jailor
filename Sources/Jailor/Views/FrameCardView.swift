import SwiftUI
import AppKit

struct FrameCardView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var l10n = Localization.shared

    let layout: WorkspaceLayout
    let frame: FrameZone
    let index: Int
    let canvasSize: CGSize

    @State private var hovered = false
    @State private var isDropTarget = false
    @State private var dragOrigin: NormRect?
    @State private var resizeOrigin: NormRect?

    private var assignment: WindowAssignment? {
        store.assignment(for: frame.id)
    }

    private var relevantTagID: UUID? {
        assignment?.tagID ?? frame.preferredTagID
    }

    private var dimmed: Bool {
        guard let filter = store.tagFilter else { return false }
        return relevantTagID != filter
    }

    private var isSelected: Bool {
        store.selectedFrameID == frame.id
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 215 || geometry.size.height < 135
            card(compact: compact)
        }
    }

    private func card(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: compact)
            if let assignment {
                filledContent(assignment, compact: compact)
            } else {
                emptyContent(compact: compact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(dimmed ? 0.32 : 1)
        .saturation(dimmed ? 0.25 : 1)
        .animation(.easeOut(duration: 0.14), value: dimmed)
        .onHover { hovered = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if let assignment {
                    store.focus(assignmentID: assignment.id)
                }
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                store.selectedFrameID = frame.id
            }
        )
        .gesture(moveGesture, including: store.isEditing ? .all : .none)
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.compactMap(WindowDragPayload.parse).first else { return false }
            store.assignDragPayload(payload, toFrame: frame.id)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) {
                isDropTarget = targeted
            }
        }
        .contextMenu {
            contextMenu
        }
        .help(assignment == nil ? L("Drag a window into this frame") : L("Double-click to focus"))
    }

    // MARK: Header

    private func header(compact: Bool) -> some View {
        HStack(spacing: 5) {
            Text("\(index + 1)")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color.white.opacity(0.10)))

            Text(frame.name)
                .font(.system(size: compact ? 9 : 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)

            if store.isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.26))
            }

            Spacer(minLength: 2)

            if let tag = store.tag(relevantTagID) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 5, height: 5)
                    if !compact {
                        Text(tag.name)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.top, compact ? 6 : 8)
        .padding(.bottom, compact ? 3 : 5)
    }

    // MARK: Content

    private func filledContent(_ assignment: WindowAssignment, compact: Bool) -> some View {
        let running = store.isRunning(assignment)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                AppIconBadge(bundleID: assignment.bundleID, size: compact ? 18 : 25)
                VStack(alignment: .leading, spacing: 1) {
                    if !compact {
                        Text(assignment.appName.uppercased())
                            .font(.system(size: 7.5, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(.white.opacity(0.36))
                            .lineLimit(1)
                    }
                    Text(assignment.windowTitle)
                        .font(.system(size: compact ? 10 : 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.93))
                        .lineLimit(compact ? 2 : 3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(running ? Theme.success : Color.white.opacity(0.24))
                    .frame(width: 4.5, height: 4.5)
                Text(running ? L("Running") : L("Not running"))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.40))

                Spacer(minLength: 0)

                if hovered && !store.isEditing {
                    Button {
                        store.focus(assignmentID: assignment.id)
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Jump to window"))

                    Button {
                        store.removeAssignment(assignment.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Remove from frame"))
                }
            }
        }
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.top, 1)
        .padding(.bottom, compact ? 6 : 8)
    }

    private func emptyContent(compact: Bool) -> some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Image(systemName: "rectangle.dashed")
                .font(.system(size: compact ? 14 : 19, weight: .light))
                .foregroundStyle(.white.opacity(0.22))
            if !compact {
                Text(L("Drag a window here"))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.36))
                HStack(spacing: 3) {
                    KeyCap(text: "⌃")
                    KeyCap(text: "⌥")
                    KeyCap(text: "\(index + 1)")
                }
                .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
    }

    // MARK: Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDropTarget ? 0.14 : 0.065),
                        Color.white.opacity(0.028)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(
                color: isDropTarget ? Theme.accent.opacity(0.35) : Color.black.opacity(0.12),
                radius: isDropTarget ? 12 : 4,
                y: 2
            )
    }

    private var cardBorder: some View {
        let selected = store.isEditing && isSelected
        let color: Color
        if isDropTarget {
            color = Theme.accent
        } else if selected {
            color = Theme.accent.opacity(0.85)
        } else if let tag = store.tag(relevantTagID) {
            color = Color(hex: tag.colorHex).opacity(0.40)
        } else {
            color = Color.white.opacity(0.10)
        }

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(color, lineWidth: isDropTarget || selected ? 1.5 : 0.9)
    }

    @ViewBuilder
    private var resizeHandle: some View {
        if store.isEditing {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(width: 17, height: 17)
            .padding(5)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture)
            .help(L("Drag to resize the frame"))
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let assignment {
            Button(L("Jump to window")) {
                store.focus(assignmentID: assignment.id)
            }

            Menu(L("Change label")) {
                Button(L("No label")) {
                    store.setAssignmentTag(assignment.id, tagID: nil)
                }
                Divider()
                ForEach(store.tags) { tag in
                    Button(tag.name) {
                        store.setAssignmentTag(assignment.id, tagID: tag.id)
                    }
                }
            }

            Button(L("Remove from frame"), role: .destructive) {
                store.removeAssignment(assignment.id)
            }
        } else {
            if let selectedID = store.selectedWindowID,
               let window = store.runningWindows.first(where: { $0.id == selectedID }) {
                Button(L("Assign selected %@ here", window.appName)) {
                    store.assignSuggested(window: window, toFrame: frame.id)
                }
            } else {
                Button(L("Drag a window into this frame.")) {}
                    .disabled(true)
            }
        }

        Divider()

        Menu(L("Frame preferred label")) {
            Button(L("No label")) {
                store.setFramePreferredTag(frame.id, tagID: nil)
            }
            Divider()
            ForEach(store.tags) { tag in
                Button(tag.name) {
                    store.setFramePreferredTag(frame.id, tagID: tag.id)
                }
            }
        }

        if store.isEditing {
            Divider()
            Button(L("Delete frame"), role: .destructive) {
                store.deleteFrame(frame.id)
            }
        }
    }

    // MARK: Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard store.isEditing, canvasSize.width > 1, canvasSize.height > 1 else { return }
                if dragOrigin == nil {
                    dragOrigin = frame.rect
                    store.selectedFrameID = frame.id
                }
                guard let start = dragOrigin else { return }
                let dx = Double(value.translation.width / canvasSize.width)
                let dy = Double(value.translation.height / canvasSize.height)
                store.updateFrameRect(
                    frame.id,
                    rect: NormRect(
                        x: start.x + dx,
                        y: start.y + dy,
                        width: start.width,
                        height: start.height
                    )
                )
            }
            .onEnded { _ in
                dragOrigin = nil
                store.persistNow()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard store.isEditing, canvasSize.width > 1, canvasSize.height > 1 else { return }
                if resizeOrigin == nil {
                    resizeOrigin = frame.rect
                    store.selectedFrameID = frame.id
                }
                guard let start = resizeOrigin else { return }
                let dw = Double(value.translation.width / canvasSize.width)
                let dh = Double(value.translation.height / canvasSize.height)
                store.updateFrameRect(
                    frame.id,
                    rect: NormRect(
                        x: start.x,
                        y: start.y,
                        width: start.width + dw,
                        height: start.height + dh
                    )
                )
            }
            .onEnded { _ in
                resizeOrigin = nil
                store.persistNow()
            }
    }
}
