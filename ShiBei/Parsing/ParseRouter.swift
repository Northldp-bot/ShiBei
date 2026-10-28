import Foundation

/// 解析总入口：识别链接 → 选择平台解析器 → 失败时降级到 OpenGraph。
final class ParseRouter: Sendable {
    static let shared = ParseRouter()

    private let resolvers: [ContentResolver]

    init(resolvers: [ContentResolver]? = nil) {
        self.resolvers = resolvers ?? [
            XiaohongshuResolver(),
            DouyinResolver(),
            BilibiliResolver(),
            ZhihuResolver(),
            WeiboResolver(),
            HeyboxResolver()
        ]
    }

    func resolve(text: String) async throws -> ParsedContent {
        guard let url = LinkExtractor.bestLink(in: text) else {
            throw ParseError.unsupportedLink
        }
        return try await resolve(url: url)
    }

    func resolve(url: URL) async throws -> ParsedContent {
        let http = HTTPClient.shared
        let platform = Platform.detect(from: url)

        if let resolver = resolvers.first(where: { $0.canResolve(url) }) {
            do {
                return try await resolver.resolve(url, http: http)
            } catch {
                // 小红书的安全拦截页只有真实浏览器执行 JS 后才能拿到笔记数据
                if platform == .xiaohongshu,
                   let rescued = try? await rescueXiaohongshu(url: url) {
                    return rescued
                }

                // 平台解析失败时，用通用解析器再试一次，保留原始错误信息
                if let fallback = try? await GenericResolver().resolve(url, http: http) {
                    var result = fallback
                    result.diagnostics.append("平台解析失败：\(error.localizedDescription)")
                    result.diagnostics.append("已降级为 OpenGraph 解析")
                    return result
                }
                throw error
            }
        }
        return try await GenericResolver().resolve(url, http: http)
    }

    /// 用离屏 WKWebView 打开笔记页，读取 JS 执行后的 window.__INITIAL_STATE__
    private func rescueXiaohongshu(url: URL) async throws -> ParsedContent {
        let capture = try await WebExtractor.shared.capture(
            url: url,
            userAgent: UserAgent.iphone,
            timeout: 18
        )
        guard let raw = capture.initialState,
              let state = EmbeddedJSON.parse(raw) as? [String: Any] else {
            throw ParseError.blocked("浏览器渲染后仍未拿到笔记数据")
        }

        let pattern = "/(?:explore|discovery/item|note)/([0-9a-fA-F]{24})"
        let noteID = ParseSupport.firstMatch(pattern, in: capture.finalURL.absoluteString)
            ?? ParseSupport.firstMatch(pattern, in: url.absoluteString)

        return try XiaohongshuResolver().content(
            from: state,
            noteID: noteID,
            sourceURL: capture.finalURL,
            notes: ["source: webview rescue"]
        )
    }
}
