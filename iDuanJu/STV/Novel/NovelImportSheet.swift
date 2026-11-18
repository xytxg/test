import SwiftUI
import UniformTypeIdentifiers

/// ui-redesign 07: one sheet for every import path — local books, a source URL, the clipboard or a source file.
/// Results stay in the sheet as a banner instead of an alert.
struct NovelImportSheet: View {
    var onLocalFiles: () -> Void = {}
    /// 书源 page opens the sheet without the 书籍 group.
    var showBooks = true
    @Environment(\.dismiss) private var dismiss
    private let store = LegadoSourceStore.shared
    @State private var url = ""
    @State private var busy = false
    @State private var fileImport = false
    @State private var result: Result?
    @FocusState private var focused: Bool

    struct Result: Equatable { var ok: Bool; var title: String; var detail: String? }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(STVTheme.glassBorder).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.bottom, 10)
                HStack {
                    Text("导入").font(.system(size: 20, weight: .bold)).foregroundStyle(STVTheme.text)
                    Spacer()
                    RoundIconButton(systemName: "xmark") { dismiss() }.accessibilityIdentifier("import.close")
                }
                .frame(height: 36)
                if showBooks {
                    label("书籍")
                    group {
                        row("doc.text", "本地 TXT / EPUB", "可多选，自动识别编码和章节", id: "import.local", action: onLocalFiles)
                    }
                }
                label("书源（阅读 / Legado 格式）")
                HStack(spacing: 10) {
                    Image(systemName: "link").font(.system(size: 16, weight: .medium)).foregroundStyle(STVTheme.tertiary)
                    TextField("https://example.invalid/src.json", text: $url)
                        .focused($focused).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 15)).foregroundStyle(STVTheme.text)
                        .submitLabel(.go).onSubmit(importURL)
                        .accessibilityIdentifier("import.url")
                    Button { url = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" } label: { MiniButtonLabel(title: "粘贴") }
                        .buttonStyle(PressScale())
                }
                .padding(.leading, 14).padding(.trailing, 9).frame(height: 48)
                .background(STVTheme.glass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(STVTheme.glassBorder, lineWidth: 1))
                Button(action: importURL) {
                    ZStack {
                        PillButtonLabel(title: busy ? "" : "导入书源", tone: .accent, expand: true)
                        if busy { ProgressView().tint(STVTheme.onAccent) }
                    }
                }
                .buttonStyle(PressScale(scale: 0.98)).disabled(busy).padding(.top, 10).accessibilityIdentifier("import.submit")
                group {
                    row("doc.on.clipboard", "从剪贴板导入", "支持书源 JSON 或书源链接", id: "import.clipboard", action: importClipboard)
                    Hairline()
                    row("folder", "从文件导入", "选择 .json 书源文件", id: "import.file") { fileImport = true }
                }
                .padding(.top, 10)
                if let result { banner(result).padding(.top, 12).transition(.move(edge: .bottom).combined(with: .opacity)) }
                Text("App 不内置任何书源，导入的书源只保存在本机。")
                    .font(.system(size: 12)).foregroundStyle(STVTheme.tertiary).lineSpacing(6).padding(.horizontal, 4).padding(.top, 12)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 34)
            .animation(DS.panel, value: result)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(showBooks ? [.height(640), .large] : [.height(520), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground(STVTheme.sheet)
        .fileImporter(isPresented: $fileImport, allowedContentTypes: [.json, .plainText, .text]) { r in
            guard case .success(let u) = r else { return }
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            report { try store.add(LegadoSourceStore.parse(try Data(contentsOf: u))) }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundStyle(STVTheme.secondary).padding(.horizontal, 4).padding(.top, 16).padding(.bottom, 8)
    }

    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0) { c() }.padding(.horizontal, 14)
            .background(STVTheme.glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ icon: String, _ title: String, _ sub: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconWell(systemName: icon, size: 40, corner: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(STVTheme.text)
                    Text(sub).font(.system(size: 12)).foregroundStyle(STVTheme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(STVTheme.tertiary)
            }
            .frame(minHeight: 66).contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.98))
        .accessibilityIdentifier(id)
    }

    private func banner(_ r: Result) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.ok ? "checkmark.circle" : "exclamationmark.circle").font(.system(size: 18, weight: .medium))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title).font(.system(size: 14, weight: .semibold))
                if let d = r.detail { Text(d).font(.system(size: 12)).foregroundStyle(STVTheme.secondary) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(r.ok ? STVTheme.ok : STVTheme.accentWarm)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(r.ok ? STVTheme.okSoft : STVTheme.warmSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("import.result")
    }

    private func report(_ f: () throws -> (added: Int, updated: Int, unsupported: Int)) {
        do {
            let r = try f()
            result = Result(ok: true, title: "新增 \(r.added) 个，更新 \(r.updated) 个",
                            detail: r.unsupported > 0 ? "其中 \(r.unsupported) 个暂不支持，已自动停用" : nil)
        } catch { result = Result(ok: false, title: "导入失败", detail: "不是有效的书源 JSON") }
    }

    private func importClipboard() {
        guard let t = UIPasteboard.general.string, !t.isEmpty else { result = Result(ok: false, title: "剪贴板是空的"); return }
        if let u = URL(string: t.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme?.hasPrefix("http") == true { url = u.absoluteString; importURL(); return }
        report { try store.importText(t) }
    }

    private func importURL() {
        guard let u = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme?.hasPrefix("http") == true else {
            result = Result(ok: false, title: "网址无效", detail: "请输入 http(s) 开头的书源地址"); return
        }
        focused = false; busy = true
        Task {
            do { let r = try await store.importURL(u); report { r } }
            catch { result = Result(ok: false, title: "导入失败", detail: error.localizedDescription) }
            busy = false
        }
    }
}
