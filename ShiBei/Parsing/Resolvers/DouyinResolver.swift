import Foundation

/// 抖音。
///
/// 2026 年起分享页已改为纯客户端渲染，HTML 里不再包含 `item_list`，
/// 因此解析分三层：
/// 1. 原页面 SSR（历史缓存 / 部分路径仍可能带 `_ROUTER_DATA`）
/// 2. `iesdouyin.com/share/{video,note,slides}/{id}` 的 SSR
/// 3. 离屏 WKWebView 运行页面，截获页面自己发出的、带签名的详情接口 JSON
struct DouyinResolver: ContentResolver {
    let platform: Platform = .douyin

    func canResolve(_ url: URL) -> Bool {
        Platform.detect(from: url) == .douyin
    }

    func resolve(_ url: URL, http: HTTPClient) async throws -> ParsedContent {
        var notes: [String] = []
        let headers = ["User-Agent": UserAgent.iphone]

        let result = try await http.follow(url, headers: headers, referer: "https://www.douyin.com/")
        let finalURL = result.finalURL
        notes.append("final: \(finalURL.absoluteString)")

        guard let awemeID = awemeID(from: finalURL) ?? awemeID(from: url) else {
            throw ParseError.unsupportedLink
        }
        notes.append("awemeId: \(awemeID)")

        let html = HTMLTools.decode(data: result.body)

        // 1. 原页面 SSR
        if let router = EmbeddedJSON.object(after: "window._ROUTER_DATA", in: html),
           let item = findItem(in: router) {
            notes.append("source: ssr(original)")
            return try content(from: item, sourceURL: finalURL, notes: notes)
        }

        // 2. iesdouyin 分享页 SSR（视频 / 图文 / 图集）
        for kind in ["video", "note", "slides"] {
            guard let share = URL(string: "https://www.iesdouyin.com/share/\(kind)/\(awemeID)/") else { continue }
            guard let page = try? await http.string(
                share,
                headers: headers,
                referer: "https://www.iesdouyin.com/"
            ) else { continue }

            if let router = EmbeddedJSON.object(after: "window._ROUTER_DATA", in: page),
               let item = findItem(in: router) {
                notes.append("source: ssr(\(kind))")
                return try content(from: item, sourceURL: share, notes: notes)
            }
        }

        // 3. 离屏浏览器截获签名接口
        guard let shareURL = URL(string: "https://www.iesdouyin.com/share/video/\(awemeID)/") else {
            throw ParseError.unsupportedLink
        }

        // 用桌面 UA：移动端 UA 更容易只渲染「打开抖音 App」的引导页而不请求详情接口
        let capture = try await WebExtractor.shared.capture(
            url: shareURL,
            userAgent: UserAgent.desktop,
            timeout: 24,
            shouldFinish: { bodies in
                bodies.contains { $0.contains("\"aweme_id\"") || $0.contains("\"play_addr\"") }
            }
        )
        notes.append("source: webview(\(capture.responses.count) responses)")

        if let item = awemeItem(in: capture.responses) {
            notes.append("webview: 命中 aweme 详情")
            return try content(from: item, sourceURL: finalURL, notes: notes)
        }

        // 4. 兜底：页面里直接给出的 mp4 / 图片（非 blob）
        var media: [ParsedMedia] = []
        if let mp4 = capture.videoSources.first(where: { $0.hasPrefix("http") && $0.contains(".mp4") }),
           let videoURL = URL(string: mp4) {
            media.append(ParsedMedia(kind: .video, videoURL: videoURL))
        }
        if media.isEmpty {
            let images = capture.imageSources.filter { $0.hasPrefix("http") && !$0.contains("avatar") }
            media = images.prefix(60).compactMap { URL(string: $0) }.map {
                ParsedMedia(kind: .image, imageURL: $0, posterURL: $0)
            }
        }

        guard !media.isEmpty else {
            throw ParseError.blocked("分享页已改为纯前端渲染，且没有截获到媒体数据。请确认链接在浏览器中可正常播放")
        }

        notes.append("webview: 媒体兜底 \(media.count) 项")
        let fallbackText = String(capture.text.prefix(4000))
        return ParsedContent(
            platform: .douyin,
            sourceURL: finalURL,
            title: String(capture.title.prefix(120)),
            text: fallbackText,
            authorName: "",
            media: media,
            diagnostics: notes
        )
    }

    // MARK: - 构建

    private func content(
        from item: [String: Any],
        sourceURL: URL,
        notes: [String]
    ) throws -> ParsedContent {
        let desc = item.string("desc") ?? ""
        let author = item.dict("author")
        let authorName = author?.string("nickname") ?? ""
        let avatar = ParseSupport.lastURL(in: author?.dig("avatar_thumb", "url_list"))
        let published = ParseSupport.dateFromUnix(item.int("create_time"))

        var media: [ParsedMedia] = []
        let images = item.array("images") as? [[String: Any]] ?? []

        for image in images {
            guard let imageURL = ParseSupport.lastURL(in: image["url_list"]) else { continue }
            if let video = image.dict("video"),
               let rawVideo = ParseSupport.lastURL(in: video.dig("play_addr", "url_list")) {
                media.append(ParsedMedia(
                    kind: .livePhoto,
                    imageURL: imageURL,
                    videoURL: cleanVideoURL(rawVideo),
                    posterURL: imageURL,
                    width: image.int("width"),
                    height: image.int("height")
                ))
            } else {
                media.append(ParsedMedia(
                    kind: .image,
                    imageURL: imageURL,
                    posterURL: imageURL,
                    width: image.int("width"),
                    height: image.int("height")
                ))
            }
        }

        if let video = item.dict("video"), let raw = bestVideoURL(video) {
            let poster = ParseSupport.lastURL(in: video.dig("cover", "url_list"))
                ?? ParseSupport.lastURL(in: video.dig("origin_cover", "url_list"))
                ?? media.first?.imageURL
            let duration = (video.int("duration") ?? 0) > 0 ? Double(video.int("duration")!) / 1000 : nil
            media.insert(ParsedMedia(
                kind: .video,
                imageURL: poster,
                videoURL: cleanVideoURL(raw),
                posterURL: poster,
                width: video.int("width"),
                height: video.int("height"),
                duration: duration
            ), at: 0)
        }

        guard !media.isEmpty else { throw ParseError.noMedia }

        let title = desc.split(separator: "\n").first.map(String.init) ?? ""
        return ParsedContent(
            platform: .douyin,
            sourceURL: sourceURL,
            title: String(title.prefix(120)),
            text: desc,
            authorName: authorName,
            authorAvatarURL: avatar,
            publishedAt: published,
            media: media,
            diagnostics: notes
        )
    }

    // MARK: - 定位数据

    private func awemeID(from url: URL) -> String? {
        ParseSupport.firstMatch("/(?:video|note|slides)/(\\d{6,})", in: url.absoluteString)
            ?? ParseSupport.firstMatch("[?&]modal_id=(\\d{6,})", in: url.absoluteString)
            ?? ParseSupport.firstMatch("[?&]aweme_id=(\\d{6,})", in: url.absoluteString)
    }

    private func findItem(in router: [String: Any]) -> [String: Any]? {
        if let loader = router.dict("loaderData") {
            for value in loader.values {
                if let list = value.digDict("videoInfoRes")?["item_list"] as? [[String: Any]],
                   let first = list.first {
                    return first
                }
                if let list = value.digDict("noteInfoRes")?["item_list"] as? [[String: Any]],
                   let first = list.first {
                    return first
                }
            }
        }
        return ParseSupport.find(in: router) {
            $0["aweme_id"] != nil && ($0["video"] != nil || $0["images"] != nil)
        }
    }

    private func awemeItem(in bodies: [String]) -> [String: Any]? {
        for body in bodies {
            guard let json = EmbeddedJSON.parse(body) as? [String: Any] else { continue }
            if let item = ParseSupport.find(in: json, where: {
                $0["aweme_id"] != nil && ($0["video"] != nil || $0["images"] != nil)
            }) {
                return item
            }
            if let detail = json.dict("aweme_detail"), detail["video"] != nil || detail["images"] != nil {
                return detail
            }
            if let list = json.digArray("data", "aweme_list") as? [[String: Any]], let first = list.first {
                return first
            }
        }
        return nil
    }

    private func bestVideoURL(_ video: [String: Any]) -> URL? {
        if let bitRate = video.array("bit_rate") as? [[String: Any]], !bitRate.isEmpty {
            let sorted = bitRate.sorted {
                ($0.int("bit_rate") ?? 0) > ($1.int("bit_rate") ?? 0)
            }
            for candidate in sorted {
                if let url = ParseSupport.lastURL(in: candidate.dig("play_addr", "url_list")) {
                    return url
                }
            }
        }
        return ParseSupport.lastURL(in: video.dig("play_addr", "url_list"))
    }

    /// 去水印：把 playwm 换回 play
    private func cleanVideoURL(_ url: URL) -> URL {
        let cleaned = url.absoluteString
            .replacingOccurrences(of: "/playwm/", with: "/play/")
            .replacingOccurrences(of: "&watermark=1", with: "")
        return URL(string: cleaned) ?? url
    }
}
