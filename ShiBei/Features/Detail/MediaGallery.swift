import SwiftUI

/// 详情页媒体轮播：静图 / 实况图 / 视频。
struct MediaGallery: View {
    let item: Item
    @State private var index: Int = 0
    @State private var playing: PlayableMedia?

    private var assets: [MediaAsset] { item.sortedMedia }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $index) {
                ForEach(assets.indices, id: \.self) { offset in
                    page(for: assets[offset])
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if assets.count > 1 {
                if assets.count <= 8 {
                    HStack(spacing: 5) {
                        ForEach(assets.indices, id: \.self) { position in
                            Circle()
                                .fill(.white.opacity(position == index ? 1 : 0.42))
                                .frame(width: position == index ? 6 : 5, height: position == index ? 6 : 5)
                        }
                    }
                    .padding(.bottom, 44)
                    .animation(.snappy(duration: 0.2), value: index)
                } else {
                    // 图片很多时用计数，避免圆点横向溢出
                    Text("\(index + 1) / \(assets.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.45)))
                        .padding(.bottom, 44)
                }
            }
        }
        .background(Color.black)
        .sheet(item: $playing) { media in
            PlayerView(media: media)
                .presentationBackground(.black)
        }
    }

    @ViewBuilder
    private func page(for asset: MediaAsset) -> some View {
        switch asset.kind {
        case .image:
            MediaThumb(local: asset.localImageURL, remote: asset.remoteImageURL ?? asset.posterRemote.flatMap(URL.init(string:)))
                .aspectRatio(contentMode: .fit)

        case .livePhoto:
            if let image = asset.localImageURL, let video = asset.localVideoURL {
                LivePhotoView(imageURL: image, videoURL: video)
                    .overlay(alignment: .bottomLeading) {
                        liveBadge(text: "实况 · 按住播放")
                    }
            } else {
                MediaThumb(local: asset.localImageURL, remote: asset.remoteImageURL)
                    .aspectRatio(contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        liveBadge(text: item.isCached ? "实况" : "实况 · 缓存后可播放")
                    }
            }

        case .video:
            Button {
                let url = asset.localVideoURL ?? asset.remoteVideoURL
                guard let url else { return }
                playing = PlayableMedia(
                    url: url,
                    title: item.displayTitle,
                    subtitle: "\(item.platform.displayName) · \(item.authorName)"
                )
            } label: {
                ZStack {
                    MediaThumb(
                        local: asset.localPosterURL ?? asset.localImageURL,
                        remote: asset.posterRemote.flatMap(URL.init(string:)) ?? asset.remoteImageURL
                    )
                    .aspectRatio(contentMode: .fit)

                    Color.black.opacity(0.16)

                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(Circle().fill(.white.opacity(0.2)))
                        .overlay(Circle().stroke(.white.opacity(0.32), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomLeading) {
                liveBadge(text: asset.localVideoURL != nil ? "本地播放" : "在线播放")
            }
        }
    }

    private func liveBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(.black.opacity(0.42)))
            .padding(.leading, 16)
            .padding(.bottom, 40)
    }
}
