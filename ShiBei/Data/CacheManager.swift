import Foundation
import Foundation
import SwiftUI
import SwiftData

/// 缓存进程状态：选中条目 → 逐条下载媒体 → 写入本地路径。
@Observable
@MainActor
final class CacheManager {
    static let shared = CacheManager()

    /// item.id → 0...1
    private(set) var progress: [UUID: Double] = [:]
    private(set) var failures: [UUID: String] = [:]
    private(set) var totalBytes: Int64 = 0

    private var running: Set<UUID> = []
    /// 已排队、尚未真正开始的任务；用于防止重复点击产生多个等待者
    private var pending: Set<UUID> = []
    private var context: ModelContext { ShiBeiContainer.shared.context }

    private var maxConcurrent: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxConcurrentDownloads")
        guard stored > 0 else { return 3 }
        return max(1, min(stored, 6))
    }

    private init() {}

    func isCaching(_ id: UUID) -> Bool {
        running.contains(id) || pending.contains(id)
    }

    func progress(for id: UUID) -> Double? {
        progress[id]
    }

    func failure(for id: UUID) -> String? {
        failures[id]
    }

    func refreshTotals() {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []

        // 文件可能被系统清理或用户在「文件」App 里删除，修正已失效的缓存状态
        var changed = false
        for item in items where item.isCached {
            let broken = item.media.contains { asset in
                (asset.localImage != nil && asset.localImageURL == nil)
                    || (asset.localVideo != nil && asset.localVideoURL == nil)
            }
            if broken {
                item.isCached = false
                item.cacheBytes = 0
                changed = true
            }
        }
        if changed {
            try? context.save()
        }

        totalBytes = items.reduce(Int64(0)) { $0 + $1.cacheBytes }
    }

    func cache(_ item: Item) async {
        guard !running.contains(item.id), !pending.contains(item.id) else { return }

        pending.insert(item.id)
        defer { pending.remove(item.id) }

        // 按设置限制并发，避免同时开十几个下载把带宽打满
        while running.count >= maxConcurrent {
            try? await Task.sleep(for: .milliseconds(250))
        }

        running.insert(item.id)
        progress[item.id] = 0
        failures[item.id] = nil
        defer {
            running.remove(item.id)
            progress[item.id] = nil
        }

        let folder = LibraryPaths.folder(for: item.id)
        item.folderName = item.id.uuidString
        LibraryPaths.imagesFolder(for: item.id)
        LibraryPaths.videosFolder(for: item.id)

        let assets = item.sortedMedia
        guard !assets.isEmpty else {
            failures[item.id] = "这条收藏没有可下载的媒体"
            return
        }

        var completed = 0.0
        do {
            for asset in assets {
                try await download(asset, for: item)
                completed += 1
                progress[item.id] = completed / Double(assets.count)
            }
            item.cacheBytes = LibraryService.folderSize(folder)
            item.isCached = true
            try? context.save()
            refreshTotals()
        } catch {
            failures[item.id] = error.localizedDescription
        }
    }

    private func download(_ asset: MediaAsset, for item: Item) async throws {
        let imagesFolder = LibraryPaths.imagesFolder(for: item.id)
        let videosFolder = LibraryPaths.videosFolder(for: item.id)
        let headers = Self.headers(for: item.platform)

        switch asset.kind {
        case .image:
            // 已下载过就跳过，支持中断后续传
            guard asset.localImageURL == nil, let remote = asset.remoteImageURL else { break }
            let name = "images/\(asset.id.uuidString).\(Self.fileExtension(for: remote, fallback: "jpg"))"
            let file = imagesFolder.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
            try await fetch(remote, to: file, headers: headers)
            asset.localImage = name
            asset.localPoster = name

        case .livePhoto:
            if asset.localImageURL == nil, let remote = asset.remoteImageURL {
                let name = "images/\(asset.id.uuidString).\(Self.fileExtension(for: remote, fallback: "jpg"))"
                let file = imagesFolder.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
                try await fetch(remote, to: file, headers: headers)
                asset.localImage = name
                asset.localPoster = name
            }
            if asset.localVideoURL == nil, let remote = asset.remoteVideoURL {
                let name = "videos/\(asset.id.uuidString).\(Self.fileExtension(for: remote, fallback: "mov"))"
                let file = videosFolder.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
                try await fetch(remote, to: file, headers: headers)
                asset.localVideo = name
            }

        case .video:
            if asset.localVideoURL == nil, let remote = asset.remoteVideoURL {
                let name = "videos/\(asset.id.uuidString).mp4"
                let destination = videosFolder.appendingPathComponent("\(asset.id.uuidString).mp4")
                try await fetch(remote, to: destination, headers: headers)

                if let audioRemote = asset.remoteAudioURL {
                    let audioTemp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(asset.id.uuidString)-audio.m4s")
                    try await fetch(audioRemote, to: audioTemp, headers: headers)

                    // 先合并到独立文件，成功后再替换源视频；
                    // 否则合并失败会把刚下载好的无声视频一起删掉。
                    let merged = videosFolder.appendingPathComponent("\(asset.id.uuidString)-merged.mp4")
                    do {
                        try await MediaMerger.merge(videoURL: destination, audioURL: audioTemp, outputURL: merged)
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: merged, to: destination)
                    } catch {
                        try? FileManager.default.removeItem(at: merged)
                        item.parseNotes = (item.parseNotes ?? "") + "\n音视频合并失败：\(error.localizedDescription)"
                    }
                    try? FileManager.default.removeItem(at: audioTemp)
                }
                asset.localVideo = name
            }

            if asset.localPosterURL == nil,
               let poster = asset.posterRemote,
               let posterURL = URL(string: poster) {
                let file = imagesFolder.appendingPathComponent("\(asset.id.uuidString)-poster.jpg")
                try? await fetch(posterURL, to: file, headers: headers)
                asset.localPoster = "images/\(asset.id.uuidString)-poster.jpg"
            }
        }

        try? context.save()
    }

    private func fetch(_ url: URL, to destination: URL, headers: [String: String]) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let temporary = try await FileDownloader.shared.download(request) { _ in }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    func deleteCache(_ item: Item) {
        if let folder = item.folderURL {
            try? FileManager.default.removeItem(at: folder)
        }
        item.isCached = false
        item.cacheBytes = 0
        for asset in item.media {
            asset.localImage = nil
            asset.localVideo = nil
            asset.localPoster = nil
        }
        try? context.save()
        refreshTotals()
    }

    static func headers(for platform: Platform) -> [String: String] {
        var headers = ["User-Agent": platform == .bilibili ? UserAgent.desktop : UserAgent.iphone]
        if let referer = platform.mediaReferer {
            headers["Referer"] = referer
        }
        if let cookie = PlatformCookie.header(for: platform) {
            headers["Cookie"] = cookie
        }
        return headers
    }

    static func fileExtension(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.lowercased()
        let allowed = ["jpg", "jpeg", "png", "webp", "heic", "gif", "mp4", "mov", "m4v"]
        return allowed.contains(ext) ? ext : fallback
    }
}
