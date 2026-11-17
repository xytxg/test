import SwiftUI
import UniformTypeIdentifiers

struct SourcesView: View {
    @EnvironmentObject var app: AppModel
    @State private var filePicker = false
    @State private var showURL = false
    @State private var sourceURL = ""
    @State private var toRemove: SourceEntry?
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "externaldrive.badge.plus").font(.largeTitle).foregroundStyle(.tint)
                    Text("连接你的内容").font(.title3.bold())
                    Text("导入 WeBox JavaScript 内容源，分类、搜索和播放都在这里接续。").font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(.vertical, 12)
                Button { filePicker = true } label: { Label("从文件导入", systemImage: "folder") }.disabled(app.importing)
                Button { showURL = true } label: { Label("从链接导入", systemImage: "link") }.disabled(app.importing)
                if app.importing { HStack { ProgressView(); Text("正在验证内容源…").foregroundStyle(.secondary) } }
            }
            Section("已添加 · \(app.sources.count)") {
                ForEach(app.sources) { source in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.tint).frame(width: 32).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(source.name).font(.headline)
                            Text("v\(source.version) · WeBox 源").font(.caption).foregroundStyle(.secondary)
                            if let origin = source.origin { Text(origin).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                        }
                        Spacer()
                        if app.selectedID == source.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                    }.padding(.vertical, 6).contentShape(Rectangle())
                    .onTapGesture { app.selectedID = source.id; app.persist() }
                    .swipeActions { Button("删除", role: .destructive) { toRemove = source } }
                }
                if app.sources.isEmpty { Text("暂无内容源").foregroundStyle(.secondary) }
            }
            Section("接口支持") {
                Label("WeBox API 1.0–1.5 基础源接口", systemImage: "checkmark.circle")
                Label("HTTP、源存储、AES / 哈希 / gzip", systemImage: "checkmark.circle")
                Label("MP4 / HLS · CENC MP4 分段处理", systemImage: "checkmark.circle")
            }.font(.subheadline)
            Section {
                Text("仅导入你信任的源。源脚本可发起网络请求并在设备保存自己的数据。内容由源站提供，设备不会上传收藏和播放记录。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("WeBox iOS 0.1.0 · GPL-3.0-only").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("源管理")
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.javaScript, .plainText, .data]) { result in
            switch result { case .success(let url): Task { await app.importFile(url) }; case .failure(let error): app.error = error.localizedDescription }
        }
        .alert("导入源链接", isPresented: $showURL) {
            TextField("https://example.com/source.webox.js", text: $sourceURL).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("取消", role: .cancel) {}
            Button("导入") { Task { await app.importURL(sourceURL) } }
        } message: { Text("输入 .webox.js 文件的 HTTPS 直达链接。") }
        .confirmationDialog("删除内容源及其设备缓存？", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }), titleVisibility: .visible) {
            Button("删除源", role: .destructive) { if let source = toRemove { app.remove(source) }; toRemove = nil }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var app: AppModel
    @State private var section = 0
    var items: [LibraryItem] { section == 0 ? app.favorites : app.history }
    var body: some View {
        List {
            Section {
                Picker("资料库", selection: $section) { Text("我的收藏").tag(0); Text("播放记录").tag(1) }.pickerStyle(.segmented)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            if items.isEmpty {
                ContentUnavailableView(section == 0 ? "收藏喜欢的故事" : "还没有播放记录", systemImage: section == 0 ? "heart" : "clock", description: Text(section == 0 ? "在详情页点一下收藏，之后就能快速找到。" : "开始播放后，会自动记录分集与进度。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                if let source = app.sources.first(where: { $0.id == item.sourceID }) {
                    NavigationLink {
                        DetailView(card: item.card, source: source)
                    } label: {
                        HStack(spacing: 14) {
                            PosterImage(url: item.card.poster, title: item.card.title).frame(width: 58, height: 82).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(item.card.title).font(.headline)
                                Text(source.name).font(.caption).foregroundStyle(.secondary)
                                if section == 1 { Text("进度 \(Int((item.seconds ?? 0).isFinite ? max(0, item.seconds ?? 0) : 0)) 秒").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.padding(.vertical, 4)
                    }
                } else { Label(item.card.title + " · 源已移除", systemImage: "externaldrive.badge.xmark").foregroundStyle(.secondary) }
            }.onDelete { indices in
                let ids = Set(indices.map { items[$0].id })
                if section == 0 { app.favorites.removeAll { ids.contains($0.id) } } else { app.history.removeAll { ids.contains($0.id) } }
                app.persist()
            }
        }.listStyle(.insetGrouped).navigationTitle("资料库")
    }
}
