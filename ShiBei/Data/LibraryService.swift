import Foundation
import SwiftData
import UIKit

@MainActor
enum LibraryService {
    static var context: ModelContext { ShiBeiContainer.shared.context }

    @discardableResult
    static func save(_ content: ParsedContent, tags: [String] = []) throws -> Item {
        let id = UUID()
        let folder = LibraryPaths.folder(for: id)

        let item = Item(
            id: id,
            platform: content.platform,
            sourceURL: content.sourceURL.absoluteString,
            title: content.title,
            text: content.text,
            authorName: content.authorName,
            authorAvatarURL: content.authorAvatarURL?.absoluteString,
            publishedAt: content.publishedAt,
            folderName: id.uuidString,
            coverRemote: content.coverURL?.absoluteString,
            tags: tags,
            topics: content.topics,
            lastEditedAt: nil,
            lastViewedAt: nil,
            viewCount: 0,
            parseNotes: content.diagnostics.joined(separator: "\n")
        )
        item.media = content.media.enumerated().map { index, media in
            MediaAsset(
                kind: media.kind,
                order: index,
                remoteImage: media.imageURL?.absoluteString,
                remoteVideo: media.videoURL?.absoluteString,
                remoteAudio: media.audioURL?.absoluteString,
                posterRemote: media.posterURL?.absoluteString,
                width: media.width ?? 0,
                height: media.height ?? 0,
                duration: media.duration ?? 0
            )
        }

        context.insert(item)
        try context.save()

        // 元数据落盘，即使数据库损坏也能恢复
        writeMetadata(item, folder: folder)
        return item
    }

    static func writeMetadata(_ item: Item, folder: URL) {
        let mediaPayload: [[String: Any]] = item.sortedMedia.map { asset in
            [
                "kind": asset.kindRaw,
                "order": asset.order,
                "image": asset.remoteImage ?? "",
                "video": asset.remoteVideo ?? "",
                "audio": asset.remoteAudio ?? ""
            ]
        }

        let payload: [String: Any] = [
            "id": item.id.uuidString,
            "platform": item.platformRaw,
            "source": item.sourceURL,
            "title": item.title,
            "text": item.text,
            "author": item.authorName,
            "savedAt": ISO8601DateFormatter().string(from: item.savedAt),
            "media": mediaPayload
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }
        try? data.write(to: folder.appendingPathComponent("item.json"), options: .atomic)
    }

    static func delete(_ item: Item) {
        if let folder = item.folderURL {
            try? FileManager.default.removeItem(at: folder)
        }
        context.delete(item)
        try? context.save()
    }

    static func updateTags(_ item: Item, tags: [String]) {
        item.tags = tags
        item.lastEditedAt = .now
        try? context.save()
    }

    static func updateTopics(_ item: Item, topics: [String]) {
        item.topics = topics
        item.lastEditedAt = .now
        try? context.save()
    }

    static func updateText(_ item: Item, text: String) {
        item.text = text
        item.lastEditedAt = .now
        try? context.save()
    }

    /// 打开详情时记一次浏览
    static func recordView(_ item: Item) {
        item.lastViewedAt = .now
        item.viewCount += 1
        try? context.save()
    }

    static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
