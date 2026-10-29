import Foundation
import SwiftData

@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var platformRaw: String
    var sourceURL: String
    var title: String
    /// 完整正文，不截断
    var text: String
    var authorName: String
    var authorAvatarURL: String?
    var publishedAt: Date?
    var savedAt: Date
    var isCached: Bool
    var cacheBytes: Int64
    var folderName: String?
    var coverRemote: String?
    var tags: [String]
    /// 话题，来自正文 `#…#`，可手动增改
    var topics: [String]
    var lastEditedAt: Date?
    var lastViewedAt: Date?
    var viewCount: Int
    var parseNotes: String?

    @Relationship(deleteRule: .cascade, inverse: \MediaAsset.item)
    var media: [MediaAsset]

    init(
        id: UUID = UUID(),
        platform: Platform,
        sourceURL: String,
        title: String,
        text: String,
        authorName: String,
        authorAvatarURL: String? = nil,
        publishedAt: Date? = nil,
        savedAt: Date = .now,
        isCached: Bool = false,
        cacheBytes: Int64 = 0,
        folderName: String? = nil,
        coverRemote: String? = nil,
        tags: [String] = [],
        topics: [String] = [],
        lastEditedAt: Date? = nil,
        lastViewedAt: Date? = nil,
        viewCount: Int = 0,
        parseNotes: String? = nil,
        media: [MediaAsset] = []
    ) {
        self.id = id
        self.platformRaw = platform.rawValue
        self.sourceURL = sourceURL
        self.title = title
        self.text = text
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.publishedAt = publishedAt
        self.savedAt = savedAt
        self.isCached = isCached
        self.cacheBytes = cacheBytes
        self.folderName = folderName
        self.coverRemote = coverRemote
        self.tags = tags
        self.topics = topics
        self.lastEditedAt = lastEditedAt
        self.lastViewedAt = lastViewedAt
        self.viewCount = viewCount
        self.parseNotes = parseNotes
        self.media = media
    }

    var platform: Platform {
        Platform(rawValue: platformRaw) ?? .web
    }

    var sortedMedia: [MediaAsset] {
        media.sorted { $0.order < $1.order }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        let firstLine = text.split(separator: "\n").first.map { String($0) } ?? text
        return String(firstLine.prefix(38))
    }

    var hasVideo: Bool {
        media.contains { $0.kind == .video }
    }

    var coverURL: URL? {
        if let local = sortedMedia.first(where: { $0.localImage != nil })?.localImageURL {
            return local
        }
        if let remote = coverRemote.flatMap(URL.init(string:)) { return remote }
        return sortedMedia.first?.remoteImage.flatMap(URL.init(string:))
    }
}

@Model
final class MediaAsset {
    var id: UUID
    var kindRaw: String
    var remoteImage: String?
    var remoteVideo: String?
    var remoteAudio: String?
    var posterRemote: String?
    var localImage: String?
    var localVideo: String?
    var localPoster: String?
    var order: Int
    var width: Int
    var height: Int
    var duration: Double
    var item: Item?

    init(
        id: UUID = UUID(),
        kind: MediaKind,
        order: Int,
        remoteImage: String? = nil,
        remoteVideo: String? = nil,
        remoteAudio: String? = nil,
        posterRemote: String? = nil,
        width: Int = 0,
        height: Int = 0,
        duration: Double = 0
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.order = order
        self.remoteImage = remoteImage
        self.remoteVideo = remoteVideo
        self.remoteAudio = remoteAudio
        self.posterRemote = posterRemote
        self.width = width
        self.height = height
        self.duration = duration
    }

    var kind: MediaKind {
        MediaKind(rawValue: kindRaw) ?? .image
    }

    var remoteImageURL: URL? { remoteImage.flatMap(URL.init(string:)) }
    var remoteVideoURL: URL? { remoteVideo.flatMap(URL.init(string:)) }
    var remoteAudioURL: URL? { remoteAudio.flatMap(URL.init(string:)) }

    var localImageURL: URL? {
        guard let localImage, let folder = item?.folderURL else { return nil }
        let url = folder.appendingPathComponent(localImage)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var localVideoURL: URL? {
        guard let localVideo, let folder = item?.folderURL else { return nil }
        let url = folder.appendingPathComponent(localVideo)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var localPosterURL: URL? {
        guard let localPoster, let folder = item?.folderURL else { return nil }
        let url = folder.appendingPathComponent(localPoster)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

extension Item {
    var folderURL: URL? {
        guard let folderName else { return nil }
        return LibraryPaths.libraryRoot.appendingPathComponent(folderName, isDirectory: true)
    }
}

/// 全局模型容器
@MainActor
final class ShiBeiContainer {
    static let shared = ShiBeiContainer()
    let container: ModelContainer

    private init() {
        let schema = Schema([Item.self, MediaAsset.self])
        let configuration = ModelConfiguration("ShiBei", schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            let fallback = ModelConfiguration("ShiBei", schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: fallback)
        }
    }

    var context: ModelContext { container.mainContext }
}
