import Foundation

enum UserAgent {
    static let iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    static let ipad = "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    static let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    static let android = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"
}

/// 记录 302 链路，短链解析必须拿到中间地址。
final class RedirectCatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var chain: [URL] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let url = request.url {
            lock.lock(); storage.append(url); lock.unlock()
        }
        completionHandler(request)
    }
}

final class HTTPClient: @unchecked Sendable {
    static let shared = HTTPClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    func request(
        _ url: URL,
        headers: [String: String] = [:],
        referer: String? = nil,
        method: String = "GET"
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(UserAgent.iphone, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw ParseError.blocked("平台返回 HTTP \(http.statusCode)")
            }
            return (data, response)
        } catch let error as ParseError {
            throw error
        } catch {
            throw ParseError.upstream(error.localizedDescription)
        }
    }

    /// 跟随重定向并返回最终地址 + 内容
    func follow(
        _ url: URL,
        headers: [String: String] = [:],
        referer: String? = nil
    ) async throws -> (finalURL: URL, body: Data, response: URLResponse) {
        let catcher = RedirectCatcher()
        var request = self.request(url, headers: headers, referer: referer)
        request.setValue(UserAgent.iphone, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request, delegate: catcher)
            let final = catcher.chain.last ?? response.url ?? url
            return (final, data, response)
        } catch {
            throw ParseError.upstream(error.localizedDescription)
        }
    }

    func string(
        _ url: URL,
        headers: [String: String] = [:],
        referer: String? = nil
    ) async throws -> String {
        let (data, _) = try await data(for: request(url, headers: headers, referer: referer))
        return HTMLTools.decode(data: data)
    }

    func decoded(
        _ url: URL,
        headers: [String: String] = [:],
        referer: String? = nil
    ) async throws -> (String, URL) {
        let result = try await follow(url, headers: headers, referer: referer)
        return (HTMLTools.decode(data: result.body), result.finalURL)
    }

    /// 访问首页以获取平台 cookie（微博等接口需要）
    func warmUp(_ url: URL, headers: [String: String] = [:]) async {
        _ = try? await string(url, headers: headers, referer: url.absoluteString)
    }

    func json(
        _ url: URL,
        headers: [String: String] = [:],
        referer: String? = nil
    ) async throws -> Any {
        var merged = headers
        merged["Accept"] = merged["Accept"] ?? "application/json, text/plain, */*"
        let text = try await string(url, headers: merged, referer: referer)
        guard let object = EmbeddedJSON.parse(text) else {
            throw ParseError.badResponse
        }
        return object
    }
}
