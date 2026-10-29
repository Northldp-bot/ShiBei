import SwiftUI
import SwiftData

@MainActor
struct CacheView: View {
    @Environment(AppState.self) private var appState
    @Environment(CacheManager.self) private var cache
    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]

    @State private var showClearConfirm = false

    private var cachedItems: [Item] { items.filter(\.isCached) }

    private var totals: (bytes: Int64, video: Int64, image: Int64, live: Int64) {
        var video: Int64 = 0, image: Int64 = 0, live: Int64 = 0
        for item in cachedItems {
            for asset in item.media {
                let size = assetSize(asset)
                switch asset.kind {
                case .video: video += size
                case .image: image += size
                case .livePhoto: live += size
                }
            }
        }
        return (video + image + live, video, image, live)
    }

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(FileSize.string(totals.bytes))
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.6)
                        .padding(.top, 4)

                    Text("已缓存 \(cachedItems.count) 条收藏 · 视频 \(count(.video)) 个 · 图片 \(count(.image)) 张")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 2)

                    storageBar
                        .padding(.top, 14)

                    SectionLabel(text: "最近缓存")
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    if cachedItems.isEmpty {
                        EmptyStateView(
                            title: "还没有缓存内容",
                            message: "在收藏卡片上点「缓存」，内容会完整下载到本地，原链接失效也能继续看。"
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(cachedItems) { item in
                                NavigationLink {
                                    ItemDetailView(item: item)
                                } label: {
                                    cacheRow(item)
                                }
                                .buttonStyle(.plain)
                                if item.id != cachedItems.last?.id {
                                    Divider().overlay(Theme.hairline).padding(.leading, 72)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.surface)
                        )

                        Button {
                            showClearConfirm = true
                        } label: {
                            Text("清理全部缓存")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Theme.surface)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
            .background(Theme.canvas)
            .navigationTitle("缓存")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("确定清理全部缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清理全部", role: .destructive) {
                    for item in cachedItems {
                        cache.deleteCache(item)
                    }
                    appState.toast = ToastMessage(text: "缓存已清空", style: .info)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只会删除本地文件，收藏记录和原链接会保留。")
            }
            .onAppear { cache.refreshTotals() }
        }
    }

    private var storageBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let total = max(Double(totals.bytes), 1)
                HStack(spacing: 0) {
                    segment(Double(totals.video) / total, color: Theme.ink, width: proxy.size.width)
                    segment(Double(totals.image) / total, color: Color(rgb: 0x5B8DEF), width: proxy.size.width)
                    segment(Double(totals.live) / total, color: Color(rgb: 0xF6B26B), width: proxy.size.width)
                }
                .clipShape(Capsule())
                .background(Capsule().fill(Theme.fill))
            }
            .frame(height: 10)

            HStack(spacing: 14) {
                legend(color: Theme.ink, title: "视频 \(FileSize.string(totals.video))")
                legend(color: Color(rgb: 0x5B8DEF), title: "图片 \(FileSize.string(totals.image))")
                legend(color: Color(rgb: 0xF6B26B), title: "实况 \(FileSize.string(totals.live))")
            }
        }
    }

    private func segment(_ ratio: Double, color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width * ratio, ratio > 0 ? 3 : 0))
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.inkSecondary)
        }
    }

    private func cacheRow(_ item: Item) -> some View {
        HStack(spacing: 11) {
            MediaThumb(
                local: item.sortedMedia.first?.localPosterURL ?? item.sortedMedia.first?.localImageURL,
                remote: item.coverURL
            )
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .center) {
                if item.hasVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.black.opacity(0.3)))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.platform.displayName)
                        .foregroundStyle(item.platform.tint)
                    Text("·")
                    Text("\(item.media.count) 项")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkTertiary)
            }

            Spacer()

            Text(FileSize.string(item.cacheBytes))
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func assetSize(_ asset: MediaAsset) -> Int64 {
        var total: Int64 = 0
        for url in [asset.localImageURL, asset.localVideoURL, asset.localPosterURL].compactMap({ $0 }) {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    private func count(_ kind: MediaKind) -> Int {
        cachedItems.reduce(0) { partial, item in
            partial + item.media.filter { $0.kind == kind }.count
        }
    }
}
