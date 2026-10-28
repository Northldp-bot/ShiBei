import Foundation

/// 知乎：回答 / 专栏 / 视频 / 想法。
/// 页面内 js-initialData 含完整正文 HTML，无需登录。
struct ZhihuResolver: ContentResolver {
    let platform: Platform = .zhihu

    func canResolve(_ url: URL) -> Bool {
        Platform.detect(from: url) == .zhihu
    }

    func resolve(_ url: URL, http: HTTPClient) async throws -> ParsedContent {
        let headers = ["User-Agent": UserAgent.desktop]
        let (html, finalURL) = try await http.decoded(url, headers: headers, referer: "https://www.zhihu.com/")
        var notes = ["final: \(finalURL.absoluteString)"]

        guard let script = EmbeddedJSON.object(inScriptID: "js-initialData", html: html)
                ?? EmbeddedJSON.object(after: "window.__INITIAL_STATE__", in: html),
              let state = script.dict("initialState"),
              let entities = state.dict("entities") else {
            if html.contains("40362") || html.contains("请求存在异常") {
                throw ParseError.blocked("知乎对当前网络触发了风控（40362），请切换网络后重试")
            }
            notes.append("未找到 js-initialData，回退 OpenGraph")
            return try await GenericResolver().resolve(url, http: http)
        }

        if let answerID = ParseSupport.firstMatch("/answer/(\\d+)", in: finalURL.absoluteString) {
            return try await resolveAnswer(answerID, url: finalURL, entities: entities, notes: notes)
        }
        if let articleID = ParseSupport.firstMatch("/p/(\\d+)", in: finalURL.absoluteString) {
            return try await resolveArticle(articleID, url: finalURL, entities: entities, notes: notes)
        }
        if let pinID = ParseSupport.firstMatch("/pin/(\\d+)", in: finalURL.absoluteString) {
            return try await resolvePin(pinID, url: finalURL, entities: entities, notes: notes)
        }
        if let videoID = ParseSupport.firstMatch("/zvideo/(\\d+)", in: finalURL.absoluteString) {
            return try await resolveZVideo(videoID, url: finalURL, entities: entities, http: http, notes: notes)
        }
        throw ParseError.unsupportedLink
    }

    // MARK: - Answer

    private func resolveAnswer(
        _ answerID: String,
        url: URL,
        entities: [String: Any],
        notes: [String]
    ) async throws -> ParsedContent {
        guard let answers = entities.dict("answers"),
              let answer = answers.dict(answerID) else {
            throw ParseError.upstream("entities.answers 中缺少 \(answerID)")
        }

        let content = answer.string("content") ?? ""
        let questionID = answer.string("questionId")
            ?? ParseSupport.firstMatch("/question/(\\d+)", in: url.absoluteString)
        var questionTitle = ""
        if let questionID, let questions = entities.dict("questions"),
           let question = questions.dict(questionID) {
            questionTitle = question.string("title") ?? ""
        }

        return try build(
            content: content,
            title: questionTitle,
            author: answer.dict("author"),
            created: answer.int("createdTime") ?? answer.int("created"),
            url: url,
            http: nil,
            platformNotes: notes
        )
    }

    // MARK: - Article

    private func resolveArticle(
        _ articleID: String,
        url: URL,
        entities: [String: Any],
        notes: [String]
    ) async throws -> ParsedContent {
        guard let articles = entities.dict("articles"),
              let article = articles.dict(articleID) else {
            throw ParseError.upstream("entities.articles 中缺少 \(articleID)")
        }
        return try build(
            content: article.string("content") ?? "",
            title: article.string("title") ?? "",
            author: article.dict("author"),
            created: article.int("created") ?? article.int("updated"),
            url: url,
            http: nil,
            platformNotes: notes
        )
    }

    // MARK: - Pin（想法）

    private func resolvePin(
        _ pinID: String,
        url: URL,
        entities: [String: Any],
        notes: [String]
    ) async throws -> ParsedContent {
        guard let pins = entities.dict("pins"), let pin = pins.dict(pinID) else {
            throw ParseError.upstream("entities.pins 中缺少 \(pinID)")
        }
        let blocks = pin.array("content") as? [[String: Any]] ?? []
        let html = blocks.compactMap { $0.string("content") }.joined(separator: "\n")
        let images = blocks.compactMap { $0.string("originalUrl") ?? $0.string("url") }
            .compactMap { ParseSupport.httpsURL($0) }
        var media = images.map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
        if media.isEmpty {
            media = HTMLTools.imageURLs(in: html).map { ParsedMedia(kind: .image, imageURL: $0, posterURL: $0) }
        }
        return ParsedContent(
            platform: .zhihu,
            sourceURL: url,
            title: pin.string("excerptTitle") ?? "",
            text: HTMLTools.plainText(from: html),
            authorName: pin.digString("author", "name") ?? "",
            authorAvatarURL: ParseSupport.httpsURL(pin.digString("author", "avatarUrl")),
            publishedAt: ParseSupport.dateFromUnix(pin.int("created")),
            media: media,
            diagnostics: notes
        )
    }

    // MARK: - ZVideo

    private func resolveZVideo(
        _ videoID: String,
        url: URL,
        entities: [String: Any],
        http: HTTPClient,
        notes: [String]
    ) async throws -> ParsedContent {
        guard let zvideos = entities.dict("zvideos"), let video = zvideos.dict(videoID) else {
            throw ParseError.upstream("entities.zvideos 中缺少 \(videoID)")
        }
        let title = video.string("title") ?? ""
        let playlistString = video.string("playlist")
        var videoURL: URL?
        if let playlistString, let playlistURL = ParseSupport.httpsURL(playlistString),
           let playlistJSON = try? await http.json(playlistURL, headers: ["User-Agent": UserAgent.desktop], referer: "https://www.zhihu.com/"),
           let playlist = playlistJSON as? [String: Any],
           let sources = playlist.digDict("playlist")?.array("sources") as? [[String: Any]] {
            let best = sources.max { ($0.int("bitrate") ?? 0) < ($1.int("bitrate") ?? 0) }
            videoURL = ParseSupport.httpsURL(best?.string("url") ?? sources.first?.string("url"))
        }
        var media: [ParsedMedia] = []
        if let videoURL {
            media.append(ParsedMedia(
                kind: .video,
                videoURL: videoURL,
                posterURL: ParseSupport.httpsURL(video.string("image_url")),
                duration: video.double("duration")
            ))
        }
        return ParsedContent(
            platform: .zhihu,
            sourceURL: url,
            title: title,
            text: video.string("description") ?? "",
            authorName: video.digString("author", "name") ?? "",
            authorAvatarURL: ParseSupport.httpsURL(video.digString("author", "avatarUrl")),
            publishedAt: ParseSupport.dateFromUnix(video.int("created")),
            media: media,
            diagnostics: notes
        )
    }

    // MARK: - Shared

    private func build(
        content: String,
        title: String,
        author: [String: Any]?,
        created: Int?,
        url: URL,
        http: HTTPClient?,
        platformNotes: [String]
    ) throws -> ParsedContent {
        var media = HTMLTools.imageURLs(in: content).map {
            ParsedMedia(kind: .image, imageURL: $0, posterURL: $0)
        }
        let text = HTMLTools.plainText(from: content)
        guard !media.isEmpty || !text.isEmpty else { throw ParseError.noMedia }

        return ParsedContent(
            platform: .zhihu,
            sourceURL: url,
            title: title,
            text: text,
            authorName: author?.string("name") ?? "",
            authorAvatarURL: ParseSupport.httpsURL(
                author?.string("avatarUrl") ?? author?.string("avatar_url")
            ),
            publishedAt: ParseSupport.dateFromUnix(created),
            media: media,
            diagnostics: platformNotes
        )
    }
}
