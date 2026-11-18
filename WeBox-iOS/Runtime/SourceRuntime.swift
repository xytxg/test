import Foundation
import WebKit
import Network

actor InvocationGate {
    private var locked = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func acquire() async { if !locked { locked = true; return }; await withCheckedContinuation { waiting.append($0) } }
    func release() { if waiting.isEmpty { locked = false } else { waiting.removeFirst().resume() } }
}

@MainActor
final class SourceRuntime: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var continuations: [String: CheckedContinuation<Any, Error>] = [:]
    private var operationNames: [String: String] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var network: [String: Task<Void, Never>] = [:]
    private var networkFailures: [String: [HTTPNetworkError]] = [:]
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var loadTimer: Task<Void, Never>?
    private var evaluationContinuation: CheckedContinuation<Void, Error>?
    private var evaluationTimer: Task<Void, Never>?
    private let namespace: String
    private var permitsHTTP = true
    private var closed = false
    private let client: HTTPClient
    private let proxyClient: HTTPClient?
    private let sourceProxy: SourceHTTPSProxy?
    private let useSurgeVIF: Bool
    private let gate = InvocationGate()
    init(namespace: String, client: HTTPClient = HTTPClient(), sourceProxy: SourceHTTPSProxy? = nil, useSurgeVIF: Bool = false) {
        self.namespace = namespace; self.client = client
        self.sourceProxy = sourceProxy
        self.proxyClient = sourceProxy?.makeClient()
        self.useSurgeVIF = useSurgeVIF
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let content = configuration.userContentController
        content.add(WeakScriptHandler(self), name: "rpc"); content.add(WeakScriptHandler(self), name: "result")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        webView.uiDelegate = self; webView.navigationDelegate = self
    }
    func close() {
        guard !closed else { return }; closed = true
        for task in network.values { task.cancel() }; network.removeAll(); networkFailures.removeAll()
        for task in timers.values { task.cancel() }; timers.removeAll(); loadTimer?.cancel(); evaluationTimer?.cancel()
        evaluationContinuation?.resume(throwing: CancellationError()); evaluationContinuation = nil
        let pending = Array(continuations.values); continuations.removeAll(); operationNames.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
        loadContinuation?.resume(throwing: CancellationError()); loadContinuation = nil
        let view = webView; webView = nil
        view?.stopLoading(); view?.uiDelegate = nil; view?.navigationDelegate = nil
        view?.configuration.userContentController.removeAllScriptMessageHandlers()
        client.close()
        proxyClient?.close()
    }
    func load(script: String, settings: [String: Any] = [:], hint: String = "source") async throws -> [String: Any] {
        guard script.utf8.count <= ScriptDocument.limit else { throw WeBoxError("源文件超过 8 MB") }
        do {
            try await withCheckedThrowingContinuation { continuation in
                loadContinuation = continuation
                loadTimer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    self?.finishLoad(WeBoxError("源引擎初始化超时，请重试"))
                }
                webView.loadHTMLString("<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; worker-src blob:; frame-src 'self' about: blob: data:; connect-src 'none'\"></head><body></body></html>", baseURL: nil)
            }
            try await evaluate(resource: "bridge")
            let worker = try resource("compute-worker")
            _ = try await webView.evaluateJavaScript("globalThis.__computeWorkerSource=\(Self.quote(worker)); void 0")
            for name in ["sdk-cheerio", "sdk-cryptojs", "sdk-widget", "sdk-webox", "sdk-xptv", "source-adapter"] { try await evaluate(resource: name) }
            guard !closed else { throw CancellationError() }
            _ = try await webView.evaluateJavaScript("__configureHost(\(try Self.json(settings)),\(Self.quote(hint))); void 0")
            try await evaluateUserScript(script)
            let metadata = try await invoke("metadata") as? [String: Any] ?? [:]
            permitsHTTP = metadata["allowHttp"] as? Bool ?? true
            let requirements = metadata["requires"] as? [String] ?? []
            let supported = ["html","crypto","compute","dom","binary","audio","imageDecoder","cencMp4"]
            let unsupported = requirements.filter { !supported.contains($0) }
            guard unsupported.isEmpty else { throw WeBoxError("已识别此源，但当前 iOS 运行器尚不支持：" + unsupported.joined(separator: "、")) }
            return metadata
        } catch { throw Self.scriptError(error) }
    }
    private func resource(_ name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { throw WeBoxError("应用资源缺失：\(name).js") }
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func evaluate(resource name: String) async throws { guard !closed else { throw CancellationError() }; _ = try await webView.evaluateJavaScript(resource(name)) }
    private func evaluateUserScript(_ script: String) async throws {
        guard !closed else { throw CancellationError() }
        try await withCheckedThrowingContinuation { continuation in
            evaluationContinuation = continuation
            evaluationTimer = Task { [weak self] in
                do { try await Task.sleep(for:.seconds(12)) } catch { return }
                self?.finishEvaluation(WeBoxError("脚本初始化超过 12 秒，可能含有阻塞的顶层代码"))
            }
            webView.evaluateJavaScript(script) { [weak self] _, error in self?.finishEvaluation(error) }
        }
    }
    private func finishEvaluation(_ error: Error?) {
        evaluationTimer?.cancel(); evaluationTimer = nil
        let pending = evaluationContinuation; evaluationContinuation = nil
        if let error { pending?.resume(throwing:error) } else { pending?.resume() }
    }
    func invoke(_ method: String, _ request: [String: Any] = [:]) async throws -> Any {
        await gate.acquire(); defer { Task { await gate.release() } }
        try Task.checkCancellation(); guard !closed else { throw CancellationError() }
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[id] = continuation
                operationNames[id] = method
                timers[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(75)) } catch { return }
                    self?.cancel(id, error: WeBoxError("源请求超过 75 秒，请重试或切换源"))
                }
                do {
                    let args = try Self.json([id, method, request])
                    webView.evaluateJavaScript("__invoke(...\(args)); void 0") { [weak self] _, error in
                        if let error { self?.finish(id, result: .failure(Self.scriptError(error))) }
                    }
                } catch { finish(id, result: .failure(error)) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel(id, error: CancellationError()) } }
    }
    private func cancel(_ id: String, error: Error) {
        guard !closed else { return }
        webView.evaluateJavaScript("__cancel(\(Self.quote(id)))", completionHandler: nil)
        for (key, task) in network where key.hasPrefix(id + ":") { task.cancel() }; finish(id, result: .failure(error))
    }
    private func finish(_ id: String, result: Result<Any, Error>) {
        timers.removeValue(forKey: id)?.cancel()
        networkFailures.removeValue(forKey: id)
        operationNames.removeValue(forKey: id)
        for (key, task) in network where key.hasPrefix(id + ":") { task.cancel() }
        guard let continuation = continuations.removeValue(forKey: id) else { return }; continuation.resume(with: result)
    }
    static func json(_ value: Any) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), encoding: .utf8)! }
    static func quote(_ value: String) -> String { (try? json(value)) ?? "\"\"" }
    static func scriptError(_ error: Error) -> Error {
        let info = (error as NSError).userInfo
        if let message = info["WKJavaScriptExceptionMessage"] as? String {
            let line = info["WKJavaScriptExceptionLineNumber"] as? Int
            return WeBoxError("脚本\(line.map { "第 \($0) 行" } ?? "")：\(message)")
        }; return error
    }
    private func finishLoad(_ error: Error? = nil) {
        loadTimer?.cancel(); loadTimer = nil
        let continuation = loadContinuation; loadContinuation = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoad(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoad(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let error = WeBoxError("源运行进程已结束，请重试")
        finishLoad(error); for id in Array(continuations.keys) { finish(id, result: .failure(error)) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard prompt == "webox.native", frame.isMainFrame, let data = defaultText?.data(using: .utf8) else { completionHandler(nil); return }
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any], let method = request["method"] as? String else { throw WeBoxError("桥接参数错误") }
            let value = try handleSync(method, request["params"] as? [String: Any] ?? [:])
            completionHandler(try Self.json(["ok": true, "value": value]))
        } catch { completionHandler(try? Self.json(["ok": false, "error": error.localizedDescription])) }
    }
    private func handleSync(_ method: String, _ p: [String: Any]) throws -> Any {
        if method.hasPrefix("crypto.") || method == "code.decode" { return try SDKCrypto.call(method, p) }
        let key = "webox.source.\(namespace).\(p["key"] as? String ?? "")"
        switch method {
        case "native.store.get", "storage.getItem":
            guard let data = UserDefaults.standard.data(forKey: key) else { return NSNull() }; return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        case "native.store.set", "storage.setItem":
            let data = try JSONSerialization.data(withJSONObject: p["value"] ?? NSNull(), options: .fragmentsAllowed)
            guard data.count <= 1048576 else { throw WeBoxError("源存储单条超过 1 MB") }; UserDefaults.standard.set(data, forKey: key); return NSNull()
        case "native.store.remove", "storage.removeItem": UserDefaults.standard.removeObject(forKey: key); return NSNull()
        case "storage.clear": for k in UserDefaults.standard.dictionaryRepresentation().keys where k.hasPrefix("webox.source.\(namespace).") { UserDefaults.standard.removeObject(forKey: k) }; return NSNull()
        case "storage.keys": return UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("webox.source.\(namespace).") }.map { String($0.dropFirst("webox.source.\(namespace).".count)) }
        default: throw WeBoxError("当前运行器尚未支持：" + method)
        }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !closed, message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let id = body["id"] as? String else { return }
        if message.name == "result" {
            if body["ok"] as? Bool == true { finish(id, result: .success(body["value"] ?? NSNull())) }
            else {
                var message = body["error"] as? String ?? "源运行失败"
                if let start = message.range(of: "WBX_ERROR:"), let data = String(message[start.upperBound...]).data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { message = (value["message"] as? String ?? message) }
                let networkFailure = networkFailures[id]?.last { $0.localizedDescription == message }
                finish(id, result: .failure(networkFailure.map { $0 as Error } ?? WeBoxError(message)))
            }; return
        }
        let operation = body["operation"] as? String ?? ""
        guard continuations[operation] != nil else { return }
        let key = operation + ":" + id
        network[key] = Task { [weak self] in
            guard let self else { return }; defer { self.network.removeValue(forKey: key) }
            let reply: [String: Any]
            do { reply = ["ok":true,"value":try await self.handleAsync(body)] }
            catch {
                if let failure = error as? HTTPNetworkError, !Task.isCancelled, self.continuations[operation] != nil {
                    // JS receives a normal Error and can catch it as usual. Keep
                    // the typed original for a failure it propagates to the UI.
                    var recent = self.networkFailures[operation] ?? []
                    recent.append(failure)
                    self.networkFailures[operation] = Array(recent.suffix(8))
                }
                reply = ["ok":false,"error":error.localizedDescription]
            }
            guard !Task.isCancelled, self.continuations[operation] != nil else { return }
            if let json = try? Self.json(reply) { self.webView.evaluateJavaScript("__reply(\(Self.quote(id)),\(json)); void 0", completionHandler: nil) }
        }
    }
    private func handleAsync(_ body: [String: Any]) async throws -> Any {
        guard body["method"] as? String == "request" else { throw WeBoxError("源使用了尚未支持的异步接口") }
        let p = body["args"] as? [String: Any] ?? [:]
        guard let raw = p["url"] as? String, var components = URLComponents(string: raw) else { throw WeBoxError("请求 URL 无效") }
        if let query = p["params"] as? [String: Any], !query.isEmpty {
            // Append without decoding and re-encoding the existing (possibly signed) query.
            let encoded = query.keys.sorted().map { name in
                Self.queryEncode(name) + "=" + Self.queryEncode(Self.queryString(query[name] ?? NSNull()))
            }.joined(separator: "&")
            let original = components.percentEncodedQuery ?? ""
            components.percentEncodedQuery = original.isEmpty ? encoded : original + "&" + encoded
        }
        guard let url = components.url else { throw WeBoxError("请求 URL 无效") }
        var request = URLRequest(url: url, timeoutInterval: min(60,max(1,p["timeout"] as? Double ?? 18)))
        let method = (p["method"] as? String ?? "GET").uppercased()
        guard ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"].contains(method) else {
            throw WeBoxError("源请求使用了不支持的 HTTP 方法")
        }
        request.httpMethod = method
        for (name,value) in p["headers"] as? [String:String] ?? [:] { guard !name.contains("\n"),!value.contains("\r"),!value.contains("\n") else { throw WeBoxError("请求头格式无效") }; request.setValue(value, forHTTPHeaderField: name) }
        if let body = p["bodyBase64"] as? String { request.httpBody = try SourceCrypto.decode(body, "base64") }
        else if let text = p["data"] as? String { request.httpBody = Data(text.utf8) }
        else if let data = p["data"], !(data is NSNull) { request.httpBody = try JSONSerialization.data(withJSONObject: data) }
        let limit = min(8_388_608, max(1, p["maxResponseBytes"] as? Int ?? 4_194_304))
        let httpsOnly = !permitsHTTP || p["httpsOnly"] as? Bool == true
        if method == "GET" || method == "HEAD" { request.httpBody = nil }
        let operation = operationNames[body["operation"] as? String ?? ""] ?? "source"
        let log = SourceRequestLog.shared
        let ticket = log.begin(request, operation: operation)
        let started = ContinuousClock.now
        let result: HTTPResult
        do {
            result = try await fetchSource(request, limit: limit, httpsOnly: httpsOnly,
                                           redirects: p["allow_redirects"] as? Bool != false, ticket: ticket)
            let elapsed = started.duration(to: .now).components
            let milliseconds = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
            let stages = result.trace?.summary ?? ""
            let finalHost = result.response.url?.host
            let destination = finalHost != request.url?.host ? finalHost.map { " → " + $0 } ?? "" : ""
            log.append(ticket, "HTTP \(result.response.statusCode)\(destination) · \(milliseconds) ms" + (stages.isEmpty ? "" : " · " + stages))
        } catch {
            if let network = error as? HTTPNetworkError {
                let stages = network.trace?.summary ?? ""
                let stageText = stages.isEmpty ? "系统未返回阶段信息" : stages
                log.append(ticket, "iOS \(network.code.rawValue) · " + stageText)
                if let detail = network.recoveryResult { log.append(ticket, detail) }
            } else if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                log.append(ticket, "已取消")
            } else {
                log.append(ticket, "请求未完成")
            }
            throw error
        }
        let data = p["zlibMode"] as? Bool == true && result.data.starts(with: [0x1f, 0x8b])
            ? try SDKCrypto.gunzip(result.data, limit: limit) : result.data
        let value: Any
        if p["base64Data"] as? Bool == true { value = data.base64EncodedString() }
        else if p["decodable"] as? Bool != false, let json = try? JSONSerialization.jsonObject(with: data) { value = json }
        else { value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? "" }
        var headers: [String:String] = [:]; for (key,value) in result.response.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
        return ["statusCode":result.response.statusCode,"headers":headers,"data":value,"url":result.response.url?.absoluteString ?? raw]
    }

    private static func queryEncode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func queryString(_ value: Any) -> String {
        if let string = value as? String { return string }
        if value is NSNull { return "" }
        if let json = try? Self.json(value) { return json }
        return ""
    }

    private func fetchSource(_ request: URLRequest, limit: Int, httpsOnly: Bool,
                             redirects: Bool, ticket: String) async throws -> HTTPResult {
        let log = SourceRequestLog.shared
        if let proxyClient, let sourceProxy, let url = request.url, url.scheme == "https" {
            log.append(ticket, sourceProxy.routeName)
            do {
                return try await proxyClient.fetch(request, limit: limit, httpsOnly: true, followRedirects: redirects)
            } catch var error as HTTPNetworkError {
                if [.badURL, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .timedOut, .userAuthenticationRequired].contains(error.code) {
                    error.recoveryResult = await sourceProxy.diagnose(target: url)
                    try Task.checkCancellation()
                } else {
                    error.recoveryResult = "当前线路为" + sourceProxy.routeName + "。"
                }
                throw error
            }
        }
        if useSurgeVIF, request.url?.scheme == "https", let host = request.url?.host {
            log.append(ticket, "Surge VPN 接管 · 查询虚拟地址")
            let addresses: [NWEndpoint.Host]
            do {
                addresses = try await SurgeVIFDNS.resolve(host)
            } catch {
                try Task.checkCancellation()
                throw HTTPNetworkError(code: .dnsLookupFailed, host: host, cellularDenied: false,
                                       recoveryResult: "Surge 未返回虚拟地址。请确认 Surge VPN 正在运行。")
            }
            log.append(ticket, "Surge DNS 返回 \(addresses.count) 个虚拟地址")
            return try await connectResolved(request, limit: limit, addresses: addresses, host: host)
        }

        log.append(ticket, "系统线路")
        do {
            return try await client.fetch(request, limit: limit, httpsOnly: httpsOnly, followRedirects: redirects)
        } catch var failure as HTTPNetworkError {
            guard failure.isResolutionFailure, failure.canUseAlternateDNS,
                  UserDefaults.standard.bool(forKey: AlternateDNS.preferenceKey),
                  request.url?.scheme == "https", let host = request.url?.host else { throw failure }
            log.append(ticket, "系统解析失败（\(failure.code.rawValue)），查询备用 DNS")
            let addresses: [NWEndpoint.Host]
            do {
                addresses = try await AlternateDNS.resolve(host)
            } catch {
                try Task.checkCancellation()
                failure.recoveryResult = "备用 DNS 查询失败。"
                throw failure
            }
            log.append(ticket, "备用 DNS 返回 \(addresses.count) 个地址")
            return try await connectResolved(request, limit: limit, addresses: addresses, host: host)
        }
    }

    private func connectResolved(_ request: URLRequest, limit: Int, addresses: [NWEndpoint.Host],
                                 host: String) async throws -> HTTPResult {
        do {
            return try await AlternateDNS.fetch(request, limit: limit, addresses: addresses)
        } catch let error as ResolvedConnectionError {
            throw HTTPNetworkError(code: error.code, host: host, cellularDenied: error.cellularDenied,
                                   recoveryResult: error.phase, trace: error.trace)
        }
    }

}
@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: SourceRuntime?
    init(_ target: SourceRuntime) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { target?.userContentController(controller, didReceive: message) }
}
