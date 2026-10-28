import Foundation

/// 从 HTML 中切出内嵌 JSON（__INITIAL_STATE__ / js-initialData / _ROUTER_DATA）。
enum EmbeddedJSON {
    static func object(after marker: String, in html: String) -> [String: Any]? {
        guard let range = html.range(of: marker) else { return nil }
        let tail = html[range.upperBound...]
        guard let start = tail.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        guard let json = balanced(from: start, in: html) else { return nil }
        guard let value = parse(sanitize(json)) else { return nil }
        return value as? [String: Any]
    }

    static func object(inScriptID id: String, html: String) -> [String: Any]? {
        let patterns = [
            "<script id=\"\(id)\"[^>]*>",
            "<script id='\(id)'[^>]*>"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let tagRange = Range(match.range, in: html) else { continue }
            let tail = html[tagRange.upperBound...]
            guard let endRange = tail.range(of: "</script>") else { continue }
            let body = String(tail[..<endRange.lowerBound])
            if let start = body.firstIndex(of: "{"), let json = balanced(from: start, in: body) {
                if let value = parse(sanitize(json)) as? [String: Any] {
                    return value
                }
            }
        }
        return nil
    }

    /// 从 start 处的 { 或 [ 开始，按括号层级切出完整 JSON（正确处理字符串与转义）
    static func balanced(from start: String.Index, in text: String) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let ch = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"": inString = true
                case "{", "[": depth += 1
                case "}", "]":
                    depth -= 1
                    if depth == 0 {
                        let end = text.index(after: index)
                        return String(text[start..<end])
                    }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// 小红书的内嵌 JSON 含裸 undefined，先替换为 null
    static func sanitize(_ json: String) -> String {
        let scalars = Array(json.unicodeScalars)
        var output = String()
        output.reserveCapacity(json.count)
        var inString = false
        var escaped = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if inString {
                output.unicodeScalars.append(scalar)
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            if scalar == "\"" {
                inString = true
                output.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            if scalar == "u" {
                let end = index + 9
                if end <= scalars.count {
                    let slice = scalars[index..<end]
                    if slice.elementsEqual("undefined".unicodeScalars),
                       index == 0 || !isIdentifierScalar(scalars[index - 1]),
                       end >= scalars.count || !isIdentifierScalar(scalars[end]) {
                        output += "null"
                        index = end
                        continue
                    }
                }
            }
            output.unicodeScalars.append(scalar)
            index += 1
        }
        return output
    }

    private static func isIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$"
    }

    static func parse(_ json: String) -> Any? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

extension Dictionary where Key == String, Value == Any {
    func dict(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func array(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }

    func string(_ key: String) -> String? {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSNumber { return value.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? NSNumber { return value.intValue }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? NSNumber { return value.doubleValue }
        if let value = self[key] as? String { return Double(value) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        return nil
    }

    /// 逐级取值：dig("note", "video", "media")
    func dig(_ keys: String...) -> Any? {
        var current: Any? = self
        for key in keys {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[key]
        }
        return current
    }

    func digDict(_ keys: String...) -> [String: Any]? {
        dig(keys) as? [String: Any]
    }

    func digArray(_ keys: String...) -> [Any]? {
        dig(keys) as? [Any]
    }

    func digString(_ keys: String...) -> String? {
        dig(keys) as? String
    }
}

extension Array where Element == Any {
    func dict(at index: Int) -> [String: Any]? {
        guard indices.contains(index) else { return nil }
        return self[index] as? [String: Any]
    }
}
