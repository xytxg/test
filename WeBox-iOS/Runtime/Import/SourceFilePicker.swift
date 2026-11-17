import SwiftUI
import UniformTypeIdentifiers

// This object belongs to the page, never to rows that disappear after the first import.
@MainActor
final class SourceImportCoordinator: ObservableObject {
    enum Sheet: String, Identifiable { case files, results; var id: String { rawValue } }
    let id = UUID()
    @Published var sheet: Sheet?
    @Published var link = false
    @Published var address = ""
    private var pendingFiles: [URL]?
    func openFiles() { pendingFiles = nil; sheet = .files }
    func selected(_ urls: [URL]) { pendingFiles = urls; sheet = nil }
    func dismissed(app: AppModel) {
        if let files = pendingFiles {
            pendingFiles = nil
            guard !files.isEmpty else { return }
            Task {
                await app.importFiles(files, owner: id)
                if !app.importResults.isEmpty { sheet = .results }
            }
        } else if app.importOwner == id, !app.importing {
            app.importResults = []
        }
    }
    func importLink(app: AppModel) {
        Task {
            await app.importURL(address, owner: id)
            if !app.importResults.isEmpty { sheet = .results }
        }
    }
}

struct SourceFilePicker: UIViewControllerRepresentable {
    let completion: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Copy mode lets Files finish downloading third-party/iCloud documents before parsing.
        // Accept all file types because Android-exported JS can have an unregistered UTI.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(_ completion: @escaping ([URL]) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion([]) }
    }
}

private struct SourceImportPresentation: ViewModifier {
    @EnvironmentObject private var app: AppModel
    @StateObject private var importer = SourceImportCoordinator()
    func body(content: Content) -> some View {
        content.environmentObject(importer)
            .sheet(item: $importer.sheet, onDismiss: { importer.dismissed(app: app) }) { page in
                switch page {
                case .files:
                    SourceFilePicker { urls in
                        importer.selected(urls)
                    }.ignoresSafeArea()
                case .results: ImportResultsView()
                }
            }
            .onChange(of: app.importResults.isEmpty) { _, empty in
                if empty, importer.sheet == .results { importer.sheet = nil }
            }
            .alert("导入脚本链接", isPresented: $importer.link) {
                TextField("https://…/source.js", text: $importer.address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("取消", role: .cancel) {}
                Button("导入") { importer.importLink(app: app) }
            } message: { Text("填写 JS 直链，也可粘贴 GitHub 文件链接。") }
            .overlay(alignment: .bottom) {
                if app.importing, app.importOwner == importer.id {
                    HStack { ProgressView(); Text("正在读取并解析脚本…").font(.subheadline) }
                        .padding().background(.regularMaterial, in: Capsule()).padding()
                        .accessibilityIdentifier("import-progress")
                }
            }
    }
}
extension View {
    func sourceImportPresentation() -> some View { modifier(SourceImportPresentation()) }
}
