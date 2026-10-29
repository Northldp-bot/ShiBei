import SwiftUI
import SwiftData

@main
struct ShiBeiApp: App {
    @State private var appState = AppState()
    @AppStorage("themeMode") private var themeMode = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(CacheManager.shared)
                .tint(Theme.ink)
                .preferredColorScheme(colorScheme)
                .modelContainer(ShiBeiContainer.shared.container)
                .onOpenURL { url in
                    guard url.scheme == "shibei" else { return }
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    if let raw = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                       let target = URL(string: raw) {
                        appState.pendingLink = target.absoluteString
                        appState.presentCapture = true
                    }
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
