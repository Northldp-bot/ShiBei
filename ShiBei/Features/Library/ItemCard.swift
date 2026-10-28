import SwiftUI
import UIKit

@MainActor
struct ItemCard: View {
    let item: Item

    @Environment(AppState.self) private var appState
    @Environment(CacheManager.self) private var cache

    private var assets: [MediaAsset] { item.sortedMedia }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            if !item.text.isEmpty {
                Text(item.text)
                    .font(Theme.body(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            mediaArea
            metaRow
            Divider().overlay(Theme.hairline)
            actionRow
        }
        .cardStyle(padding: 16)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            AuthorAvatar(url: item.authorAvatarURL.flatMap(URL.init(string:)), name: item.authorName)
            Text(item.authorName.isEmpty ? "未知作者" : item.authorName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            PlatformBadge(platform: item.platform)
            Spacer(minLength: 8)
            Text(Formatters.ago(item.savedAt))
                .font(Theme.meta())
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    // MARK: Media

    @ViewBuilder
    private var mediaArea: some View {
        if let first = assets.first, first.kind == .video, assets.count == 1 {
            videoCover(first)
        } else if !assets.isEmpty {
            grid
        }
    }

    private func videoCover(_ asset: MediaAsset) -> some View {
        ZStack {
            MediaThumb(local: asset.localPosterURL ?? asset.localImageURL, remote: asset.posterRemote.flatMap(URL.init(string:)) ?? asset.remoteImageURL)
                .aspectRatio(16 / 10, contentMode: .fill)
            Color.black.opacity(0.18)
            Image(systemName: "play.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(.white.opacity(0.24)))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
            badge("视频")
                .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            if asset.duration > 0 {
                Text(Formatters.duration(asset.duration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(8)
            }
        }
    }

    private var grid: some View {
        let visible = Array(assets.prefix(9))
        let columns = gridColumns(count: visible.count)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(visible.indices, id: \.self) { index in
                let asset = visible[index]
                MediaTile(
                    asset: asset,
                    extraCount: index == 8 ? max(assets.count - 9, 0) : 0,
                    singleColumn: visible.count == 1
                )
            }
        }
    }

    private func gridColumns(count: Int) -> [GridItem] {
        switch count {
        case 1:
            return [GridItem(.flexible())]
        case 2:
            return [GridItem(.flexible(), spacing: 4), GridItem(.flexible())]
        default:
            return Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.45)))
    }

    // MARK: Meta

    private var metaRow: some View {
        HStack(spacing: 8) {
            if !item.text.isEmpty {
                Text("字 · \(item.text.count)")
            }
            if !assets.isEmpty {
                dot
                Text("图 · \(assets.filter { $0.kind != .video }.count)")
            }
            let liveCount = assets.filter { $0.kind == .livePhoto }.count
            if liveCount > 0 {
                dot
                Text("实况 · \(liveCount)")
            }
            if item.hasVideo {
                dot
                Text("视频")
            }

            Spacer()

            if cache.isCaching(item.id) {
                Text("缓存中 \(Int((cache.progress(for: item.id) ?? 0) * 100))%")
                    .foregroundStyle(Theme.warning)
            } else if item.isCached {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                    Text("已缓存")
                }
                .foregroundStyle(Theme.success)
            } else {
                Text(Formatters.day(item.savedAt))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .font(Theme.meta())
        .foregroundStyle(Theme.inkTertiary)
    }

    private var dot: some View {
        Circle().fill(Theme.inkTertiary.opacity(0.5)).frame(width: 3, height: 3)
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack {
            Button {
                Task { await cache.cache(item) }
            } label: {
                actionLabel(icon: "arrow.down.to.line", title: item.isCached ? "已缓存" : "缓存")
            }
            .disabled(cache.isCaching(item.id))

            Spacer()

            Button {
                Task { await PhotoSaver.save(item: item, cache: cache, appState: appState) }
            } label: {
                actionLabel(icon: "photo.on.rectangle", title: "存相册")
            }

            Spacer()

            ShareLink(item: URL(string: item.sourceURL) ?? URL(string: "https://shibei.app")!) {
                actionLabel(icon: "square.and.arrow.up", title: "分享")
            }

            Spacer()

            Menu {
                Button {
                    UIPasteboard.general.string = item.sourceURL
                    appState.toast = ToastMessage(text: "链接已复制", style: .success)
                } label: {
                    Label("复制原链接", systemImage: "link")
                }

                Button {
                    Task { await cache.cache(item) }
                } label: {
                    Label(item.isCached ? "重新缓存" : "加入缓存", systemImage: "arrow.triangle.2.circlepath")
                }

                if item.isCached {
                    Button(role: .destructive) {
                        cache.deleteCache(item)
                    } label: {
                        Label("删除缓存", systemImage: "trash")
                    }
                    .disabled(cache.isCaching(item.id))
                }

                Divider()

                Button(role: .destructive) {
                    LibraryService.delete(item)
                    appState.toast = ToastMessage(text: "已删除", style: .info)
                } label: {
                    Label("删除收藏", systemImage: "trash")
                }
                .disabled(cache.isCaching(item.id))
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(width: 34, height: 28)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private func actionLabel(icon: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            Text(title).font(.system(size: 13))
        }
        .foregroundStyle(Theme.inkSecondary)
        .padding(.vertical, 6)
    }
}

// MARK: - 单个媒体格

struct MediaTile: View {
    let asset: MediaAsset
    var extraCount: Int = 0
    var singleColumn = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MediaThumb(
                    local: asset.localImageURL,
                    remote: asset.remoteImageURL ?? asset.posterRemote.flatMap(URL.init(string:))
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                if asset.kind == .livePhoto {
                    VStack {
                        Spacer()
                        HStack {
                            Text("◎ 实况")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.45)))
                            Spacer()
                        }
                        .padding(6)
                    }
                }

                if asset.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.black.opacity(0.42)))
                }

                if extraCount > 0 {
                    ZStack {
                        Color.black.opacity(0.38)
                        Text("+\(extraCount)")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .aspectRatio(singleColumn ? 4 / 3 : 1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
