import Foundation

enum LinkExtractor {
    private static let urlPattern = "https?://[A-Za-z0-9\\-._~:/?#\\[\\]@!$&'()*+,;=%]+"

    static func urls(in text: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var results: [URL] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let urlRange = Range(match.range, in: text) else { return }
            var raw = String(text[urlRange])
            raw = trimTrailingPunctuation(raw)
            guard let url = URL(string: raw), let host = url.host, host.contains(".") else { return }
            if seen.insert(raw).inserted {
                results.append(url)
            }
        }
        return results
    }

    /// 分享文案里通常只有一个有效链接；优先返回已知平台链接
    static func bestLink(in text: String) -> URL? {
        let all = urls(in: text)
        if let known = all.first(where: { Platform.detect(from: $0) != nil && Platform.detect(from: $0) != .web }) {
            return known
        }
        return all.first
    }

    private static func trimTrailingPunctuation(_ value: String) -> String {
        var result = value
        let trailing = CharacterSet(charactersIn: ".,;:!?)]}>,，。！？；：、）】」』”’…")
        while let last = result.unicodeScalars.last, trailing.contains(last) {
            result.removeLast()
        }
        return result
    }
}
