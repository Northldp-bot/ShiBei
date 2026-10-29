import SwiftUI
import SwiftData

@Observable
final class AppState {
    var selectedTab: AppTab = .library
    var presentCapture = false
    var pendingLink: String?
    var searchText = ""
    var galleryMode = false
    var filter = FilterState()
    var sortOrder: SortOrder = .saved
    var toast: ToastMessage?
    var hideTabBar = false

    init() {
        if let raw = UserDefaults.standard.string(forKey: "defaultSort"),
           let order = SortOrder(rawValue: raw) {
            sortOrder = order
        }
        if let raw = UserDefaults.standard.string(forKey: "defaultDimension"),
           let dimension = FilterDimension(rawValue: raw) {
            filter.dimension = dimension
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var style: Style = .success

    enum Style: Equatable { case success, failure, info }
}

enum AppTab: Hashable {
    case library, settings
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        ZStack(alignment: .bottom) {
            Group {
                switch state.selectedTab {
                case .library:
                    LibraryView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !state.hideTabBar {
                BottomBar(selection: $state.selectedTab) {
                    state.presentCapture = true
                }
            }
        }
        .background(Theme.canvas)
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

/// 底部导航：收藏 / ＋ / 设置
private struct BottomBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.library, title: "收藏", icon: "square.grid.2x2")
            addButton
            tabButton(.settings, title: "设置", icon: "gearshape")
        }
        .padding(6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.6), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        )
        .padding(.horizontal, 44)
        .padding(.bottom, 6)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.onInk)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.ink))
                .overlay(Circle().stroke(Theme.canvas, lineWidth: 4))
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .offset(y: -14)
    }

    private func tabButton(_ tab: AppTab, title: String, icon: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selection == tab ? Theme.onInk : Theme.inkSecondary)
            .frame(width: 96, height: 46)
            .background(
                Capsule(style: .continuous)
                    .fill(selection == tab ? Theme.ink : Color.clear)
            )
        }
        .buttonStyle(.plain)
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
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.86)))
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
