import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(hex: "#6C7CFF")
    static let accentDeep = Color(hex: "#4F5BD5")
    static let teal = Color(hex: "#3DD6C0")
    static let success = Color(hex: "#35C759")
    static let warning = Color(hex: "#FFB020")
    static let danger = Color(hex: "#FF5D5D")

    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)

    static let tagPalette = [
        "#5B8CFF", "#FF8A4C", "#35C759", "#BF5AF2",
        "#FFD60A", "#64D2FF", "#FF375F", "#AC8E68"
    ]
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }

        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if value.count == 8 {
            red = Double((number >> 24) & 0xFF) / 255
            green = Double((number >> 16) & 0xFF) / 255
            blue = Double((number >> 8) & 0xFF) / 255
            alpha = Double(number & 0xFF) / 255
        } else {
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(named: NSImage.applicationIconName) ?? NSImage()
        }
        cache[bundleID] = image
        return image
    }
}

struct AppIconBadge: View {
    let bundleID: String
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: AppIcons.icon(for: bundleID))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

struct TagChip: View {
    @ObservedObject private var l10n = Localization.shared

    let tag: Tag?
    var selected: Bool = false
    var compact: Bool = false
    var action: (() -> Void)?

    private var color: Color {
        if let tag { return Color(hex: tag.colorHex) }
        return Color.secondary
    }

    var body: some View {
        if let action {
            Button(action: action) {
                chip
            }
            .buttonStyle(.plain)
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tag == nil ? Color.secondary.opacity(0.35) : color)
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
            Text(tag?.name ?? L("No label"))
                .font(.system(size: compact ? 9.5 : 10.5, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: compact ? 20 : 24)
        .background(
            Capsule()
                .fill(selected ? color.opacity(0.22) : Color.primary.opacity(0.055))
        )
        .overlay(
            Capsule()
                .stroke(selected ? color.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .contentShape(Capsule())
    }
}

struct ToastView: View {
    let toast: Toast

    private var icon: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch toast.kind {
        case .info: return Theme.accent
        case .success: return Theme.success
        case .warning: return Theme.warning
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(toast.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: AnyView?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct DashedBorder: ViewModifier {
    var color: Color
    var radius: CGFloat
    var dash: [CGFloat] = [5, 4]

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(color, style: StrokeStyle(lineWidth: 1, dash: dash))
        )
    }
}
