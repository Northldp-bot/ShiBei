import AppIntents
import Foundation

/// 快捷指令：把一段分享文本直接收藏进拾贝。
struct SaveLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "收藏链接到拾贝"
    static var description: IntentDescription? = IntentDescription("解析分享链接并保存到拾贝，可选择同时缓存到本地。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "分享文本或链接", description: "从任意 App 复制的内容")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content = try await ParseRouter.shared.resolve(text: text)
        let platformName = content.platform.displayName
        let mediaCount = content.media.count

        // 只入库、不下载：App 不在前台时 URLSession 会被系统挂起，
        // 后台缓存并不可靠，交给用户打开 App 时触发。
        try await MainActor.run {
            _ = try LibraryService.save(content, tags: [platformName])
        }

        return .result(dialog: "已收藏 \(platformName) 内容，共 \(mediaCount) 项媒体。打开拾贝即可缓存到本地")
    }
}

struct ShiBeiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveLinkIntent(),
            phrases: [
                "用 \(.applicationName) 收藏链接",
                "把链接存到 \(.applicationName)"
            ],
            shortTitle: "收藏链接",
            systemImageName: "square.and.arrow.down"
        )
    }
}
