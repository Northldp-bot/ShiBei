import Foundation
import Photos
import SwiftUI

@MainActor
enum PhotoSaver {
    static func save(item: Item, cache: CacheManager, appState: AppState) async {
        if !item.isCached {
            if cache.isCaching(item.id) {
                // 已有缓存任务在排队或进行中，等它结束再保存，避免误报失败
                var waited: TimeInterval = 0
                while cache.isCaching(item.id), waited < 180 {
                    try? await Task.sleep(for: .milliseconds(300))
                    waited += 0.3
                }
            } else {
                appState.toast = ToastMessage(text: "正在缓存，稍后自动保存…", style: .info)
                await cache.cache(item)
            }
        }
        guard item.isCached else {
            appState.toast = ToastMessage(
                text: cache.failure(for: item.id) ?? "缓存失败，无法保存",
                style: .failure
            )
            return
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            appState.toast = ToastMessage(text: "没有相册写入权限，请在系统设置中开启", style: .failure)
            return
        }

        var count = 0
        let keepLiveAsLivePhoto = (UserDefaults.standard.object(forKey: "saveLiveAsLivePhoto") as? Bool) ?? true
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for asset in item.sortedMedia {
                    switch asset.kind {
                    case .image:
                        if let url = asset.localImageURL {
                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                            count += 1
                        }
                    case .video:
                        if let url = asset.localVideoURL {
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                            count += 1
                        }
                    case .livePhoto:
                        if keepLiveAsLivePhoto, let image = asset.localImageURL, let video = asset.localVideoURL {
                            let request = PHAssetCreationRequest.forAsset()
                            request.addResource(with: .photo, fileURL: image, options: nil)
                            let options = PHAssetResourceCreationOptions()
                            options.shouldMoveFile = false
                            request.addResource(with: .pairedVideo, fileURL: video, options: options)
                            count += 1
                        } else {
                            if let image = asset.localImageURL {
                                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: image)
                                count += 1
                            }
                            if let video = asset.localVideoURL {
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
                                count += 1
                            }
                        }
                    }
                }
            }
            appState.toast = ToastMessage(
                text: count > 0 ? "已保存 \(count) 项到相册" : "没有可保存的媒体",
                style: count > 0 ? .success : .info
            )
        } catch {
            appState.toast = ToastMessage(text: "保存失败：\(error.localizedDescription)", style: .failure)
        }
    }
}
