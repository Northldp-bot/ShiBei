import Foundation
import SwiftUI

/// 支持的平台。`web` 为兜底（OpenGraph 解析）。
enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
    case xiaohongshu
    case douyin
    case bilibili
    case zhihu
    case weibo
    case heybox
    case web

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xiaohongshu: return "小红书"
        case .douyin: return "抖音"
        case .bilibili: return "B站"
        case .zhihu: return "知乎"
        case .weibo: return "微博"
        case .heybox: return "小黑盒"
        case .web: return "网页"
        }
    }

    /// 卡片角标上的单字
    var shortMark: String {
        switch self {
        case .xiaohongshu: return "小"
        case .douyin: return "抖"
        case .bilibili: return "B"
        case .zhihu: return "知"
        case .weibo: return "微"
        case .heybox: return "盒"
        case .web: return "网"
        }
    }

    var tint: Color {
        switch self {
        case .xiaohongshu: return Color(rgb: 0xFF2442)
        case .douyin: return Color(rgb: 0x161823)
        case .bilibili: return Color(rgb: 0x00A1D6)
        case .zhihu: return Color(rgb: 0x0A7CFF)
        case .weibo: return Color(rgb: 0xE6162D)
        case .heybox: return Color(rgb: 0xFF6B00)
        case .web: return Color(rgb: 0x8E8E93)
        }
    }

    var hosts: [String] {
        switch self {
        case .xiaohongshu: return ["xiaohongshu.com", "xhslink.com"]
        case .douyin: return ["douyin.com", "iesdouyin.com", "v.douyin.com"]
        case .bilibili: return ["bilibili.com", "b23.tv", "bili2233.cn"]
        case .zhihu: return ["zhihu.com", "zhihu.cn"]
        case .weibo: return ["weibo.com", "weibo.cn", "m.weibo.cn"]
        case .heybox: return ["xiaoheihe.cn", "heybox.com", "heybox.net"]
        case .web: return []
        }
    }

    static func detect(from url: URL) -> Platform? {
        guard let host = url.host?.lowercased() else { return nil }
        for platform in Platform.allCases where platform != .web {
            if platform.hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                return platform
            }
        }
        return nil
    }

    /// 媒体下载需要的 Referer / UA 组合
    var mediaReferer: String? {
        switch self {
        case .xiaohongshu: return "https://www.xiaohongshu.com/"
        case .douyin: return "https://www.douyin.com/"
        case .bilibili: return "https://www.bilibili.com/"
        case .zhihu: return "https://www.zhihu.com/"
        case .weibo: return "https://m.weibo.cn/"
        case .heybox: return "https://www.xiaoheihe.cn/"
        case .web: return nil
        }
    }
}

enum MediaKind: String, Codable, CaseIterable, Sendable {
    case image
    case video
    case livePhoto

    var label: String {
        switch self {
        case .image: return "图片"
        case .video: return "视频"
        case .livePhoto: return "实况"
        }
    }

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .livePhoto: return "livephoto"
        }
    }
}
