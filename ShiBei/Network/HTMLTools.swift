import Foundation

enum HTMLTools {
    static func decode(data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let gb = String(data: data, encoding: gb18030) { return gb }
        return String(decoding: data, as: UTF8.self)
    }

    private static let blockTags = [
        "p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6",
        "blockquote", "tr", "section", "article", "figure", "figcaption"
    ]

    /// HTML → 纯文本，保留段落换行
    static func plainText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: "(?is)<(script|style|noscript)[^>]*>.*?</\\1>",
            with: "",
            options: .regularExpression
        )
        for tag in blockTags {
            text = text.replacingOccurrences(
                of: "(?i)</?\(tag)\\b[^>]*>",
                with: "\n",
                options: .regularExpression
            )
        }
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        var output = text

        // 数字实体 &#123;
        var rebuilt = String()
        var remaining = output[...]
        while let range = remaining.range(of: "&#[0-9]{2,6};", options: .regularExpression) {
            rebuilt += remaining[..<range.lowerBound]
            let digits = remaining[range.lowerBound...].dropFirst(2).dropLast()
            if let code = UInt32(digits), let scalar = Unicode.Scalar(code) {
                rebuilt.unicodeScalars.append(scalar)
            }
            remaining = remaining[range.upperBound...]
        }
        rebuilt += remaining
        output = rebuilt

        // 命名实体（&amp; 放最后，避免二次解码）
        let map: [String: String] = [
            "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&ldquo;": "“",
            "&rdquo;": "”", "&lsquo;": "‘", "&rsquo;": "’", "&hellip;": "…",
            "&mdash;": "—", "&ndash;": "–", "&middot;": "·"
        ]
        for (key, value) in map {
            output = output.replacingOccurrences(of: key, with: value)
        }
        output = output.replacingOccurrences(of: "&amp;", with: "&")
        return output
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let patterns = [
            "\(name)\\s*=\\s*\"([^\"]*)\"",
            "\(name)\\s*=\\s*'([^']*)'"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(tag.startIndex..., in: tag)
            if let match = regex.firstMatch(in: tag, range: range),
               match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: tag) {
                return String(tag[valueRange])
            }
        }
        return nil
    }

    /// 提取正文图片，优先原图属性
    static func imageURLs(in html: String) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()
        guard let regex = try? NSRegularExpression(pattern: "(?is)<img\\b[^>]*>") else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match, let tagRange = Range(match.range, in: html) else { return }
            let tag = String(html[tagRange])
            let candidates = [
                attribute("data-original", in: tag),
                attribute("data-actualsrc", in: tag),
                attribute("data-src", in: tag),
                attribute("data-lazy-src", in: tag),
                attribute("src", in: tag)
            ].compactMap { $0 }
            for candidate in candidates {
                guard var value = candidate.trimmingCharacters(in: .whitespacesAndNewlines).removingPercentEncoding,
                       !value.isEmpty,
                       !value.hasPrefix("data:") else { continue }
                if value.hasPrefix("//") { value = "https:" + value }
                guard let url = URL(string: value) else { continue }
                let key = url.absoluteString
                if seen.insert(key).inserted {
                    results.append(url)
                }
                break
            }
        }
        return results
    }

    /// 提取 og/meta 信息
    static func meta(in html: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "(?is)<meta\\b[^>]*>") else { return result }
        let range = NSRange(html.startIndex..., in: html)
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match, let tagRange = Range(match.range, in: html) else { return }
            let tag = String(html[tagRange])
            guard let key = attribute("property", in: tag) ?? attribute("name", in: tag),
                  let content = attribute("content", in: tag),
                  !content.isEmpty else { return }
            result[key.lowercased()] = content
        }
        return result
    }

    static func title(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<title[^>]*>(.*?)</title>") else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let titleRange = Range(match.range(at: 1), in: html) else { return nil }
        let title = plainText(from: String(html[titleRange]))
        return title.isEmpty ? nil : title
    }

    static func jsonLD(in html: String) -> [String: Any]? {
        guard let regex = try? NSRegularExpression(
            pattern: "(?is)<script[^>]+type=[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>"
        ) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let bodyRange = Range(match.range(at: 1), in: html) else { return nil }
        return EmbeddedJSON.parse(String(html[bodyRange])) as? [String: Any]
    }
}
