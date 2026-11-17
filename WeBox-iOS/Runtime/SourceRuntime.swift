import Foundation
import WebKit

@MainActor
final class SourceRuntime: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var continuations: [String: CheckedContinuation<Any, Error>] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var network: [String: Task<Void, Never>] = [:]
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private let namespace: String
    private var permitsHTTP = false
    private let session: URLSession

    init(namespace: String, session: URLSession? = nil) {
        self.namespace = namespace
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: config)
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let content = configuration.userContentController
        content.add(WeakScriptHandler(self), name: "rpc")
        content.add(WeakScriptHandler(self), name: "result")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }
    func close() {
        for task in network.values { task.cancel() }; network.removeAll()
        for task in timers.values { task.cancel() }; timers.removeAll()
        let pending = continuations.values; continuations.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
        loadContinuation?.resume(throwing: CancellationError()); loadContinuation = nil
        webView.stopLoading()
        session.invalidateAndCancel()
    }
    func load(script: String) async throws -> [String: Any] {
        guard script.utf8.count <= 4 * 1024 * 1024 else { throw WeBoxError("源文件超过 4 MB") }
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.loadHTMLString("<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; connect-src 'none'\"></head><body></body></html>", baseURL: nil)
        }
        let bridgeURL = Bundle.main.url(forResource: "bridge", withExtension: "js")!
        try await webView.evaluateJavaScript(String(contentsOf: bridgeURL, encoding: .utf8))
        try await webView.evaluateJavaScript(script)
        let metadata = try await invoke("metadata") as? [String: Any] ?? [:]
        permitsHTTP = metadata["allowHttp"] as? Bool ?? false
        let requirements = metadata["requires"] as? [String] ?? []
        let unsupported = requirements.filter { !["crypto", "cencMp4"].contains($0) }
        guard unsupported.isEmpty else { throw WeBoxError("此源需要暂不支持的接口：" + unsupported.joined(separator: ", ")) }
        return metadata
    }
    func invoke(_ method: String, _ request: [String: Any] = [:]) async throws -> Any {
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[id] = continuation
                timers[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) } catch { return }
                    self?.cancel(id, error: WeBoxError("源请求超过 90 秒，请重试"))
                }
                do {
                    let args = try Self.json([id, method, request])
                    webView.evaluateJavaScript("__invoke(...\(args)); void 0") { [weak self] _, error in
                        if let error { self?.finish(id, result: .failure(error)) }
                    }
                } catch { finish(id, result: .failure(error)) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel(id, error: CancellationError()) } }
    }
    private func cancel(_ id: String, error: Error) {
        webView.evaluateJavaScript("__cancel(\(Self.quote(id)))")
        for (key, task) in network where key.hasPrefix(id + ":") { task.cancel() }
        finish(id, result: .failure(error))
    }
    private func finish(_ id: String, result: Result<Any, Error>) {
        timers.removeValue(forKey: id)?.cancel()
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }
    static func json(_ value: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), encoding: .utf8)!
    }
    static func quote(_ value: String) -> String { (try? json(value)) ?? "\"\"" }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume(); loadContinuation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error); loadContinuation = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error); loadContinuation = nil
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let error = WeBoxError("源运行进程已结束，请重新选择源")
        loadContinuation?.resume(throwing: error); loadContinuation = nil
        for id in Array(continuations.keys) { finish(id, result: .failure(error)) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard prompt == "webox.native", frame.isMainFrame, let data = defaultText?.data(using: .utf8) else { completionHandler(nil); return }
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WeBoxError("桥接参数错误") }
            let value = try SourceCrypto.invoke(request)
            completionHandler(try Self.json(["ok": true, "value": value]))
        } catch { completionHandler(try? Self.json(["ok": false, "error": error.localizedDescription])) }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let id = body["id"] as? String else { return }
        if message.name == "result" {
            if body["ok"] as? Bool == true { finish(id, result: .success(body["value"] ?? NSNull())) }
            else { finish(id, result: .failure(WeBoxError(body["error"] as? String ?? "源运行失败"))) }
            return
        }
        let operation = body["operation"] as? String ?? ""
        guard continuations[operation] != nil else { return }
        let key = operation + ":" + id
        network[key] = Task { [weak self] in
            guard let self else { return }
            defer { self.network.removeValue(forKey: key) }
            let reply: [String: Any]
            do { reply = ["ok": true, "value": try await self.handle(body)] }
            catch { reply = ["ok": false, "error": error.localizedDescription] }
            guard !Task.isCancelled, self.continuations[operation] != nil else { return }
            if let json = try? Self.json(reply) { self.webView.evaluateJavaScript("__reply(\(Self.quote(id)),\(json)); void 0", completionHandler: nil) }
        }
    }
    private func handle(_ body: [String: Any]) async throws -> Any {
        let method = body["method"] as? String ?? ""
        let args = body["args"] as? [String: Any] ?? [:]
        let key = "webox.source.\(namespace).\(args["key"] as? String ?? "")"
        switch method {
        case "store.get":
            guard let data = UserDefaults.standard.data(forKey: key) else { return NSNull() }
            return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        case "store.set":
            let data = try JSONSerialization.data(withJSONObject: args["value"] ?? NSNull(), options: .fragmentsAllowed)
            guard data.count < 1024 * 1024 else { throw WeBoxError("源缓存超过上限") }
            UserDefaults.standard.set(data, forKey: key); return NSNull()
        case "store.remove": UserDefaults.standard.removeObject(forKey: key); return NSNull()
        case "http":
            guard let raw = args["url"] as? String, let url = URL(string: raw), url.host != nil,
                  url.user == nil, url.password == nil, url.scheme == "https" || permitsHTTP && url.scheme == "http" else { throw WeBoxError("源请求地址无效或未允许 HTTP") }
            let options = args["options"] as? [String: Any] ?? [:]
            let limit = min(max(options["maxResponseBytes"] as? Int ?? 2_097_152, 1), 8_388_608)
            let timeout = min(max((options["timeoutMs"] as? Double ?? 12000) / 1000, 1), 45)
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = args["verb"] as? String ?? "GET"
            for (name, value) in options["headers"] as? [String: String] ?? [:] { request.setValue(value, forHTTPHeaderField: name) }
            if let bytes = options["bytes"] as? String { request.httpBody = try SourceCrypto.decode(bytes, "base64") }
            else if let json = options["json"] { request.httpBody = try JSONSerialization.data(withJSONObject: json); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            else if let text = options["body"] as? String { request.httpBody = Data(text.utf8) }
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.url?.scheme == "https" || permitsHTTP && http.url?.scheme == "http" else { throw WeBoxError("无效的 HTTP 响应") }
            if response.expectedContentLength > limit { throw WeBoxError("源响应超过大小上限") }
            var data = Data()
            for try await byte in bytes { if data.count >= limit { throw WeBoxError("源响应超过大小上限") }; data.append(byte) }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields { headers[String(describing: k).lowercased()] = String(describing: v) }
            let type = options["responseType"] as? String ?? "text"
            let result: Any
            if type == "base64" { result = data.base64EncodedString() }
            else if type == "json" { result = try JSONSerialization.jsonObject(with: data) }
            else { result = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self) }
            return ["status": http.statusCode, "headers": headers, "data": result, "url": http.url?.absoluteString ?? raw]
        default: throw WeBoxError("不支持的源接口：\(method)")
        }
    }
}

@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: SourceRuntime?
    init(_ target: SourceRuntime) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
