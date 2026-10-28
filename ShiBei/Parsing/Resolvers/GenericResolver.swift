import Foundation

/// 通用兜底：OpenGraph / JSON-LD / 页面图片。用于未知站点或平台改版时的降级。
struct GenericResolver: ContentResolver {
    let platform: Platform = .web

    func canResolve(_ url: URL) -> Bool { true }

    func resolve(_ url: URL, http: HTTPClient) async throws -> ParsedContent {
        var notes: [String] = []
        let (html, finalURL) = try await http.decoded(url, headers: ["User-Agent": UserAgent.desktop])
        notes.append("final: \(finalURL.absoluteString)")

        let meta = HTMLTools.meta(in: html)
        let ld = HTMLTools.jsonLD(in: html)

        var title = meta["og:title"] ?? meta["twitter:title"] ?? HTMLTools.title(in: html) ?? ""
        var description = meta["og:description"] ?? meta["description"] ?? ""
        var media: [ParsedMedia] = []

        // JSON-LD 补全
        if let ld {
            if title.isEmpty { title = (ld.string("headline") ?? ld.string("name") ?? "") }
            if description.isEmpty { description = ld.string("description") ?? "" }
        }

        // 图片
        var imageURLs: [URL] = []
        for key in ["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"] {
            if let url = ParseSupport.httpsURL(meta[key]), !imageURLs.contains(url) {
                imageURLs.append(url)
            }
        }
        if let ld, let image = ld["image"] {
            if let single = image as? String, let url = ParseSupport.httpsURL(single) {
                imageURLs.append(url)
            } else if let list = image as? [String] {
                imageURLs.append(contentsOf: list.compactMap { ParseSupport.httpsURL($0) })
            } else if let dict = image as? [String: Any], let url = ParseSupport.httpsURL(dict.string("url")) {
                imageURLs.append(url)
            }
        }

        // 视频
        var videoURL: URL?
        for key in ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"] {
            if let url = ParseSupport.httpsURL(meta[key]) {
                videoURL = url
                break
            }
        }
        if videoURL == nil,
           let src = ParseSupport.firstMatch("<video[^>]+src=[\"']([^\"']+)[\"']", in: html) {
            videoURL = ParseSupport.httpsURL(src)
        }

        // 正文图片兜底（过滤明显的站点装饰图）
        if imageURLs.isEmpty {
            imageURLs = HTMLTools.imageURLs(in: html).filter { url in
                let lower = url.absoluteString.lowercased()
                return !(lower.contains("logo") || lower.contains("icon") || lower.contains("avatar") || lower.contains("sprite"))
            }
        }

        let uniqueImages = Array(NSOrderedSet(array: imageURLs)) as? [URL] ?? imageURLs
        media = uniqueImages.prefix(60).map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
        if let videoURL {
            media.insert(ParsedMedia(kind: .video, videoURL: videoURL, posterURL: uniqueImages.first), at: 0)
        }

        if description.isEmpty {
            let bodyText = HTMLTools.plainText(from: html)
            description = String(bodyText.prefix(4000))
        }

        guard !media.isEmpty || !description.isEmpty || !title.isEmpty else {
            throw ParseError.noMedia
        }

        notes.append("og: \(meta.keys.count), jsonld: \(ld != nil)")
        return ParsedContent(
            platform: Platform.detect(from: finalURL) ?? .web,
            sourceURL: finalURL,
            title: title,
            text: description,
            authorName: meta["author"] ?? "",
            authorAvatarURL: nil,
            publishedAt: nil,
            media: media,
            diagnostics: notes
        )
    }
}
