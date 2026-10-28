import Foundation

/// 微博：m.weibo.cn/statuses/show 接口，支持图文、视频、转发。
struct WeiboResolver: ContentResolver {
    let platform: Platform = .weibo

    func canResolve(_ url: URL) -> Bool {
        Platform.detect(from: url) == .weibo
    }

    func resolve(_ url: URL, http: HTTPClient) async throws -> ParsedContent {
        var notes: [String] = []
        guard let mid = Self.mid(from: url) else {
            throw ParseError.unsupportedLink
        }
        notes.append("mid: \(mid)")
        notes.append("raw: \(url.absoluteString)")

        // 先取一次首页，拿到 _T_WM 等 cookie
        if let home = URL(string: "https://m.weibo.cn/") {
            await http.warmUp(home, headers: ["User-Agent": UserAgent.iphone])
        }

        let api = URL(string: "https://m.weibo.cn/statuses/show?id=\(mid)")!
        var headers = [
            "User-Agent": UserAgent.iphone,
            "X-Requested-With": "XMLHttpRequest",
            "MWeibo-Pwa": "1",
            "Accept": "application/json, text/plain, */*"
        ]
        if let cookie = PlatformCookie.header(for: .weibo) {
            headers["Cookie"] = cookie
        }
        let json = try await http.json(api, headers: headers, referer: "https://m.weibo.cn/")
        let root = json as? [String: Any]
        guard let root, let data = root.dict("data") else {
            let message = root?["msg"] as? String ?? "unknown"
            throw ParseError.blocked("微博接口未返回数据（\(message)）")
        }

        let user = data.dict("user")
        let rawText = data.string("text") ?? ""
        var text = HTMLTools.plainText(from: rawText)
        var media: [ParsedMedia] = []

        // 图片
        let pics = data.array("pics") as? [[String: Any]] ?? []
        for pic in pics {
            let url = ParseSupport.httpsURL(pic.digString("large", "url") ?? pic.string("url"))
            if let url {
                media.append(ParsedMedia(kind: .image, imageURL: url, posterURL: url,
                                         width: pic.int("width"), height: pic.int("height")))
            }
        }

        // 实况图（pic_infos[pid].video 存在时）
        let picInfos = data.dict("pic_infos") ?? [:]
        for (_, value) in picInfos {
            guard let info = value as? [String: Any] else { continue }
            guard let video = info.dict("video"),
                  let videoURL = ParseSupport.httpsURL(
                    video.digString("url") ?? video.digString("mp4", "url")
                  ) else { continue }
            let imageURL = ParseSupport.httpsURL(info.digString("large", "url") ?? info.string("url"))
            if let imageURL {
                media.append(ParsedMedia(kind: .livePhoto, imageURL: imageURL, videoURL: videoURL, posterURL: imageURL))
            }
        }

        // 视频
        if let pageInfo = data.dict("page_info"), let mediaInfo = pageInfo.dict("media_info") {
            let keys = ["mp4_720p_mp4", "mp4_hd_url", "mp4_sd_url"]
            for key in keys {
                if let raw = mediaInfo.string(key), let videoURL = ParseSupport.httpsURL(raw) {
                    let poster = ParseSupport.httpsURL(
                        mediaInfo.string("big_pic_info") ?? pageInfo.string("page_pic")
                    )
                    media.append(ParsedMedia(kind: .video, videoURL: videoURL, posterURL: poster,
                                             duration: mediaInfo.double("duration")))
                    break
                }
            }
        }

        // 转发内容合并
        if let retweeted = data.dict("retweeted_status") {
            let originalName = retweeted.digString("user", "screen_name") ?? ""
            let originalText = HTMLTools.plainText(from: retweeted.string("text") ?? "")
            if !originalText.isEmpty {
                text += "\n\n转发自 @\(originalName)：\n" + originalText
            }
            let retweetPics = retweeted.array("pics") as? [[String: Any]] ?? []
            for pic in retweetPics {
                if let url = ParseSupport.httpsURL(pic.digString("large", "url") ?? pic.string("url")) {
                    media.append(ParsedMedia(kind: .image, imageURL: url, posterURL: url))
                }
            }
        }

        guard !media.isEmpty || !text.isEmpty else { throw ParseError.noMedia }

        let title = text.split(separator: "\n").first.map(String.init) ?? ""
        notes.append("pics: \(pics.count), live: \(media.filter { $0.kind == .livePhoto }.count)")

        return ParsedContent(
            platform: .weibo,
            sourceURL: url,
            title: String(title.prefix(120)),
            text: text,
            authorName: user?.string("screen_name") ?? "",
            authorAvatarURL: ParseSupport.httpsURL(user?.string("profile_image_url")),
            publishedAt: Self.date(from: data.string("created_at")),
            media: media,
            diagnostics: notes
        )
    }

    // MARK: - Helpers

    static func mid(from url: URL) -> String? {
        let text = url.absoluteString
        if let mid = ParseSupport.firstMatch("/(?:detail|status)/(\\d{10,})", in: text) {
            return mid
        }
        if let mid = ParseSupport.firstMatch("[?&](?:mid|id)=(\\d{10,})", in: text) {
            return mid
        }
        if let bid = ParseSupport.firstMatch("weibo\\.(?:com|cn)/\\d+/([0-9A-Za-z]{6,12})", in: text) {
            return decodeBase62(bid)
        }
        return nil
    }

    /// 微博短链 base62 → 数字 mid
    static func decodeBase62(_ value: String) -> String? {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var number: UInt64 = 0
        for character in value {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            number = number * 62 + UInt64(index)
        }
        return String(number)
    }

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return formatter.date(from: value)
    }
}
