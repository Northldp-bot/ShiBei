import Foundation

/// 小黑盒：分享页结构随版本变化较大，采用「内嵌 JSON 深扫描 + OpenGraph」双层策略。
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
        var published: Date?

        // 分享接口有时直接返回 JSON
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

        // 正文图片（HTML 兜底）
        if media.isEmpty {
            let images = HTMLTools.imageURLs(in: body)
                .filter { !Self.looksLikeChrome($0) }
            media = images.map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
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
            publishedAt: published,
            media: media,
            diagnostics: notes
        )
    }

    static func looksLikeChrome(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return lower.contains("logo") || lower.contains("avatar") || lower.contains("icon")
            || lower.contains("emoji") || lower.contains("badge")
    }
}
