import SwiftUI
import SwiftData

@main
struct ShiBeiApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(CacheManager.shared)
                .tint(Theme.ink)
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
}
