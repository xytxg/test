import Foundation

enum ScreenshotSupport {
    static var importTestDirectory: URL? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--import-test-document") {
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        #endif
        return nil
    }

    static func prepareImportTestFiles() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--import-test-document"), args.indices.contains(index + 1),
              let data = Data(base64Encoded: args[index + 1]), let directory = importTestDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("Local-UTF16.webox.js"), options: .atomic)
        try? Data("<!doctype html><html>Not a script</html>".utf8).write(to: directory.appendingPathComponent("Invalid.webox.js"), options: .atomic)
        #endif
    }
    static func mark(_ page:String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--screenshots") else {return}
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("UIReady-"+page)
        try? Data("ready".utf8).write(to:url,options:.atomic)
        #endif
    }
}
