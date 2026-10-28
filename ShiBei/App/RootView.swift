import SwiftUI
import SwiftData

@Observable
final class AppState {
    var selectedTab: AppTab = .library
    var presentCapture = false
    var pendingLink: String?
    var searchText = ""
    var galleryMode = false
    var selectedPlatform: Platform?
    var selectedTag: String?
    var toast: ToastMessage?
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var style: Style = .success

    enum Style { case success, failure, info }
}

enum AppTab: Hashable {
    case library, cache, settings
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {
            LibraryView()
                .tabItem { Label("收藏", systemImage: "square.grid.2x2") }
                .tag(AppTab.library)

            CacheView()
                .tabItem { Label("缓存", systemImage: "arrow.down.circle") }
                .tag(AppTab.cache)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .sheet(isPresented: $state.presentCapture) {
            CaptureView(prefill: state.pendingLink)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let toast = state.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: state.toast)
        .onChange(of: state.toast) { _, newToast in
            guard let newToast else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.6))
                if appState.toast?.id == newToast.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.toast = nil
                    }
                }
            }
        }
    }
}

private struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
            Text(toast.text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, 24)
    }

    private var iconName: String {
        switch toast.style {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}
