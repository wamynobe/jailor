import SwiftUI
import AppKit

@MainActor
final class PaletteModel: ObservableObject {
    let store: AppStore
    let target: PaletteTarget

    @Published var selectedTagID: UUID?
    @Published var hoveredIndex: Int?
    var onClose: (() -> Void)?

    init(store: AppStore, target: PaletteTarget) {
        self.store = store
        self.target = target
        self.selectedTagID = store.recommendedTag(for: target)
    }

    var frames: [FrameZone] {
        store.activeLayout?.frames ?? []
    }

    var layoutName: String {
        store.activeLayout?.name ?? L("Layout")
    }

    func tag(for id: UUID?) -> Tag? {
        store.tag(id)
    }

    func assignment(for frame: FrameZone) -> WindowAssignment? {
        store.assignment(for: frame.id)
    }

    func selectTag(_ id: UUID?) {
        selectedTagID = id
    }

    func cycleTag(_ direction: Int) {
        let options: [UUID?] = [nil] + store.tags.map { Optional($0.id) }
        guard !options.isEmpty else { return }
        let current = options.firstIndex(where: { $0 == selectedTagID }) ?? 0
        let next = (current + direction + options.count) % options.count
        selectedTagID = options[next]
    }

    func assign(_ index: Int) {
        guard index >= 0, index < frames.count else { return }
        let frame = frames[index]
        if store.assign(target: target, toFrame: frame.id, tagID: selectedTagID) {
            onClose?()
        } else {
            NSSound.beep()
        }
    }

    func close() {
        onClose?()
    }
}

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var l10n = Localization.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            preview
            divider
            tagBar
            footer
        }
        .frame(width: 620, height: 468)
        .background(paletteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }

    private var paletteBackground: some View {
        ZStack {
            Color(hex: "#111526")
            LinearGradient(
                colors: [
                    Theme.accent.opacity(0.16),
                    Color.clear,
                    Theme.teal.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [.white.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconBadge(bundleID: model.target.bundleID, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.target.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(L("focused window"))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.34))
                }
                Text(model.target.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(L("ASSIGN TO FRAME"))
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.32))

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(L("Close (Esc)"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var preview: some View {
        GeometryReader { geometry in
            let screenSize = store.activeLayout.map { store.screenSize(for: $0) } ?? CGSize(width: 16, height: 9)
            let aspect = screenSize.height > 0 ? screenSize.width / screenSize.height : 1.6
            let canvas = ScreenGeometry.fittedRect(aspect: aspect, in: geometry.size, padding: 10)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.022))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                    )
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(x: canvas.minX, y: canvas.minY)

                ForEach(Array(model.frames.enumerated()), id: \.element.id) { index, frame in
                    let rect = CGRect(
                        x: canvas.minX + CGFloat(frame.rect.x) * canvas.width,
                        y: canvas.minY + CGFloat(frame.rect.y) * canvas.height,
                        width: CGFloat(frame.rect.width) * canvas.width,
                        height: CGFloat(frame.rect.height) * canvas.height
                    )

                    paletteFrame(index: index, frame: frame)
                        .frame(
                            width: max(36, rect.width - 6),
                            height: max(28, rect.height - 6)
                        )
                        .offset(x: rect.minX + 3, y: rect.minY + 3)
                        .onHover { isHovering in
                            if isHovering {
                                model.hoveredIndex = index
                            } else if model.hoveredIndex == index {
                                model.hoveredIndex = nil
                            }
                        }
                        .onTapGesture {
                            model.assign(index)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 258)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func paletteFrame(index: Int, frame: FrameZone) -> some View {
        let assignment = model.assignment(for: frame)
        let tag = model.tag(for: assignment?.tagID ?? frame.preferredTagID)
        let hovered = model.hoveredIndex == index
        let selectedTag = model.selectedTagID
        let matchesTag = selectedTag != nil && (assignment?.tagID ?? frame.preferredTagID) == selectedTag

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("\(index + 1)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(hovered ? 0.20 : 0.10)))

                Text(frame.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let tag {
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 5, height: 5)
                }
            }

            if let assignment {
                HStack(spacing: 5) {
                    AppIconBadge(bundleID: assignment.bundleID, size: 16)
                    Text(assignment.windowTitle)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            } else {
                Spacer(minLength: 0)
                Text(hovered ? L("Press %d", index + 1) : L("Empty"))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(hovered ? 0.62 : 0.28))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.13 : (matchesTag ? 0.075 : 0.045)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    hovered ? Theme.accent : (tag.map { Color(hex: $0.colorHex).opacity(0.35) } ?? Color.white.opacity(0.08)),
                    lineWidth: hovered ? 1.6 : 0.8
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var tagBar: some View {
        HStack(spacing: 8) {
            Text(L("LABEL"))
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.30))

            TagChip(tag: nil, selected: model.selectedTagID == nil) {
                model.selectTag(nil)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.tags) { tag in
                        TagChip(tag: tag, selected: model.selectedTagID == tag.id) {
                            model.selectTag(tag.id)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            KeyCap(text: "Tab")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            KeyCap(text: "1–9")
            Text(L("assign"))
            SeparatorDot()
            KeyCap(text: "Tab")
            Text(L("change label"))
            SeparatorDot()
            KeyCap(text: "Esc")
            Text(L("close"))

            Spacer()

            Text(L("%d frames · %@", model.frames.count, model.layoutName))
                .lineLimit(1)
        }
        .font(.system(size: 9))
        .foregroundStyle(.white.opacity(0.36))
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Color.white.opacity(0.025))
    }
}

private struct SeparatorDot: View {
    var body: some View {
        Text("·")
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.22))
    }
}
