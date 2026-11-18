import SwiftUI

/// The novel module uses the app palette and one set of navigation, surface and row rules.
enum NovelStyle {
    static let radius: CGFloat = 14
    static let inset: CGFloat = 16
    static let title = Font.system(size: 17, weight: .semibold)
    static let metadata = Font.system(size: 12)
}

private struct NovelScreenStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(STVTheme.accent)
            .scrollContentBackground(.hidden)
            .background(STVTheme.bg.ignoresSafeArea())
            .toolbarBackground(STVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func novelScreen() -> some View { modifier(NovelScreenStyle()) }
    func novelPanel() -> some View {
        padding(NovelStyle.inset).frame(maxWidth: .infinity, alignment: .leading)
            .background(STVTheme.surface, in: RoundedRectangle(cornerRadius: NovelStyle.radius))
    }
}

struct NovelBackButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)) }
            .accessibilityLabel("返回")
    }
}

struct NovelBookRow: View {
    let title: String
    let author: String
    let kind: String
    let cover: String?
    var latest = ""
    var subtitle = ""
    var rank: Int? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WebCover(url: cover, title: title).frame(width: 58, height: 80)
            VStack(alignment: .leading, spacing: 7) {
                Text(rank.map { "\($0). \(title)" } ?? title).font(NovelStyle.title).foregroundStyle(STVTheme.text).lineLimit(2)
                Text([author,kind].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(NovelStyle.metadata).foregroundStyle(STVTheme.secondary).lineLimit(2)
                if !latest.isEmpty { Text(latest).font(.caption2).foregroundStyle(STVTheme.secondary).lineLimit(1) }
                if !subtitle.isEmpty { Text(subtitle).font(.caption2).foregroundStyle(STVTheme.accent).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 14)
    }
}
