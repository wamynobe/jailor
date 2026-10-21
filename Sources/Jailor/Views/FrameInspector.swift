import SwiftUI
import AppKit

struct FrameInspector: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var l10n = Localization.shared
    let layout: WorkspaceLayout

    private var selectedFrame: FrameZone? {
        layout.frames.first(where: { $0.id == store.selectedFrameID })
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                if let frame = selectedFrame {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)

                    TextField(L("Frame name"), text: nameBinding(frame))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 140)

                    tagMenu(frame)
                    screenMenu

                    Button {
                        store.deleteFrame(frame.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Delete this frame"))

                    Spacer()

                    Text(L("Drag to move · drag the bottom-right corner to resize"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(L("Select a frame to rename it, set a preferred label, or delete it."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L("Drag to move · drag the bottom-right corner to resize"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func nameBinding(_ frame: FrameZone) -> Binding<String> {
        Binding(
            get: {
                store.activeLayout?.frames.first(where: { $0.id == frame.id })?.name ?? frame.name
            },
            set: { store.renameFrame(frame.id, name: $0) }
        )
    }

    private func tagMenu(_ frame: FrameZone) -> some View {
        let tag = store.tag(frame.preferredTagID)
        return Menu {
            Button(L("No label")) {
                store.setFramePreferredTag(frame.id, tagID: nil)
            }
            Divider()
            ForEach(store.tags) { item in
                Button(item.name) {
                    store.setFramePreferredTag(frame.id, tagID: item.id)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tag.map { Color(hex: $0.colorHex) } ?? Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(tag?.name ?? L("Preferred label: None"))
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Label assigned automatically when a window is dragged into this frame"))
    }

    private var screenMenu: some View {
        Menu {
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                Button(screen.localizedName) {
                    store.setLayoutScreen(layout.id, screenName: screen.localizedName)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "display")
                    .font(.system(size: 8.5))
                Text(store.screenName(for: layout))
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Screen for this layout"))
    }
}
