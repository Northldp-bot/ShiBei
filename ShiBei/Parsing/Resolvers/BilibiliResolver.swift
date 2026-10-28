import Foundation

/// B 站：b23.tv → BV 号 → view API + playurl API。
/// 视频通常是 DASH（音视频分离），下载后由 CacheManager 合并。
struct BilibiliResolver: ContentResolver {
    let platform: Platform = .bilibili

    func canResolve(_ url: URL) -> Bool {
        Platform.detect(from: url) == .bilibili
    }

    func resolve(_ url: URL, http: HTTPClient) async throws -> ParsedContent {
        var headers = ["User-Agent": UserAgent.desktop]
        if let cookie = PlatformCookie.header(for: .bilibili) {
            headers["Cookie"] = cookie
        }
        let result = try await http.follow(url, headers: headers, referer: "https://www.bilibili.com/")
        let finalURL = result.finalURL
        var notes = ["final: \(finalURL.absoluteString)"]

        if finalURL.absoluteString.contains("/read/cv") {
            return try await resolveArticle(finalURL, body: result.body, http: http, notes: notes)
        }
        if finalURL.absoluteString.contains("/opus/") {
            return try await resolveOpus(finalURL, body: result.body, http: http, notes: notes)
        }

        guard let bv = ParseSupport.firstMatch("(BV[0-9A-Za-z]{10})", in: finalURL.absoluteString) else {
            throw ParseError.unsupportedLink
        }
        notes.append("bvid: \(bv)")

        let viewURL = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bv)")!
        let viewJSON = try await http.json(viewURL, headers: headers, referer: "https://www.bilibili.com/")
        guard let root = viewJSON as? [String: Any],
              root.int("code") == 0,
              let data = root.dict("data") else {
            throw ParseError.upstream("view API: \((viewJSON as? [String: Any])?.string("message") ?? "unknown")")
        }

        var title = data.string("title") ?? ""
        let desc = data.string("desc") ?? ""
        let owner = data.dict("owner")
        let pages = data.array("pages") as? [[String: Any]] ?? []

        var pageIndex = 0
        if let components = URLComponents(url: finalURL, resolvingAgainstBaseURL: false),
           let rawP = components.queryItems?.first(where: { $0.name == "p" })?.value,
           let p = Int(rawP), p > 0, p <= max(pages.count, 1) {
            pageIndex = p - 1
        }
        let pageInfo = pages.indices.contains(pageIndex) ? pages[pageIndex] : pages.first
        let cid = pageInfo?.int("cid") ?? data.int("cid") ?? 0
        if pages.count > 1, let part = pageInfo?.string("part"), !part.isEmpty {
            title = "\(title) · P\(pageIndex + 1) \(part)"
        }

        let playURL = URL(string: "https://api.bilibili.com/x/player/playurl?bvid=\(bv)&cid=\(cid)&qn=\(preferredQuality)&fnval=4048&fourk=1")!
        let playJSON = try await http.json(playURL, headers: headers, referer: "https://www.bilibili.com/")
        guard let playRoot = playJSON as? [String: Any], playRoot.int("code") == 0,
              let playData = playRoot.dict("data") else {
            throw ParseError.upstream("playurl API 拒绝，可能需要登录 cookie 才能取流")
        }

        let poster = ParseSupport.httpsURL(data.string("pic"))
        var media: [ParsedMedia] = []

        if let dash = playData.dict("dash") {
            let videoTracks = dash.array("video") as? [[String: Any]] ?? []
            let audioTracks = dash.array("audio") as? [[String: Any]] ?? []
            // 优先 AVC(H.264)，兼容性最好；其次 HEVC/AV1
            let avc = videoTracks.filter { ($0.int("codecid") ?? 7) == 7 }
            let pool = avc.isEmpty ? videoTracks : avc
            let best = pool.max { ($0.int("id") ?? 0) < ($1.int("id") ?? 0) }
            let videoURLString = best?.string("baseUrl") ?? best?.string("base_url")
            // 音轨优先取码率最高的一条，避免拿到 64k 的 HE-AAC
            let bestAudio = audioTracks.max {
                ($0.int("bandwidth") ?? $0.int("id") ?? 0) < ($1.int("bandwidth") ?? $1.int("id") ?? 0)
            }
            let audioURLString = bestAudio?.string("baseUrl") ?? bestAudio?.string("base_url")
            if let videoURLString, let videoURL = ParseSupport.httpsURL(videoURLString) {
                media.append(ParsedMedia(
                    kind: .video,
                    videoURL: videoURL,
                    audioURL: ParseSupport.httpsURL(audioURLString),
                    posterURL: poster,
                    width: best?.int("width"),
                    height: best?.int("height"),
                    duration: (pageInfo?.int("duration")).map(Double.init)
                ))
                notes.append("dash: \(best?.int("id") ?? 0), audio: \(audioURLString != nil)")
            }
        } else if let durl = playData.array("durl") as? [[String: Any]], let first = durl.first,
                  let urlString = first.string("url"), let videoURL = ParseSupport.httpsURL(urlString) {
            media.append(ParsedMedia(
                kind: .video,
                videoURL: videoURL,
                posterURL: poster,
                duration: (pageInfo?.int("duration")).map(Double.init)
            ))
            notes.append("durl: 单文件含音轨")
        }

        if media.isEmpty, let pic = poster {
            media.append(ParsedMedia(kind: .image, imageURL: pic, posterURL: pic))
        }
        guard !media.isEmpty else { throw ParseError.noMedia }

        var body = desc
        if !desc.isEmpty { body = "【简介】\n" + desc }
        notes.append("pages: \(pages.count)")

        return ParsedContent(
            platform: .bilibili,
            sourceURL: finalURL,
            title: title,
            text: body,
            authorName: owner?.string("name") ?? "",
            authorAvatarURL: ParseSupport.httpsURL(owner?.string("face")),
            publishedAt: ParseSupport.dateFromUnix(data.int("pubdate")),
            media: media,
            diagnostics: notes
        )
    }

    // MARK: - 专栏 / 图文动态

    /// 设置里的清晰度偏好：最高 / 1080P / 720P
    private var preferredQuality: Int {
        switch UserDefaults.standard.string(forKey: "downloadQuality") ?? "1080P" {
        case "最高": return 120
        case "720P": return 64
        default: return 80
        }
    }

    private func resolveArticle(
        _ url: URL,
        body: Data,
        http: HTTPClient,
        notes: [String]
    ) async throws -> ParsedContent {
        var html = HTMLTools.decode(data: body)
        if !html.contains("__INITIAL_STATE__") {
            html = try await http.string(url, headers: ["User-Agent": UserAgent.desktop], referer: "https://www.bilibili.com/")
        }
        guard let state = EmbeddedJSON.object(after: "window.__INITIAL_STATE__", in: html),
              let readInfo = state.dict("readInfo") else {
            return try await GenericResolver().resolve(url, http: http)
        }

        let title = readInfo.string("title") ?? ""
        let content = readInfo.string("content") ?? ""
        let author = readInfo.dict("author")
        let images = HTMLTools.imageURLs(in: content)
        var media = images.enumerated().map { index, image in
            ParsedMedia(kind: .image, imageURL: image, posterURL: image)
        }
        if let banner = ParseSupport.httpsURL(readInfo.string("banner_url")), media.isEmpty {
            media = [ParsedMedia(kind: .image, imageURL: banner, posterURL: banner)]
        }

        return ParsedContent(
            platform: .bilibili,
            sourceURL: url,
            title: title,
            text: HTMLTools.plainText(from: content),
            authorName: author?.string("name") ?? "",
            authorAvatarURL: ParseSupport.httpsURL(author?.string("face")),
            publishedAt: ParseSupport.dateFromUnix(readInfo.int("publish_time")),
            media: media,
            diagnostics: notes
        )
    }

    private func resolveOpus(
        _ url: URL,
        body: Data,
        http: HTTPClient,
        notes: [String]
    ) async throws -> ParsedContent {
        let html = HTMLTools.decode(data: body)
        if let state = EmbeddedJSON.object(after: "window.__INITIAL_STATE__", in: html),
           let detail = state.digDict("detail") {
            let modules = detail.dict("modules")
            let author = modules?.dict("module_author")
            let dynamic = modules?.dict("module_dynamic")
            let desc = dynamic?.digString("desc", "text") ?? ""
            let major = dynamic?.dict("major")
            let archive = major?.dict("archive")
            let draw = major?.dict("draw")
            var media: [ParsedMedia] = []
            for item in (draw?.array("items") as? [[String: Any]] ?? []) {
                if let src = ParseSupport.httpsURL(item.string("src")) {
                    media.append(ParsedMedia(kind: .image, imageURL: src, posterURL: src,
                                             width: item.int("width"), height: item.int("height")))
                }
            }
            var text = desc
            if let archiveTitle = archive?.string("title") { text = archiveTitle + "\n\n" + text }
            return ParsedContent(
                platform: .bilibili,
                sourceURL: url,
                title: (text.split(separator: "\n").first.map(String.init) ?? ""),
                text: text,
                authorName: author?.string("name") ?? "",
                authorAvatarURL: ParseSupport.httpsURL(author?.string("face")),
                publishedAt: ParseSupport.dateFromUnix(author?.int("pub_ts")),
                media: media,
                diagnostics: notes
            )
        }
        return try await GenericResolver().resolve(url, http: http)
    }
}
