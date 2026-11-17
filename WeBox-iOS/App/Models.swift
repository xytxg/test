import Foundation
import SwiftUI

struct SourceEntry: Codable, Identifiable, Hashable {
    var id: String
    var pluginID: String
    var name: String
    var version: String
    var filename: String
    var origin: String?
}
struct Card: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var poster: String?
    var subtitle: String?
    var summary: String?
    var kind: String?
}
struct Episode: Decodable, Identifiable, Hashable { var id: String; var name: String }
struct EpisodeGroup: Decodable, Identifiable { var id: String; var name: String; var episodes: [Episode] }
struct ContentDetail: Decodable {
    var id: String
    var title: String
    var poster: String?
    var summary: String?
    var groups: [EpisodeGroup]
}
struct FilterOption: Decodable, Identifiable { var value: String; var label: String; var id: String { value } }
struct SourceFilter: Decodable, Identifiable {
    var key: String; var label: String; var type: String
    var `default`: String?
    var options: [FilterOption]
    var id: String { key }
}
struct CatalogPage: Decodable { var items: [Card]; var nextCursor: String? }
struct PlayResponse: Decodable { var sources: [MediaSource] }
struct LibraryItem: Codable, Identifiable {
    var sourceID: String; var card: Card; var episodeID: String?; var seconds: Double?; var date: Date
    var id: String { sourceID + ":" + card.id }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var sources: [SourceEntry] = []
    @Published var selectedID = ""
    @Published var favorites: [LibraryItem] = []
    @Published var history: [LibraryItem] = []
    @Published var error: String?
    @Published var importing = false
    let root: URL
    let screenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshots")
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sources = Self.read("webox.sources", fallback: [])
        favorites = Self.read("webox.favorites", fallback: [])
        history = Self.read("webox.history", fallback: [])
        selectedID = UserDefaults.standard.string(forKey: "webox.selected") ?? sources.first?.id ?? ""
    }
    static func read<T: Decodable>(_ key: String, fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key), let decoded = try? JSONDecoder().decode(T.self, from: data) else { return fallback }; return decoded
    }
    func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(sources), forKey: "webox.sources")
        UserDefaults.standard.set(try? JSONEncoder().encode(favorites), forKey: "webox.favorites")
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "webox.history")
        UserDefaults.standard.set(selectedID, forKey: "webox.selected")
    }
    var selected: SourceEntry? { sources.first { $0.id == selectedID } }
    func bootstrap() async {
        if screenshotMode {
            if let url = Bundle.main.url(forResource: "demo.webox", withExtension: "js") { await importFile(url, origin: "离线截图演示") }
        } else if sources.isEmpty, let url = Bundle.main.url(forResource: "hongguo.webox", withExtension: "js") { await importFile(url, origin: "内置附件源") }
    }
    func makeRuntime(_ source: SourceEntry) async throws -> SourceRuntime {
        let runtime = SourceRuntime(namespace: source.id)
        do {
            let script = try String(contentsOf: root.appendingPathComponent(source.filename), encoding: .utf8)
            _ = try await runtime.load(script: script); return runtime
        } catch { runtime.close(); throw error }
    }
    func importFile(_ url: URL, origin: String? = nil) async {
        guard !importing else { return }; importing = true; defer { importing = false }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try await install(data, origin: origin ?? url.lastPathComponent)
        } catch { self.error = error.localizedDescription }
    }
    func importURL(_ raw: String) async {
        guard !importing else { return }; importing = true; defer { importing = false }
        do {
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil, url.user == nil else { throw WeBoxError("请输入 HTTPS 源文件链接") }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = 30
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https" else { throw WeBoxError("源文件下载失败") }
            var data = Data()
            for try await byte in bytes { guard data.count < 4_194_304 else { throw WeBoxError("源文件超过 4 MB") }; data.append(byte) }
            // Avoid persisting signed URL query strings or tokens in source metadata.
            var origin = URLComponents(url: url, resolvingAgainstBaseURL: false); origin?.query = nil; origin?.fragment = nil
            try await install(data, origin: origin?.string)
        } catch { self.error = error.localizedDescription }
    }
    private func install(_ data: Data, origin: String?) async throws {
        guard data.count <= 4_194_304, let text = String(data: data, encoding: .utf8) else { throw WeBoxError("请选择 UTF-8 的 .webox.js 文件") }
        let candidate = SourceRuntime(namespace: "validation-" + UUID().uuidString)
        defer { candidate.close() }
        let metadata = try await candidate.load(script: text)
        guard let pluginID = metadata["id"] as? String, let name = metadata["name"] as? String else { throw WeBoxError("源元数据不完整") }
        if let existing = sources.first(where: { $0.pluginID == pluginID }) {
            try data.write(to: root.appendingPathComponent(existing.filename), options: .atomic)
            let i = sources.firstIndex(where: { $0.id == existing.id })!
            sources[i].name = name; sources[i].version = metadata["version"] as? String ?? "0"; sources[i].origin = origin
            selectedID = existing.id
        } else {
            let id = UUID().uuidString
            let filename = id + ".webox.js"
            try data.write(to: root.appendingPathComponent(filename), options: .atomic)
            sources.append(SourceEntry(id: id, pluginID: pluginID, name: name, version: metadata["version"] as? String ?? "0", filename: filename, origin: origin))
            selectedID = id
        }
        persist()
    }
    func remove(_ source: SourceEntry) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(source.filename))
        sources.removeAll { $0.id == source.id }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("webox.source.\(source.id).") { UserDefaults.standard.removeObject(forKey: key) }
        if selectedID == source.id { selectedID = sources.first?.id ?? "" }; persist()
    }
    func toggleFavorite(_ card: Card, source: SourceEntry) {
        let id = source.id + ":" + card.id
        if favorites.contains(where: { $0.id == id }) { favorites.removeAll { $0.id == id } }
        else { favorites.insert(LibraryItem(sourceID: source.id, card: card, date: Date()), at: 0) }; persist()
    }
    func record(_ card: Card, source: SourceEntry, episode: String, seconds: Double) {
        history.removeAll { $0.sourceID == source.id && $0.card.id == card.id }
        history.insert(LibraryItem(sourceID: source.id, card: card, episodeID: episode, seconds: seconds.isFinite ? seconds : 0, date: Date()), at: 0)
        history = Array(history.prefix(200)); persist()
    }
}
