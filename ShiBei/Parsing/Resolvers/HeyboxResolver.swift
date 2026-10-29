import Foundation

/// 小黑盒：分享页是纯前端渲染，HTML 只有 SPA 外壳。
/// 策略：HTTP 直取（旧版/JSON）→ 离屏 WKWebView 渲染 → 从截获的接口 JSON 或 DOM 取内容。
struct HeyboxResolver: ContentResolver {
    let platform: Platform = .heybox

    func canResolve(_ url: URL) -> Bool {
        Platform.detect(from: url) == .heybox
    }

    func resolve(_ url: URL, http: HTTPClient) async throws -> ParsedContent {
        var notes: [String] = []
        let headers = ["User-Agent": UserAgent.iphone]
        let result = try await http.follow(url, headers: headers, referer: "https://www.xiaoheihe.cn/")
        notes.append("final: \(result.finalURL.absoluteString)")

        let body = HTMLTools.decode(data: result.body)
        var media: [ParsedMedia] = []
        var text = ""
        var title = ""
        var authorName = ""
        var avatar: URL?

        // 分享接口偶尔直接返回 JSON
        if let json = EmbeddedJSON.parse(body) as? [String: Any] {
            notes.append("body: json")
            var collected: (images: [URL], videos: [URL]) = ([], [])
            ParseSupport.collectMedia(in: json, into: &collected)
            media = collected.images.map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
            media += collected.videos.map { ParsedMedia(kind: .video, videoURL: $0) }
            title = ParseSupport.find(in: json) { $0["title"] != nil }?.string("title") ?? ""
            text = ParseSupport.find(in: json) { $0["content"] != nil || $0["description"] != nil }
                .map { HTMLTools.plainText(from: $0.string("content") ?? $0.string("description") ?? "") } ?? ""
        }

        // HTML 内嵌状态
        if media.isEmpty {
            let markers = ["window.__INITIAL_STATE__", "window.__NUXT__", "__NEXT_DATA__", "window.__DATA__"]
            for marker in markers {
                guard let state = EmbeddedJSON.object(after: marker, in: body) else { continue }
                notes.append("embedded: \(marker)")
                var collected: (images: [URL], videos: [URL]) = ([], [])
                ParseSupport.collectMedia(in: state, into: &collected)
                media = collected.images.map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
                media += collected.videos.map { ParsedMedia(kind: .video, videoURL: $0) }
                break
            }
        }

        let meta = HTMLTools.meta(in: body)
        if title.isEmpty {
            title = meta["og:title"] ?? HTMLTools.title(in: body) ?? ""
        }
        if text.isEmpty {
            text = meta["og:description"] ?? meta["description"] ?? ""
            text = HTMLTools.plainText(from: text)
        }
        if media.isEmpty {
            let images = [meta["og:image"], meta["twitter:image"]].compactMap { ParseSupport.httpsURL($0) }
            media = images.map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
            if let video = ParseSupport.httpsURL(meta["og:video"] ?? meta["og:video:url"]) {
                media.insert(ParsedMedia(kind: .video, videoURL: video), at: 0)
            }
        }

        if media.isEmpty {
            let images = HTMLTools.imageURLs(in: body).filter { !Self.looksLikeChrome($0) }
            media = images.map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
        }

        // 纯前端渲染的分享页：让页面自己跑一遍，再取数据
        if media.isEmpty && text.isEmpty {
            notes.append("fallback: webview")
            if let capture = try? await WebExtractor.shared.capture(
                url: url,
                userAgent: UserAgent.iphone,
                timeout: 20,
                shouldFinish: { responses in
                    responses.contains { $0.contains("\"imgs\"") || $0.contains("\"link\"") }
                }
            ) {
                notes.append("webview: \(capture.finalURL.absoluteString)")

                for raw in capture.responses {
                    guard let data = raw.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data),
                          let link = Self.findLink(in: json) else { continue }
                    let parsed = Self.parse(link: link)
                    title = parsed.title
                    text = parsed.text
                    media = parsed.media.filter { entry in
                        guard let imageURL = entry.imageURL else { return true }
                        return !Self.looksLikeChrome(imageURL)
                    }
                    authorName = parsed.author
                    avatar = parsed.avatar
                    if !media.isEmpty || !text.isEmpty {
                        notes.append("api: link")
                        break
                    }
                }

                if media.isEmpty {
                    var seen = Set<String>()
                    let urls = capture.imageSources
                        .filter { $0.contains("/bbs/") && !$0.lowercased().contains("/avatar/") }
                        .filter { seen.insert($0).inserted }
                    media = urls.prefix(9).compactMap { raw -> ParsedMedia? in
                        let base = raw.split(separator: "?").first.map(String.init) ?? raw
                        guard let imageURL = URL(string: base) else { return nil }
                        return ParsedMedia(kind: .image, imageURL: imageURL, posterURL: imageURL)
                    }
                    if !media.isEmpty {
                        notes.append("dom: images \(media.count)")
                    }
                }

                if title.isEmpty {
                    title = capture.title
                }
                if text.isEmpty {
                    text = Self.cleanBodyText(capture.text, title: title)
                }
            }
        }

        guard !media.isEmpty || !text.isEmpty else {
            throw ParseError.noMedia
        }

        notes.append("media: \(media.count)")
        return ParsedContent(
            platform: .heybox,
            sourceURL: result.finalURL,
            title: title,
            text: text,
            authorName: authorName,
            authorAvatarURL: avatar,
            publishedAt: nil,
            media: media,
            diagnostics: notes
        )
    }

    // MARK: - WebView JSON

    private static func findLink(in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if let link = dict["link"] as? [String: Any],
               link["title"] != nil || link["text"] != nil || link["imgs"] != nil {
                return link
            }
            for child in dict.values {
                if let found = findLink(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findLink(in: child) { return found }
            }
        }
        return nil
    }

    private static func parse(link: [String: Any]) -> (title: String, text: String, media: [ParsedMedia], author: String, avatar: URL?) {
        var media: [ParsedMedia] = []
        var collected: (images: [URL], videos: [URL]) = ([], [])
        ParseSupport.collectMedia(in: link, into: &collected)
        media = collected.images.map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
        media += collected.videos.map { ParsedMedia(kind: .video, videoURL: $0) }

        let title = link.string("title")
        let rawText = link.string("text")
            ?? link.string("content")
            ?? link.string("description")
            ?? ""
        let text = HTMLTools.plainText(from: rawText)

        var author = ""
        var avatar: URL?
        if let user = link["user"] as? [String: Any] {
            author = user.string("username") ?? user.string("name") ?? ""
            avatar = ParseSupport.httpsURL(user.string("avatar") ?? user.string("avatar_url") ?? "")
        }
        return (title, text, media, author, avatar)
    }

    /// 去掉页面导航、「打开 App」等外壳，只留正文
    private static func cleanBodyText(_ raw: String, title: String) -> String {
        var value = raw
        let cutMarkers = ["全部评论", "相关推荐", "打开APP", "打开 App", "下载小黑盒", "热门推荐"]
        for marker in cutMarkers {
            if let range = value.range(of: marker) {
                value = String(value[..<range.lowerBound])
            }
        }
        if !title.isEmpty, let range = value.range(of: title) {
            value = String(value[range.upperBound...])
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(8000))
    }

    static func looksLikeChrome(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return lower.contains("logo") || lower.contains("avatar") || lower.contains("icon")
            || lower.contains("emoji") || lower.contains("badge")
    }
}
