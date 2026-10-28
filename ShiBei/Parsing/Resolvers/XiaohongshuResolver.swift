import Foundation

/// 小红书：短链 → __INITIAL_STATE__.note.noteDetailMap[id].note
/// 支持图文、视频、实况图（imageList[i].video）。
struct XiaohongshuResolver: ContentResolver {
    let platform: Platform = .xiaohongshu

    func canResolve(_ url: URL) -> Bool {
        Platform.detect(from: url) == .xiaohongshu
    }

    func resolve(_ url: URL, http: HTTPClient) async throws -> ParsedContent {
        var notes: [String] = []
        let headers = [
            "User-Agent": UserAgent.iphone,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ]
        let result = try await http.follow(url, headers: headers, referer: "https://www.xiaohongshu.com/")
        var finalURL = result.finalURL
        var html = HTMLTools.decode(data: result.body)
        notes.append("final: \(finalURL.absoluteString)")

        // 被安全页拦截时，页面仍带 __INITIAL_STATE__ 但没有笔记数据，需要给出准确提示
        if finalURL.absoluteString.contains("/404/sec") || finalURL.absoluteString.contains("/website-login") {
            throw ParseError.blocked("笔记不存在、已删除，或当前网络被小红书安全策略拦截")
        }

        guard let noteID = noteID(from: finalURL) ?? noteID(from: url) else {
            throw ParseError.unsupportedLink
        }
        notes.append("noteId: \(noteID)")

        if !html.contains("__INITIAL_STATE__") {
            let canonical = URL(string: "https://www.xiaohongshu.com/explore/\(noteID)")!
            html = try await http.string(canonical, headers: headers, referer: "https://www.xiaohongshu.com/")
            finalURL = canonical
            notes.append("fallback: canonical explore page")
        }

        guard let state = EmbeddedJSON.object(after: "window.__INITIAL_STATE__", in: html) else {
            throw ParseError.blocked("页面没有内嵌笔记数据，可能需要登录或触发了风控")
        }

        return try content(from: state, noteID: noteID, sourceURL: finalURL, notes: notes)
    }

    /// 从 `__INITIAL_STATE__` 构建内容。
    /// 数据可能来自 HTTP 页面，也可能来自离屏 WKWebView 的 `window.__INITIAL_STATE__`。
    func content(
        from state: [String: Any],
        noteID: String?,
        sourceURL: URL,
        notes: [String]
    ) throws -> ParsedContent {
        var notes = notes
        let note = extractNote(from: state, noteID: noteID ?? "")
        guard let note else {
            throw ParseError.upstream("noteDetailMap 中找不到笔记 \(noteID ?? "")")
        }

        let title = (note.string("title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = (note.string("desc") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var body = desc
        if !title.isEmpty {
            body = title + (desc.isEmpty ? "" : "\n\n" + desc)
        }

        let user = note.digDict("user")
        let authorName = user?.string("nickname") ?? user?.string("nickName") ?? ""
        let avatar = ParseSupport.httpsURL(user?.string("image") ?? user?.string("avatar"))

        var media: [ParsedMedia] = []
        let imageList = note.array("imageList") as? [[String: Any]] ?? []
        let isVideo = (note.string("type") == "video") || note["video"] != nil

        if isVideo, let videoURL = videoStreamURL(note) {
            let poster = imageList.first.flatMap { imageURL(from: $0) }
            media.append(ParsedMedia(
                kind: .video,
                imageURL: poster,
                videoURL: videoURL,
                posterURL: poster,
                width: imageList.first?.int("width"),
                height: imageList.first?.int("height"),
                duration: note.digDouble("video", "media", "videoDuration")
            ))
        } else {
            for (index, item) in imageList.enumerated() {
                guard let image = imageURL(from: item) else { continue }
                let liveVideo = livePhotoVideoURL(item)
                if let liveVideo {
                    media.append(ParsedMedia(
                        kind: .livePhoto,
                        imageURL: image,
                        videoURL: liveVideo,
                        posterURL: image,
                        width: item.int("width"),
                        height: item.int("height")
                    ))
                } else {
                    media.append(ParsedMedia(
                        kind: .image,
                        imageURL: image,
                        posterURL: image,
                        width: item.int("width"),
                        height: item.int("height")
                    ))
                }
                if index >= 39 { break }
            }
        }

        // 视频笔记若没拿到直链，回退到图片
        if media.isEmpty {
            for item in imageList {
                if let image = imageURL(from: item) {
                    media.append(ParsedMedia(kind: .image, imageURL: image, posterURL: image))
                }
            }
        }

        guard !media.isEmpty else { throw ParseError.noMedia }

        let published = ParseSupport.dateFromMilliseconds(note.int("time") ?? note.int("lastUpdateTime"))
        notes.append("images: \(imageList.count), live: \(media.filter { $0.kind == .livePhoto }.count)")

        return ParsedContent(
            platform: .xiaohongshu,
            sourceURL: sourceURL,
            title: title,
            text: body,
            authorName: authorName,
            authorAvatarURL: avatar,
            publishedAt: published,
            media: media,
            diagnostics: notes
        )
    }

    // MARK: - Helpers

    private func noteID(from url: URL) -> String? {
        let text = url.absoluteString
        if let id = ParseSupport.firstMatch("/(?:explore|discovery/item|note)/([0-9a-fA-F]{24})", in: text) {
            return id
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "noteId" || $0.name == "note_id" })?.value {
            return id
        }
        return nil
    }

    private func extractNote(from state: [String: Any], noteID: String) -> [String: Any]? {
        if let detail = state.digDict("note", "noteDetailMap", noteID) {
            if let note = detail.dict("note") { return note }
            return detail
        }
        if let map = state.digDict("note", "noteDetailMap"),
           let first = map.values.compactMap({ $0 as? [String: Any] }).first {
            return first.dict("note") ?? first
        }
        if let detail = state.digDict("note", "noteDetail") {
            return detail
        }
        return ParseSupport.find(in: state) { $0["imageList"] != nil || $0["video"] != nil }
    }

    private func imageURL(from item: [String: Any]) -> URL? {
        let candidates = ["urlDefault", "urlPre", "url", "traceId"]
        for key in candidates {
            if let value = item.string(key), let url = ParseSupport.httpsURL(value), key != "traceId" {
                return url
            }
        }
        // 部分版本是 infoList 数组
        if let info = ParseSupport.first(item["infoList"]) {
            return ParseSupport.httpsURL(info.string("url"))
        }
        return nil
    }

    private func livePhotoVideoURL(_ item: [String: Any]) -> URL? {
        guard item.bool("livePhoto") == true || item["video"] != nil else { return nil }
        guard let video = item.dict("video") else { return nil }
        if let stream = video.digDict("media", "stream") {
            if let url = streamURL(fromStream: stream) { return url }
        }
        if let key = video.digString("consumer", "originVideoKey") {
            return ParseSupport.httpsURL("https://sns-video-bd.xhscdn.com/\(key)")
        }
        if let url = video.string("url") { return ParseSupport.httpsURL(url) }
        return nil
    }

    private func videoStreamURL(_ note: [String: Any]) -> URL? {
        guard let video = note.dict("video") else { return nil }
        if let stream = video.digDict("media", "stream"), let url = streamURL(fromStream: stream) {
            return url
        }
        if let key = video.digString("consumer", "originVideoKey") {
            return ParseSupport.httpsURL("https://sns-video-bd.xhscdn.com/\(key)")
        }
        return nil
    }

    private func streamURL(fromStream stream: [String: Any]) -> URL? {
        for codec in ["h264", "h265", "av1", "h266"] {
            if let list = stream.array(codec) as? [[String: Any]], let url = list.first?.string("masterUrl") {
                return ParseSupport.httpsURL(url)
            }
        }
        return nil
    }
}

private extension Dictionary where Key == String, Value == Any {
    func digDouble(_ keys: String...) -> Double? {
        var current: Any? = self
        for key in keys {
            current = (current as? [String: Any])?[key]
        }
        if let value = current as? Double { return value }
        if let value = current as? NSNumber { return value.doubleValue }
        return nil
    }
}
