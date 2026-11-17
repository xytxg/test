import Foundation

enum ScreenshotSupport {
    static func mark(_ page:String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--screenshots") else {return}
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("UIReady-"+page)
        try? Data("ready".utf8).write(to:url,options:.atomic)
        #endif
    }
}
