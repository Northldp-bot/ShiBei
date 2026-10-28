import Foundation
import AVFoundation

/// B 站 DASH 音视频合并。
enum MediaMerger {
    static func merge(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceVideo = videoTracks.first else {
            throw ParseError.upstream("视频轨缺失，无法合并")
        }
        guard let sourceAudio = audioTracks.first else {
            throw ParseError.upstream("音轨缺失，无法合并")
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let duration = CMTimeMinimum(videoDuration, audioDuration)

        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ), let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ParseError.upstream("无法创建合成轨道")
        }

        let range = CMTimeRange(start: .zero, duration: duration)
        try compositionVideo.insertTimeRange(range, of: sourceVideo, at: .zero)
        try compositionAudio.insertTimeRange(range, of: sourceAudio, at: .zero)
        if let transform = try? await sourceVideo.load(.preferredTransform) {
            compositionVideo.preferredTransform = transform
        }

        try? FileManager.default.removeItem(at: outputURL)
        try await export(composition, to: outputURL)
    }

    static func export(_ asset: AVAsset, to outputURL: URL) async throws {
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var lastError: Error?

        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            session.outputURL = outputURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }

            if session.status == .completed,
               FileManager.default.fileExists(atPath: outputURL.path) {
                return
            }
            lastError = session.error
            try? FileManager.default.removeItem(at: outputURL)
        }
        throw lastError ?? ParseError.upstream("音视频合并失败")
    }
}
