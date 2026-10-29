import Foundation

/// 解析器统一输出。纯值类型，可在后台线程构造。
struct ParsedContent: Sendable {
    var platform: Platform
    var sourceURL: URL
    var title: String
    var text: String
    var authorName: String
    var authorAvatarURL: URL?
    var publishedAt: Date?
    var media: [ParsedMedia]
    var diagnostics: [String]
    /// 从正文 `#话题#` 提取，可手动增改
    var topics: [String]

    init(
        platform: Platform,
        sourceURL: URL,
        title: String = "",
        text: String = "",
        authorName: String = "",
        authorAvatarURL: URL? = nil,
        publishedAt: Date? = nil,
        media: [ParsedMedia] = [],
        diagnostics: [String] = [],
        topics: [String] = []
    ) {
        self.platform = platform
        self.sourceURL = sourceURL
        self.title = title
        self.text = text
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.publishedAt = publishedAt
        self.media = media
        self.diagnostics = diagnostics
        self.topics = topics
    }

    var images: [ParsedMedia] { media.filter { $0.kind == .image } }
    var videos: [ParsedMedia] { media.filter { $0.kind == .video } }
    var livePhotos: [ParsedMedia] { media.filter { $0.kind == .livePhoto } }

    var coverURL: URL? {
        media.first(where: { $0.kind == .livePhoto })?.imageURL
            ?? media.first(where: { $0.kind == .image })?.imageURL
            ?? media.first(where: { $0.kind == .video })?.posterURL
    }

    var characterCount: Int { text.count }
}

struct ParsedMedia: Identifiable, Sendable {
    let id: UUID
    var kind: MediaKind
    /// 实况图/图片的静态帧
    var imageURL: URL?
    /// 视频本体
    var videoURL: URL?
    /// B 站 DASH 的音轨（需要与 videoURL 合并）
    var audioURL: URL?
    /// 视频封面
    var posterURL: URL?
    var width: Int?
    var height: Int?
    var duration: Double?

    init(
        id: UUID = UUID(),
        kind: MediaKind,
        imageURL: URL? = nil,
        videoURL: URL? = nil,
        audioURL: URL? = nil,
        posterURL: URL? = nil,
        width: Int? = nil,
        height: Int? = nil,
        duration: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.posterURL = posterURL
        self.width = width
        self.height = height
        self.duration = duration
    }
}

enum ParseError: LocalizedError {
    case unsupportedLink
    case blocked(String)
    case noMedia
    case upstream(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            return "没有识别到可解析的链接，请粘贴完整的分享文本"
        case .blocked(let detail):
            return "平台拒绝了请求：\(detail)"
        case .noMedia:
            return "解析成功，但没有找到图片或视频"
        case .upstream(let detail):
            return "平台返回异常：\(detail)"
        case .badResponse:
            return "网络返回内容不完整，请重试"
        }
    }
}
