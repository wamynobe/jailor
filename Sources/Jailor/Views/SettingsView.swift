import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var l10n = Localization.shared

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { store.state.settings.autoRestoreOnLaunch },
                        set: { store.setAutoRestore($0) }
                    )
                ) {
                    Text(L("Auto-restore layout when Jailor opens"))
                }
                Toggle(
                    isOn: Binding(
                        get: { store.state.settings.launchMissingApps },
                        set: { store.setLaunchMissingApps($0) }
                    )
                ) {
                    Text(L("Relaunch closed apps on restore"))
                }
                Toggle(
                    isOn: Binding(
                        get: { store.isLaunchAtLoginEnabled },
                        set: { store.setLaunchAtLogin($0) }
                    )
                ) {
                    Text(L("Launch at login"))
                }
            } header: {
                Text(L("Restore & launch"))
            } footer: {
                Text(L("When Jailor launches, assigned windows return to their frames. Closed apps are reopened on a best-effort basis."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    isOn: Binding(
                        get: { store.isWorkspaceMode },
                        set: { store.setWorkspaceMode($0) }
                    )
                ) {
                    Text(L("Workspace mode: hide Jailor UI"))
                }

                HStack(spacing: 8) {
                    Text(L("Language"))
                    Spacer(minLength: 8)

                    Menu {
                        ForEach(AppLanguage.allCases) { language in
                            Button {
                                l10n.language = language
                            } label: {
                                if l10n.language == language {
                                    Label(language.displayName, systemImage: "checkmark")
                                } else {
                                    Text(language.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(l10n.language.displayName)
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.055))
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            } header: {
                Text(L("Interface"))
            }

            Section {
                ShortcutRow(keys: ["⌃", "⌥", "Space"], title: L("Open the quick-assign palette"))
                ShortcutRow(keys: ["⌃", "⌥", "1–9"], title: L("Assign the focused window to the matching frame"))
                ShortcutRow(keys: ["⌃", "⌥", "R"], title: L("Hide the dashboard and reveal the workspace"))
                ShortcutRow(keys: ["⌘", "↩"], title: L("Apply the layout while Jailor is active"))
                ShortcutRow(keys: ["⌘", "⇧", "R"], title: L("Hide the dashboard and reveal the workspace (when Jailor is active)"))
                ShortcutRow(keys: ["⌘", "0"], title: L("Open the Jailor dashboard"))
            } header: {
                Text(L("Shortcuts"))
            } footer: {
                Text(L("Global ⌃ ⌥ shortcuts work even when Jailor is hidden. Local ⌘ shortcuts require Jailor to be active."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(store.tags) { tag in
                    TagEditorRow(tag: tag)
                }

                Button {
                    store.addTag()
                } label: {
                    Label(L("Add label"), systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            } header: {
                Text(L("Labels"))
            } footer: {
                Text(L("Labels classify windows. A frame can have a preferred label; dragging a window into that frame applies the label automatically."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 10) {
                    Circle()
                        .fill(store.isTrusted ? Theme.success : Theme.warning)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.isTrusted ? L("Accessibility granted") : L("Accessibility not granted"))
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(L("Jailor needs this permission to read window titles and move windows from other apps."))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(L("Open System Settings")) {
                        store.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(L("Check again")) {
                        store.refreshTrust()
                        store.refreshWindows()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } header: {
                Text(L("Permissions"))
            }

            Section {
                HStack(spacing: 11) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jailor \(appVersion)")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L("Workspace for macOS with frames, labels, and shortcuts."))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            } header: {
                Text(L("About"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 660, height: 620)
    }
}

private struct ShortcutRow: View {
    let keys: [String]
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(keys, id: \.self) { key in
                    KeyCap(text: key)
                }
            }
            .frame(minWidth: 102, alignment: .leading)

            Text(title)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private struct TagEditorRow: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var l10n = Localization.shared
    let tag: Tag

    @State private var showDelete = false

    private var current: Tag? {
        store.tags.first(where: { $0.id == tag.id })
    }

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color(hex: current?.colorHex ?? tag.colorHex))
                .frame(width: 8, height: 8)

            ZStack(alignment: .leading) {
                if (current?.name ?? tag.name).isEmpty {
                    Text(L("Label name"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }

                TextField(
                    "",
                    text: Binding(
                        get: { current?.name ?? tag.name },
                        set: { store.updateTagName(tag.id, name: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(.system(size: 11.5, weight: .medium))
            }
            .frame(width: 170, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Theme.tagPalette, id: \.self) { hex in
                    Button {
                        store.updateTagColor(tag.id, colorHex: hex)
                    } label: {
                        ZStack {
                            if current?.colorHex == hex {
                                Circle()
                                    .stroke(Color.primary.opacity(0.55), lineWidth: 1.4)
                                    .frame(width: 17, height: 17)
                            }
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 12, height: 12)
                        }
                        .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                }
            }

            Spacer(minLength: 0)

            Button {
                showDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.danger.opacity(0.8))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(L("Delete label"))
        }
        .frame(height: 30)
        .confirmationDialog(
            L("Delete label \"%@\"?", current?.name ?? tag.name),
            isPresented: $showDelete,
            titleVisibility: .visible
        ) {
            Button(L("Delete label"), role: .destructive) {
                store.deleteTag(tag.id)
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Windows using this label will become unlabeled."))
        }
    }
}
