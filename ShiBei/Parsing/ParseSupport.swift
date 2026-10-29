import Foundation

protocol ContentResolver: Sendable {
    var platform: Platform { get }
    func canResolve(_ url: URL) -> Bool
    func resolve(_ url: URL, http: HTTPClient) async throws -> ParsedContent
}

enum ParseSupport {
    /// 补全协议、处理 `//` 开头与 HTML 转义
    static func httpsURL(_ raw: String?) -> URL? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "&amp;", with: "&")
        if value.hasPrefix("//") { value = "https:" + value }
        if value.hasPrefix("http://") { value = "https://" + value.dropFirst(7) }
        guard value.hasPrefix("http") else { return nil }
        return URL(string: value)
    }

    static func first(_ value: Any?) -> [String: Any]? {
        (value as? [Any])?.first as? [String: Any]
    }

    /// 深度优先寻找第一个满足条件的字典（用于平台嵌套结构不稳定的场景）
    static func find(in value: Any, depth: Int = 0, where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        guard depth < 12 else { return nil }
        if let dictionary = value as? [String: Any] {
            if predicate(dictionary) { return dictionary }
            for child in dictionary.values {
                if let found = find(in: child, depth: depth + 1, where: predicate) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = find(in: child, depth: depth + 1, where: predicate) { return found }
            }
        }
        return nil
    }

    /// 从任意 JSON 中收集媒体直链，作为兜底
    static func collectMedia(in value: Any, depth: Int = 0, into result: inout (images: [URL], videos: [URL])) {
        guard depth < 14 else { return }
        if let string = value as? String {
            appendIfMedia(string, into: &result)
            return
        }
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if let string = child as? String, key.lowercased().contains("url") || key.lowercased().contains("src") {
                    appendIfMedia(string, into: &result)
                } else {
                    collectMedia(in: child, depth: depth + 1, into: &result)
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectMedia(in: child, depth: depth + 1, into: &result)
            }
        }
    }

    static func appendIfMedia(_ raw: String, into result: inout (images: [URL], videos: [URL])) {
        let lower = raw.lowercased()
        guard lower.hasPrefix("http"), let url = httpsURL(raw) else { return }
        let imageExts = [".jpg", ".jpeg", ".png", ".webp", ".heic", ".gif"]
        let videoExts = [".mp4", ".m3u8", ".mov", ".flv"]
        if imageExts.contains(where: { lower.contains($0) }) {
            if !result.images.contains(url) { result.images.append(url) }
        } else if videoExts.contains(where: { lower.contains($0) }) {
            if !result.videos.contains(url) { result.videos.append(url) }
        }
    }

    static func dateFromMilliseconds(_ value: Int?) -> Date? {
        guard let value, value > 0 else { return nil }
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: Double(value) / 1000)
        }
        return Date(timeIntervalSince1970: Double(value))
    }

    static func dateFromUnix(_ value: Int?) -> Date? {
        guard let value, value > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(value))
    }

    static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let resultRange = Range(match.range(at: group), in: text) else { return nil }
        return String(text[resultRange])
    }

    static func allMatches(_ pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group, let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    /// 从正文提取 `#话题#`，去重并限制数量
    static func topics(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "#([^#\\s\\[\\]]{1,30})") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var result: [String] = []
        var seen = Set<String>()
        for match in regex.matches(in: text, range: range) {
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: text) else { continue }
            let topic = String(text[r])
                .trimmingCharacters(in: CharacterSet(charactersIn: "，。！？、,.!?#"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !topic.isEmpty, seen.insert(topic).inserted else { continue }
            result.append(topic)
            if result.count >= 12 { break }
        }
        return result
    }

    /// 从 `url_list` 这类数组中取最后（通常最大）一个
    static func lastURL(in value: Any?) -> URL? {
        guard let list = value as? [String], let last = list.last else {
            return httpsURL((value as? String))
        }
        return httpsURL(last)
    }
}
