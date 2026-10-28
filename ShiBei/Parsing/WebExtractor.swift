import Foundation
import WebKit
import UIKit

/// 网页快照：由离屏 WKWebView 真实执行页面 JS 后采集。
struct WebCapture: Sendable {
    var finalURL: URL
    var title: String
    var text: String
    /// window.__INITIAL_STATE__ 的 JSON 字符串
    var initialState: String?
    /// <script id="js-initialData"> 的文本
    var initialData: String?
    /// <script id="RENDER_DATA"> 的原始文本（域名站点常见 URL 编码）
    var renderData: String?
    /// 页面内拦截到的 JSON 响应（按到达顺序）
    var responses: [String]
    var videoSources: [String]
    var imageSources: [String]
}

/// 离屏网页提取器。
///
/// 很多平台的分享页已经改成纯客户端渲染：HTML 里没有媒体数据，
/// 数据由页面自己的 JS 调用「带签名」的接口取回。这里不逆向签名，
/// 而是让页面在 WKWebView 里正常运行，注入脚本 hook `fetch` / `XMLHttpRequest`，
/// 把页面自己拿到的 JSON 原样截获，再交给解析器。
final class WebExtractor: Sendable {
    static let shared = WebExtractor()

    private init() {}

    @MainActor
    func capture(
        url: URL,
        userAgent: String = UserAgent.iphone,
        timeout: TimeInterval = 22,
        shouldFinish: @escaping @Sendable ([String]) -> Bool = { _ in false }
    ) async throws -> WebCapture {
        let session = WebSession()
        defer { session.teardown() }

        session.start(url: url, userAgent: userAgent)
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        var snapshot: [String: Any] = [:]
        var sawRelevant = false

        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(600))

            if let json = await session.snapshotJSON(),
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               !dict.isEmpty {
                snapshot = dict
            }

            if shouldFinish(session.responses) {
                sawRelevant = true
                break
            }

            // 页面把数据写进了全局（小红书 SSR），不必再等网络请求
            let hasEmbeddedState = (snapshot["initialState"] as? String)?.isEmpty == false
                || (snapshot["initialData"] as? String)?.isEmpty == false
            if hasEmbeddedState, Date().timeIntervalSince(start) > 3 {
                break
            }

            // 页面已加载但确实没有任何网络数据，不必耗满超时
            if Date().timeIntervalSince(start) > 8,
               snapshot["title"] != nil,
               session.responses.isEmpty {
                break
            }
        }

        let responses = session.responses
        guard !snapshot.isEmpty || !responses.isEmpty || sawRelevant else {
            throw ParseError.upstream("网页渲染超时，未取到任何数据")
        }

        return WebCapture(
            finalURL: session.currentURL ?? url,
            title: snapshot["title"] as? String ?? "",
            text: snapshot["text"] as? String ?? "",
            initialState: snapshot["initialState"] as? String,
            initialData: snapshot["initialData"] as? String,
            renderData: snapshot["renderData"] as? String,
            responses: responses,
            videoSources: (snapshot["videos"] as? [String]) ?? [],
            imageSources: (snapshot["images"] as? [String]) ?? []
        )
    }
}

// MARK: - 单次网页会话

@MainActor
private final class WebSession: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private(set) var responses: [String] = []
    private(set) var currentURL: URL?
    private let webView: WKWebView
    private let controller: WKUserContentController
    private weak var hostWindow: UIWindow?

    override init() {
        // 两阶段初始化：stored property 必须在 super.init() 之前赋值，
        // 且在此之前不能通过 self 读取属性，所以先建局部变量。
        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = contentController
        let webView = WKWebView(
            frame: CGRect(x: -2000, y: -2000, width: 390, height: 844),
            configuration: configuration
        )

        self.controller = contentController
        self.webView = webView
        super.init()

        contentController.add(self, name: "capture")
        contentController.addUserScript(
            WKUserScript(
                source: Self.injectionScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.alpha = 0.01
    }

    func start(url: URL, userAgent: String) {
        webView.customUserAgent = userAgent
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: { !$0.isHidden }) ?? scene.windows.first {
            hostWindow = window
            window.addSubview(webView)
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        webView.load(request)
    }

    func teardown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        controller.removeAllScriptMessageHandlers()
        controller.removeAllUserScripts()
        webView.removeFromSuperview()
    }

    func snapshotJSON() async -> String? {
        let script = "window.__shibei_snapshot ? window.__shibei_snapshot() : '{}'"
        let value = try? await webView.evaluateJavaScript(script)
        return value as? String
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "capture",
              let payload = message.body as? [String: Any],
              let body = payload["body"] as? String,
              body.count > 40 else { return }

        let url = payload["url"] as? String ?? ""
        // 只保留可能是内容数据的响应，避免堆内存
        let looksRelevant = ["aweme", "note", "answer", "status", "article", "bbs", "feed"]
            .contains { url.lowercased().contains($0) }
            || body.contains("\"aweme_id\"")
            || body.contains("\"play_addr\"")
            || body.contains("noteDetailMap")
        guard looksRelevant else { return }

        responses.append(body)
        if responses.count > 12 {
            responses.removeFirst(responses.count - 12)
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        currentURL = webView.url
    }

    // MARK: 注入脚本

    private static let injectionScript = #"""
    (function () {
      if (window.__shibei_hooked) { return; }
      window.__shibei_hooked = true;

      function send(url, body) {
        try {
          if (!body) { return; }
          window.webkit.messageHandlers.capture.postMessage({
            url: String(url || ''),
            body: String(body).slice(0, 1500000)
          });
        } catch (e) { }
      }

      var originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function () {
          var args = arguments;
          var request = args[0];
          var url = (request && request.url) ? request.url : request;
          var promise = originalFetch.apply(this, args);
          promise.then(function (response) {
            try {
              var type = (response.headers.get('content-type') || '');
              if (type.indexOf('json') >= 0 || String(url).indexOf('/aweme/') >= 0) {
                response.clone().text().then(function (text) { send(url, text); });
              }
            } catch (e) { }
          }).catch(function () { });
          return promise;
        };
      }

      var originalOpen = XMLHttpRequest.prototype.open;
      var originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__shibei_url = url;
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        var xhr = this;
        xhr.addEventListener('load', function () {
          try {
            var type = xhr.getResponseHeader('content-type') || '';
            if (type.indexOf('json') >= 0 || String(xhr.__shibei_url).indexOf('/aweme/') >= 0) {
              send(xhr.__shibei_url, xhr.responseText);
            }
          } catch (e) { }
        });
        return originalSend.apply(this, arguments);
      };

      window.__shibei_snapshot = function () {
        var out = {};
        try { out.initialState = window.__INITIAL_STATE__ ? JSON.stringify(window.__INITIAL_STATE__) : null; } catch (e) { out.initialState = null; }
        try {
          var el = document.getElementById('js-initialData');
          out.initialData = el ? el.textContent : null;
        } catch (e) { out.initialData = null; }
        try {
          var rd = document.getElementById('RENDER_DATA');
          out.renderData = rd ? rd.textContent : null;
        } catch (e) { out.renderData = null; }
        try { out.title = document.title || ''; } catch (e) { out.title = ''; }
        try { out.text = document.body ? document.body.innerText.slice(0, 30000) : ''; } catch (e) { out.text = ''; }
        try {
          out.videos = Array.prototype.slice.call(document.querySelectorAll('video'))
            .map(function (v) { return v.currentSrc || v.src || ''; })
            .filter(function (s) { return s.length > 0; });
        } catch (e) { out.videos = []; }
        try {
          out.images = Array.prototype.slice.call(document.querySelectorAll('img'))
            .map(function (i) { return i.currentSrc || i.src || ''; })
            .filter(function (s) { return s.length > 0 && s.indexOf('data:') !== 0; })
            .slice(0, 80);
        } catch (e) { out.images = []; }
        return JSON.stringify(out);
      };
    })();
    """#
}
