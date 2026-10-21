import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    let openSettings: () -> Void
    let openPalette: () -> Void
    let revealWorkspace: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(openSettings: openSettings, openPalette: openPalette)
            Divider().opacity(0.5)
            DashboardView(revealWorkspace: revealWorkspace)
        }
        .frame(minWidth: 980, minHeight: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.toast)
    }
}
