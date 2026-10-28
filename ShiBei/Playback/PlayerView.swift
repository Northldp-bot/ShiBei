import SwiftUI
import AVKit

struct PlayableMedia: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let subtitle: String
}

/// 本地视频播放器（AVPlayer / AVKit 原生控件，支持画中画与手势）。
struct PlayerView: View {
    let media: PlayableMedia

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var controlsVisible = true

    init(media: PlayableMedia) {
        self.media = media
        _player = State(initialValue: AVPlayer(url: media.url))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() } }

            if controlsVisible {
                topBar
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .onAppear {
            player.play()
            scheduleAutoHide()
        }
        .onDisappear {
            player.pause()
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.14)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(media.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(media.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func scheduleAutoHide() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
            }
        }
    }
}
