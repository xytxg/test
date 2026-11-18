import Foundation
import SwiftUI

enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    var any: Any {
        switch self { case .string(let v): return v; case .number(let v): return v; case .bool(let v): return v; case .object(let v): return v.mapValues(\.any); case .array(let v): return v.map(\.any); case .null: return NSNull() }
    }
    var text: String {
        switch self { case .string(let v): return v; case .number(let v): return v.rounded() == v ? String(format: "%.0f", v) : String(v); case .bool(let v): return String(v); default: return "" }
    }
}
struct FieldCondition: Codable, Hashable { var key: String; var equals: JSONValue?; var oneOf: [JSONValue]? }
struct SourceField: Codable, Identifiable, Hashable {
    var key: String; var label: String; var type: String
    var `default`: JSONValue?
    var required: Bool?; var help: String?; var placeholder: String?; var sensitive: Bool?
    var min: Double?; var max: Double?; var step: Double?; var maxLength: Int?
    var options: [FilterOption]?
    var showWhen: FieldCondition?
    var id: String { key }
    func visible(in values: [String: JSONValue]) -> Bool {
        guard let condition = showWhen else { return true }
        return (condition.oneOf ?? condition.equals.map { [$0] } ?? []).contains(values[condition.key] ?? .null)
    }
}
struct SourceManifest: Codable, Hashable {
    var id: String; var name: String; var version: String; var api: String
    var format: String; var category: String; var icon: String?
    var requires: [String]; var allowHttp: Bool; var settings: [SourceField]
    var supportsSearch: Bool
}
struct SourceEntry: Codable, Identifiable, Hashable {
    var id: String; var pluginID: String; var name: String; var version: String; var filename: String; var origin: String?
    var manifest: SourceManifest?
    var fingerprint: String?
    var enabled: Bool?
    var isEnabled: Bool { enabled != false }
    var icon: String? { manifest?.icon }
    var kindLabel: String { manifest?.category == "radio" ? "电台" : manifest?.category == "podcast" ? "播客" : "视频" }
    var formatLabel: String { manifest?.format == "widget" ? "Widget JS" : manifest?.format == "xptv" ? "XPTV JS" : "WeBox JS" }
}
struct Card: Codable, Identifiable, Hashable {
    var id: String; var title: String; var poster: String?; var subtitle: String?; var summary: String?; var kind: String?
    var link: String?; var rating: String?
}
struct Episode: Codable, Identifiable, Hashable { var id: String; var name: String; var link: String?; var subtitle: String? }
struct EpisodeGroup: Codable, Identifiable, Hashable { var id: String; var name: String; var episodes: [Episode] }
struct ContentDetail: Codable {
    var id: String; var title: String; var poster: String?; var summary: String?; var groups: [EpisodeGroup]; var kind: String?
}
struct FilterOption: Codable, Identifiable, Hashable { var value: String; var label: String; var home: Bool?; var id: String { value } }
struct SourceFilter: Codable, Identifiable {
    var key: String; var label: String; var type: String; var `default`: String?; var options: [FilterOption]
    var id: String { key }
}
struct CatalogPage: Decodable { var items: [Card]; var nextCursor: String?; var filters: [SourceFilter]? }
struct PlayResponse: Decodable { var sources: [MediaSource] }
struct LibraryItem: Codable, Identifiable {
    var sourceID: String; var card: Card; var episodeID: String?; var seconds: Double?; var date: Date
    var pluginID: String?; var groupID: String?; var variantID: String?; var duration: Double?; var episodeName: String?
    var id: String { sourceID + ":" + card.id }
    var progress: Double { guard let duration, duration > 0 else { return 0 }; return min(1, max(0, (seconds ?? 0) / duration)) }
}
struct PlayerPreferences: Codable, Equatable {
    var bufferMode = "balanced"
    var rate: Float = 1
    var autoNext = true
    var prefetchNext = true
    var swipeEpisodes: Bool?
    var allowsEpisodeSwipe: Bool { swipeEpisodes ?? true }
    var skipIntro: Double = 0
    var skipOutro: Double = 0
    var forwardBuffer: Double { bufferMode == "quick" ? 4 : bufferMode == "stable" ? 30 : 12 }
}
struct ImportItem: Identifiable {
    let id = UUID(); let filename: String; let sourceName: String?; let error: String?; let updated: Bool
}

@MainActor
final class AppModel: ObservableObject {
    @Published var sources: [SourceEntry] = []
    @Published var selectedID = ""
    @Published var favorites: [LibraryItem] = []
    @Published var history: [LibraryItem] = []
    @Published var error: String?
    @Published var importing = false
    @Published var importResults: [ImportItem] = []
    @Published var importOwner: UUID?
    @Published var sourceRevision = 0
    @Published private(set) var encryptedDNS = false
    @Published private(set) var useSurgeVIF = false
    @Published private(set) var sourceHTTPSProxy: SourceHTTPSProxy?
    @Published var preferences: PlayerPreferences {
        didSet { defaults.set(try? JSONEncoder().encode(preferences), forKey: "webox.player.preferences") }
    }
    let playback = PlaybackController()
    let root: URL
    let screenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshots")
    private let defaults: UserDefaults
    init(root: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        sources = Self.read("webox.sources", fallback: [], defaults: defaults)
        favorites = Self.read("webox.favorites", fallback: [], defaults: defaults)
        history = Self.read("webox.history", fallback: [], defaults: defaults)
        preferences = Self.read("webox.player.preferences", fallback: PlayerPreferences(), defaults: defaults)
        selectedID = defaults.string(forKey: "webox.selected") ?? sources.first?.id ?? ""
        // Only migrate the old auto-installed source. Explicitly imported sources stay.
        let automatic = sources.filter { $0.origin == "内置附件源" }
        for old in automatic {
            for i in history.indices where history[i].sourceID == old.id { history[i].pluginID = old.pluginID }
            for i in favorites.indices where favorites[i].sourceID == old.id { favorites[i].pluginID = old.pluginID }
            sources.removeAll { $0.id == old.id }; try? FileManager.default.removeItem(at: self.root.appendingPathComponent(old.filename))
        }
        if !sources.contains(where: { $0.id == selectedID && $0.isEnabled }) { selectedID = sources.first(where: \.isEnabled)?.id ?? "" }
        playback.onProgress = { [weak self] context, seconds, duration in self?.record(context, seconds: seconds, duration: duration) }
        encryptedDNS = defaults.bool(forKey: AlternateDNS.preferenceKey)
        sourceHTTPSProxy = defaults.string(forKey: SourceHTTPSProxy.preferenceKey).flatMap { try? SourceHTTPSProxy($0) }
        useSurgeVIF = defaults.bool(forKey: "webox.useSurgeVIF") && sourceHTTPSProxy == nil
        persist()
    }
    func setEncryptedDNS(_ enabled: Bool) {
        guard encryptedDNS != enabled else { return }
        defaults.set(enabled, forKey: AlternateDNS.preferenceKey)
        encryptedDNS = enabled
    }
    func setSurgeVIF(_ enabled: Bool) {
        guard enabled != useSurgeVIF || (enabled && sourceHTTPSProxy != nil) else { return }
        if enabled {
            defaults.removeObject(forKey: SourceHTTPSProxy.preferenceKey)
            sourceHTTPSProxy = nil
        }
        defaults.set(enabled, forKey: "webox.useSurgeVIF")
        useSurgeVIF = enabled
        sourceRevision += 1
    }
    func setSourceProxy(_ input: String) throws {
        let proxy = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : try SourceHTTPSProxy(input)
        guard proxy != sourceHTTPSProxy else { return }
        if proxy != nil {
            defaults.set(false, forKey: "webox.useSurgeVIF")
            useSurgeVIF = false
        }
        defaults.set(proxy?.address, forKey: SourceHTTPSProxy.preferenceKey)
        sourceHTTPSProxy = proxy
        sourceRevision += 1
    }
    static func read<T: Decodable>(_ key: String, fallback: T, defaults: UserDefaults = .standard) -> T {
        guard let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(T.self, from: data) else { return fallback }; return decoded
    }
    func persist() {
        defaults.set(try? JSONEncoder().encode(sources), forKey: "webox.sources")
        defaults.set(try? JSONEncoder().encode(favorites), forKey: "webox.favorites")
        defaults.set(try? JSONEncoder().encode(history), forKey: "webox.history")
        defaults.set(selectedID, forKey: "webox.selected")
    }
    var selected: SourceEntry? { sources.first { $0.id == selectedID && $0.isEnabled } }
    var enabledSources: [SourceEntry] { sources.filter(\.isEnabled) }
    func select(_ source: SourceEntry) { guard source.isEnabled else { return }; selectedID = source.id; persist() }
    func configuration(_ source: SourceEntry) -> [String: JSONValue] {
        var value: [String: JSONValue] = [:]
        for field in source.manifest?.settings ?? [] { if let initial = field.default { value[field.key] = initial } }
        let stored: [String: JSONValue] = Self.read("webox.config." + source.id, fallback: [:], defaults: defaults)
        value.merge(stored) { _, new in new }
        if let secrets = try? SourceSecrets.read(source.id) { value.merge(secrets) { _, new in new } }
        return value
    }
    func needsConfiguration(_ source: SourceEntry) -> Bool {
        let values = configuration(source)
        return (source.manifest?.settings ?? []).contains { field in
            field.visible(in: values) && field.required == true && (values[field.key] == nil || values[field.key]?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
        }
    }
    func saveConfiguration(_ values: [String: JSONValue], source: SourceEntry) throws {
        var regular: [String: JSONValue] = [:], secrets: [String: JSONValue] = [:]
        for field in source.manifest?.settings ?? [] where field.visible(in: values) {
            guard let value = values[field.key] else { if field.required == true { throw WeBoxError("请填写" + field.label) }; continue }
            if field.required == true && value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw WeBoxError("请填写" + field.label) }
            if field.type == "number", case .number(let number) = value {
                guard number.isFinite, number >= (field.min ?? -Double.greatestFiniteMagnitude), number <= (field.max ?? Double.greatestFiniteMagnitude) else { throw WeBoxError(field.label + "超出范围") }
            }
            if field.type == "secret" || field.sensitive == true { secrets[field.key] = value } else { regular[field.key] = value }
        }
        try SourceSecrets.write(secrets, id: source.id)
        defaults.set(try JSONEncoder().encode(regular), forKey: "webox.config." + source.id)
        sourceRevision += 1
    }
    func bootstrap() async {
        #if DEBUG
        if screenshotMode, let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--fixtures=") }) {
            let directory = URL(fileURLWithPath: String(argument.dropFirst(11)))
            let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
            await importFiles(files.filter { $0.pathExtension == "js" })
            importResults = []
            if let source = sources.first, let runtime = try? await makeRuntime(source) {
                defer { runtime.close() }
                if let raw = try? await runtime.invoke("list", ["filters":[:],"surface":"home"]), let data = try? JSONSerialization.data(withJSONObject:raw), let page = try? JSONDecoder().decode(CatalogPage.self,from:data) {
                    if favorites.isEmpty { favorites = page.items.prefix(3).map { LibraryItem(sourceID:source.id,card:$0,date:Date(),pluginID:source.pluginID) } }
                    if history.isEmpty, let card=page.items.first { history=[LibraryItem(sourceID:source.id,card:card,episodeID:"1",seconds:2,date:Date(),pluginID:source.pluginID,groupID:"primary",duration:12,episodeName:"01")] }
                    persist()
                }
            }
            ScreenshotSupport.mark("library");ScreenshotSupport.mark("settings")
        }
        #endif
        for source in sources where source.manifest == nil {
            if let data = try? Data(contentsOf: root.appendingPathComponent(source.filename)) { _ = try? await install(data, origin: source.origin) }
        }
    }
    func makeRuntime(_ source: SourceEntry) async throws -> SourceRuntime {
        let runtime = SourceRuntime(namespace: source.id, sourceProxy: sourceHTTPSProxy, useSurgeVIF: useSurgeVIF)
        do {
            let script = try String(contentsOf: root.appendingPathComponent(source.filename), encoding: .utf8)
            _ = try await runtime.load(script: script, settings: configuration(source).mapValues(\.any), hint: source.fingerprint ?? source.id)
            return runtime
        } catch { runtime.close(); throw error }
    }
    func importFiles(_ urls: [URL], owner: UUID? = nil) async {
        guard !importing else { error = "正在导入，请等待当前文件处理完成"; return }
        importing = true; importOwner = owner; defer { importing = false }
        var results: [ImportItem] = []
        for url in urls {
            do { let data = try await ScriptDocument.read(url); let installed = try await install(data, origin: url.lastPathComponent); results.append(ImportItem(filename: url.lastPathComponent, sourceName: installed.0.name, error: nil, updated: installed.1)) }
            catch { results.append(ImportItem(filename: url.lastPathComponent, sourceName: nil, error: error.localizedDescription, updated: false)) }
        }
        importResults = results
    }
    func importFile(_ url: URL) async { await importFiles([url]) }
    func importURL(_ raw: String, owner: UUID? = nil) async {
        guard !importing else { return }; importing = true; importOwner = owner; defer { importing = false }
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            guard var url = URL(string: address), HTTPClient.valid(url, httpsOnly: false) else { throw WeBoxError("请输入 HTTP(S) 脚本直链") }
            if url.host == "github.com", url.path.contains("/blob/"), var raw = URLComponents(url: url, resolvingAgainstBaseURL: false) { raw.host = "raw.githubusercontent.com"; raw.path = raw.path.replacingOccurrences(of: "/blob/", with: "/"); url = raw.url ?? url }
            let client = HTTPClient(); defer { client.close() }
            let response = try await client.fetch(URLRequest(url: url, timeoutInterval: 30), limit: ScriptDocument.limit, httpsOnly: url.scheme == "https")
            guard response.response.statusCode == 200 else { throw WeBoxError("下载脚本失败：HTTP \(response.response.statusCode)") }
            var origin = URLComponents(url: url, resolvingAgainstBaseURL: false); origin?.query = nil; origin?.fragment = nil
            let installed = try await install(response.data, origin: origin?.string)
            importResults = [ImportItem(filename: url.lastPathComponent, sourceName: installed.0.name, error: nil, updated: installed.1)]
        } catch { importResults = [ImportItem(filename: "链接导入", sourceName: nil, error: error.localizedDescription, updated: false)] }
    }
    @discardableResult func install(_ data: Data, origin: String?) async throws -> (SourceEntry, Bool) {
        let document = try ScriptDocument(data: data)
        let candidate = SourceRuntime(namespace: "validation-" + UUID().uuidString, sourceProxy: sourceHTTPSProxy, useSurgeVIF: useSurgeVIF)
        defer { candidate.close() }
        let raw = try await candidate.load(script: document.text, hint: document.fingerprint)
        let manifest = try JSONDecoder().decode(SourceManifest.self, from: JSONSerialization.data(withJSONObject: raw))
        let existing = sources.first { $0.pluginID == manifest.id }
        let id = existing?.id ?? UUID().uuidString
        let filename = existing?.filename ?? id + ".js"
        try Data(document.text.utf8).write(to: root.appendingPathComponent(filename), options: .atomic)
        let entry = SourceEntry(id: id, pluginID: manifest.id, name: manifest.name, version: manifest.version, filename: filename, origin: origin, manifest: manifest, fingerprint: document.fingerprint, enabled: existing?.enabled ?? true)
        if let index = sources.firstIndex(where: { $0.id == id }) { sources[index] = entry } else { sources.append(entry) }
        if selectedID.isEmpty { selectedID = id }
        for i in history.indices where history[i].pluginID == manifest.id { history[i].sourceID = id }
        for i in favorites.indices where favorites[i].pluginID == manifest.id { favorites[i].sourceID = id }
        sourceRevision += 1; persist()
        return (entry, existing != nil)
    }
    func remove(_ source: SourceEntry) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(source.filename)); try? SourceSecrets.write([:], id: source.id)
        defaults.removeObject(forKey: "webox.config." + source.id)
        sources.removeAll { $0.id == source.id }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("webox.source.\(source.id).") { defaults.removeObject(forKey: key) }
        if selectedID == source.id { selectedID = enabledSources.first?.id ?? "" }; sourceRevision += 1; persist()
    }
    func toggleEnabled(_ source: SourceEntry) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].enabled = !source.isEnabled
        if selectedID == source.id && !sources[index].isEnabled { selectedID = enabledSources.first?.id ?? "" }
        else if selectedID.isEmpty { selectedID = enabledSources.first?.id ?? "" }
        sourceRevision += 1; persist()
    }
    func favorite(_ card: Card, source: SourceEntry) -> Bool { favorites.contains { $0.sourceID == source.id && $0.card.id == card.id } }
    func toggleFavorite(_ card: Card, source: SourceEntry) {
        if favorite(card, source: source) { favorites.removeAll { $0.sourceID == source.id && $0.card.id == card.id } }
        else { favorites.insert(LibraryItem(sourceID: source.id, card: card, date: Date(), pluginID: source.pluginID), at: 0) }; persist()
    }
    func saved(_ card: Card, source: SourceEntry) -> LibraryItem? { history.first { $0.sourceID == source.id && $0.card.id == card.id } }
    func deleteLibraryItems(_ ids: Set<String>, history isHistory: Bool) {
        if isHistory { history.removeAll { ids.contains($0.id) } }
        else { favorites.removeAll { ids.contains($0.id) } }
        persist()
    }

    func record(_ context: PlaybackContext, seconds: Double, duration: Double) {
        guard seconds.isFinite, seconds >= 0, (duration > 0 || seconds > 0) else { return }
        let previous = saved(context.card, source: context.source)
        let sameEpisode = previous.flatMap { item in
            item.episodeID == context.episode.id && item.groupID == context.group.id ? item : nil
        }
        let total = duration.isFinite && duration > 0 ? duration : sameEpisode?.duration
        let variant = playback.selectedVariantID ?? sameEpisode?.variantID
        history.removeAll { $0.sourceID == context.source.id && $0.card.id == context.card.id }
        history.insert(LibraryItem(sourceID: context.source.id, card: context.card, episodeID: context.episode.id, seconds: seconds, date: Date(), pluginID: context.source.pluginID, groupID: context.group.id, variantID: variant, duration: total, episodeName: context.episode.name), at: 0)
        history = Array(history.prefix(200))
        defaults.set(try? JSONEncoder().encode(history), forKey: "webox.history")
    }
}
