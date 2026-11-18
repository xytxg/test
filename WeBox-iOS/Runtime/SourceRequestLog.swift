import Foundation
import SwiftUI
import UIKit

@MainActor
final class SourceRequestLog: ObservableObject {
    static let shared = SourceRequestLog()

    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let request: String
        let event: String

        var line: String {
            "\(time.formatted(date: .omitted, time: .standard))  \(request)  \(event)"
        }
    }

    @Published private(set) var entries: [Entry] = []
    private var sequence = 0

    func begin(_ request: URLRequest, operation: String) -> String {
        sequence += 1
        let label = "#\(sequence) \(operation) \(request.httpMethod ?? "GET") \(request.url?.host ?? "未知域名")"
        append(label, "开始")
        return label
    }

    func append(_ request: String, _ event: String) {
        entries.append(Entry(time: Date(), request: request, event: event))
        if entries.count > 160 { entries.removeFirst(entries.count - 160) }
    }

    func clear() { entries.removeAll() }

    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return (["WeBox \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)"] + entries.map(\.line)).joined(separator: "\n")
    }
}
