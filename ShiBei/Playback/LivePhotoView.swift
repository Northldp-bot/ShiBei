import SwiftUI
import PhotosUI

/// 用本地 JPEG + MOV 构造可播放的实况图。构建失败时由上层回退为静图。
struct LivePhotoView: UIViewRepresentable {
    let imageURL: URL
    let videoURL: URL
    var onFailure: () -> Void = {}

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        let key = imageURL.path + "|" + videoURL.path
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key

        PHLivePhoto.request(
            withResourceFileURLs: [imageURL, videoURL],
            placeholderImage: nil,
            targetSize: .zero,
            contentMode: .aspectFit
        ) { livePhoto, _ in
            DispatchQueue.main.async {
                if let livePhoto {
                    uiView.livePhoto = livePhoto
                } else {
                    onFailure()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var key: String?
    }
}
