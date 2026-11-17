import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SourceImportCoordinator: ObservableObject {
    struct FileRequest: Identifiable {
        let id = UUID()
        let allowsMultipleSelection: Bool
    }

    let id = UUID()
    @Published var fileRequest: FileRequest?
    @Published var link = false
    @Published var address = ""

    func openFiles(allowsMultipleSelection: Bool = false) {
        fileRequest = FileRequest(allowsMultipleSelection: allowsMultipleSelection)
    }

    func selected(_ urls: [URL], app: AppModel) {
        fileRequest = nil
        guard !urls.isEmpty else { return }
        // Files can dismiss its own controller. Import from the delegate callback,
        // independently of how SwiftUI reports the presentation ending.
        Task { await app.importFiles(urls, owner: id) }
    }

    func importLink(app: AppModel) {
        let submittedAddress = address
        Task { await app.importURL(submittedAddress, owner: id) }
    }
}

struct SourceFilePicker: UIViewControllerRepresentable {
    let allowsMultipleSelection: Bool
    let completion: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // The copy is available locally before parsing. Generic file types
        // accommodate Android exports with nonstandard filename extensions.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .text, .javaScript], asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var completion: (([URL]) -> Void)?

        init(_ completion: @escaping ([URL]) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish([])
        }

        private func finish(_ urls: [URL]) {
            let callback = completion
            completion = nil
            callback?(urls)
        }
    }
}

struct SourceImportStatus: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var importer: SourceImportCoordinator

    var body: some View {
        if app.importOwner == importer.id {
            if app.importing {
                Section {
                    HStack {
                        ProgressView()
                        Text("正在读取并解析脚本…")
                    }.accessibilityIdentifier("import-progress")
                }
            } else if !app.importResults.isEmpty {
                Section {
                    ForEach(app.importResults) { ImportResultRow(item: $0) }
                    Button("清除导入结果") { app.importResults = [] }
                } header: { Text("导入结果") }
            }
        }
    }
}

private struct SourceImportPresentation: ViewModifier {
    @EnvironmentObject private var app: AppModel
    @StateObject private var importer = SourceImportCoordinator()

    func body(content: Content) -> some View {
        content.environmentObject(importer)
            .sheet(item: $importer.fileRequest) { request in
                SourceFilePicker(allowsMultipleSelection: request.allowsMultipleSelection) { urls in
                    importer.selected(urls, app: app)
                }.ignoresSafeArea()
            }
            .alert("导入脚本链接", isPresented: $importer.link) {
                TextField("https://…/source.js", text: $importer.address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("取消", role: .cancel) {}
                Button("导入") { importer.importLink(app: app) }
            } message: { Text("填写 JS 直链，也可粘贴 GitHub 文件链接。") }
    }
}

extension View {
    func sourceImportPresentation() -> some View { modifier(SourceImportPresentation()) }
}
