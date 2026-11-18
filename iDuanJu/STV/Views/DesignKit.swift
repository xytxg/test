import SwiftUI

// i短剧 redesign building blocks (ui-redesign/styles.css + video.css). Colours come from STVTheme; every size here
// is the spec's pt value. Screens compose these instead of styling controls ad hoc.

enum DS {
    /// One spring for selection changes (tabs, segments, chips) and one for panels / bars.
    static let select = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let panel = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.8)
    /// Spaced numbers like the spec: "512.6 万", "全 82 集".
    static func count(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.1f 亿", Double(n) / 100_000_000) }
        if n >= 10_000 { return String(format: "%.1f 万", Double(n) / 10_000) }
        return "\(n)"
    }
    static func episodes(_ s: HGSeries) -> String? {
        if let sub = s.subtitle, sub.contains("更新至") || sub.hasPrefix("全") { return spaced(sub) }
        if s.source.isLongVideo { return s.duration > 0 ? Fmt.clock(s.duration) : nil }
        return s.episodeCount > 0 ? "全 \(s.episodeCount) 集" : nil
    }
    /// "更新至24集" → "更新至 24 集".
    static func spaced(_ t: String) -> String {
        var out = "", prevDigit: Bool? = nil
        for ch in t {
            let d = ch.isNumber || ch == "."
            if let p = prevDigit, p != d, ch != " ", out.last != " " { out.append(" ") }
            out.append(ch); prevDigit = ch == " " ? nil : d
        }
        return out
    }
    /// Grid subtitle: "512.6 万热度", else "都市 · 玄幻", else the episode count.
    static func heat(_ s: HGSeries) -> String {
        if s.source.isLongVideo { return Fmt.meta(s) }
        if s.playCount > 0 { return count(s.playCount) + "热度" }
        return genres(s) ?? episodes(s) ?? ""
    }
    static func genres(_ s: HGSeries, _ n: Int = 2) -> String? {
        let g = s.tags.prefix(n).joined(separator: " · ")
        return g.isEmpty ? nil : g
    }
    /// Home shelf subtitle: "悬疑 · 96 集".
    static func shelfMeta(_ s: HGSeries) -> String {
        if s.source.isLongVideo { return Fmt.meta(s) }
        let parts = [s.tags.first, s.episodeCount > 0 ? "\(s.episodeCount) 集" : nil].compactMap { $0 }
        return parts.isEmpty ? heat(s) : parts.joined(separator: " · ")
    }
}

// MARK: - Surfaces

extension View {
    /// `.card`: card fill + 1 px border; light mode adds the soft drop shadow.
    func dsCard(_ radius: CGFloat = 20) -> some View {
        background(STVTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(STVTheme.cardBorder, lineWidth: 1))
            .shadow(color: STVTheme.shadowSoft, radius: 14, y: 10)
    }
    /// Floating glass bar (tab bar, sticky filter strip, play bar).
    func dsBar(_ radius: CGFloat) -> some View {
        stvGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous),
                 tint: STVTheme.bar.opacity(0.30))
            .shadow(color: STVTheme.barShadow.opacity(0.55), radius: 10, y: 5)
    }
    /// Pinned header: 80 % page colour over a blur, hairline under it.
    func dsPinned(_ on: Bool) -> some View {
        background {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.clear)
                    .stvGlass(in: Rectangle(), tint: STVTheme.pin.opacity(0.72), backing: STVTheme.bg)
                STVTheme.hairline.frame(height: 1)
            }
            .ignoresSafeArea(edges: .top)
            .opacity(on ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: on)
        }
    }
    /// Page ground with the spec's top glow (`.phone.amb` / `.amb-cool`).
    func dsAmbient(cool: Bool = false, visible: Bool = true) -> some View {
        background(alignment: .top) {
            AmbientGlow(cool: cool).opacity(visible ? 1 : 0).animation(.easeOut(duration: 0.25), value: visible)
                .ignoresSafeArea().allowsHitTesting(false)
        }
        .background(STVTheme.bg.ignoresSafeArea())
    }
}

/// radial-gradient(130% 100% at 25% -8%, c0 0, c1 36–40 %, transparent 72 %) over the top 380 pt.
struct AmbientGlow: View {
    var cool = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h: CGFloat = 380
            let c = cool ? STVTheme.ambientCool : STVTheme.ambientWarm
            RadialGradient(stops: [.init(color: c[0], location: 0), .init(color: c[1], location: cool ? 0.40 : 0.36),
                                   .init(color: c[1].opacity(0), location: 0.72)],
                           center: .center, startRadius: 0, endRadius: h)
                .frame(width: h * 2, height: h * 2)
                .scaleEffect(x: 1.3 * w / h, y: 1)
                .position(x: 0.25 * w, y: -0.08 * h)
        }
        .frame(height: 380)
        .clipped()
    }
}

// MARK: - Level 1: underline text tabs (`.ttabs`)

struct UnderlineTabs<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var small = false
    var idPrefix = "tabs"
    @Namespace private var ns
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: small ? 24 : 22) {
            ForEach(items, id: \.self) { it in
                let on = it == selection
                Button { withAnimation(DS.select) { selection = it } } label: {
                    UnderlineTabLabel(title: label(it), on: on, small: small, ns: ns)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(idPrefix).\(label(it))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(height: small ? 34 : 40, alignment: small ? .center : .bottom)
    }
}

struct UnderlineTabLabel: View {
    let title: String
    let on: Bool
    var small = false
    var ink: Color = STVTheme.text
    var inkOff: Color = STVTheme.secondary
    let ns: Namespace.ID
    var body: some View {
        Text(title)
            .font(.system(size: on ? (small ? 18 : 24) : (small ? 16 : 17), weight: on ? (small ? .bold : .heavy) : .regular))
            .tracking(on && !small ? 0.2 : 0)
            .foregroundStyle(on ? ink : inkOff)
            .lineLimit(1).fixedSize()
            .padding(.bottom, small ? 0 : 6)
            .overlay(alignment: small ? .bottom : .bottomLeading) {
                if on {
                    Capsule().fill(STVTheme.accent)
                        .frame(width: small ? 22 : 26, height: small ? 3 : 4)
                        .offset(x: small ? 0 : 1, y: small ? 8 : 0)
                        .matchedGeometryEffect(id: "underline", in: ns)
                }
            }
            .contentShape(Rectangle())
    }
}

// MARK: - Level 2: glass segmented control (`.seg`)

struct SegmentedTabs<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var idPrefix = "seg"
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { it in
                let on = it == selection
                Button { withAnimation(DS.select) { selection = it } } label: {
                    Text(label(it))
                        .font(.system(size: 14, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? STVTheme.text : STVTheme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(STVTheme.thumb)
                                    .shadow(color: STVTheme.shadowThumb, radius: 3, y: 1.5)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(idPrefix).\(label(it))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 40)
        .stvGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), tint: STVTheme.glass)
    }
}

// MARK: - Level 3: tone chips (`.chip`)

struct ToneChipStyle: ButtonStyle {
    var on: Bool
    /// "全部" / range chips: neutral thumb when selected instead of the accent tint.
    var neutral = false
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        ToneChipBody(label: configuration.label, on: on, neutral: neutral, small: small, pressed: configuration.isPressed)
    }
}

private struct ToneChipBody<L: View>: View {
    let label: L
    let on: Bool
    let neutral: Bool
    let small: Bool
    let pressed: Bool
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        let tint: Color = on ? (neutral ? STVTheme.thumb.opacity(0.50) : STVTheme.accent.opacity(0.22)) : STVTheme.glass
        label
            .font(.system(size: small ? 13 : 14, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? (neutral ? STVTheme.text : STVTheme.accent) : (pressed ? STVTheme.text : STVTheme.secondary))
            .lineLimit(1)
            .padding(.horizontal, small ? 12 : 14)
            .frame(height: small ? 28 : 32)
            .stvGlass(in: Capsule(), tint: tint, backing: on && !neutral ? STVTheme.elevated : STVTheme.surface,
                      interactive: enabled)
            .contentShape(Capsule())
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.38)
            .animation(DS.press, value: pressed)
            .animation(.easeOut(duration: 0.18), value: on)
    }
}

/// Chip with an inline count (`.chip em`).
struct CountLabel: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Text("\(count)").font(.system(size: 12, weight: .medium)).opacity(0.72)
        }
    }
}

/// One horizontally scrolling row of tone chips; the right edge fades out when the row overflows.
struct ChipRow<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    /// Items rendered with the neutral selected look ("全部").
    var neutral: (T) -> Bool = { _ in false }
    var fade = true
    var small = false
    var leading: CGFloat = 16
    var idPrefix = "chip"
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                STVGlassGroup(spacing: 7) {
                    LazyHStack(spacing: 8) {
                        ForEach(items, id: \.self) { it in
                            Button { withAnimation(DS.select) { selection = it } } label: { Text(label(it)) }
                                .buttonStyle(ToneChipStyle(on: it == selection, neutral: neutral(it), small: small))
                                .id(it)
                                .accessibilityIdentifier("\(idPrefix).\(label(it))")
                                .accessibilityAddTraits(it == selection ? .isSelected : [])
                        }
                    }
                    .padding(.leading, leading).padding(.trailing, 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .mask { if fade { FadeMask() } else { Color.black } }
            .onChange(of: selection) { _, it in withAnimation(DS.select) { proxy.scrollTo(it, anchor: .center) } }
        }
    }
}

/// `.chips.fade`: opaque to 84 %, then fades to the right edge.
struct FadeMask: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Buttons

/// `.cbtn`: 36 pt round glass button (`.acc` tinted, `.ov` over imagery).
struct RoundIconButton: View {
    enum Tone { case glass, accent, overlay }
    let systemName: String
    var tone: Tone = .glass
    var size: CGFloat = 36
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone == .accent ? STVTheme.accent : tone == .overlay ? .white : STVTheme.text)
                .frame(width: size, height: size)
                .stvGlass(in: Circle(), tint: tone == .accent ? STVTheme.accent.opacity(0.22) : tone == .overlay ? .black.opacity(0.45) : nil,
                          backing: tone == .overlay ? Color(white: 0.10) : STVTheme.surface, interactive: true)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }
}

/// `.capbtn`: 36 pt capsule with an optional leading / trailing icon.
struct CapsuleLabel: View {
    let title: String
    var icon: String? = nil
    var trailingIcon: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(STVTheme.secondary) }
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1)
            if let trailingIcon { Image(systemName: trailingIcon).font(.system(size: 11, weight: .semibold)).foregroundStyle(STVTheme.secondary) }
        }
        .padding(.horizontal, 14).frame(height: 36)
        .stvGlass(in: Capsule(), tint: STVTheme.glass, interactive: true)
        .contentShape(Capsule())
    }
}

/// `.btn`: accent / white(ink) capsule button; `small` is the 32 pt variant.
struct PillButtonLabel: View {
    enum Tone { case accent, ink, white }
    let title: String
    var icon: String? = nil
    var tone: Tone = .accent
    var small = false
    var height: CGFloat? = nil
    var expand = false
    var body: some View {
        let h = height ?? (small ? 32 : 48)
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: small ? 10 : 12, weight: .bold)) }
            Text(title).font(.system(size: small ? 13 : 16, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(tone == .accent ? STVTheme.onAccent : tone == .ink ? STVTheme.bg : Color(red: 0.067, green: 0.075, blue: 0.090))
        .padding(.horizontal, small ? 14 : 22)
        .frame(maxWidth: expand ? .infinity : nil)
        .frame(height: h)
        .stvGlass(in: Capsule(),
                  tint: tone == .accent ? STVTheme.accent.opacity(0.88) : tone == .ink ? STVTheme.text.opacity(0.88) : .white.opacity(0.88),
                  backing: tone == .accent ? STVTheme.accent : tone == .ink ? STVTheme.text : .white,
                  interactive: true)
        .contentShape(Capsule())
    }
}

/// Scales to 0.97 while pressed (spec "按下").
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : DS.press, value: configuration.isPressed)
    }
}

// MARK: - Navigation bar (`.nav`)

struct DSNavBar<Leading: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: 96, alignment: .leading)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1)
                .frame(maxWidth: .infinity)
            trailing.frame(width: 96, alignment: .trailing)
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }
}

extension DSNavBar where Trailing == EmptyView {
    init(title: String, @ViewBuilder leading: () -> Leading) { self.title = title; self.leading = leading(); self.trailing = EmptyView() }
}

/// The back button every sub-page uses.
struct DSBackButton: View {
    var tone: RoundIconButton.Tone = .glass
    var action: () -> Void
    var body: some View {
        RoundIconButton(systemName: "chevron.left", tone: tone, action: action).accessibilityLabel("返回").accessibilityIdentifier("nav.back")
    }
}

// MARK: - Search bar (`.search`)

struct DSSearchBarLabel: View {
    var placeholder = "搜索你想看的作品"
    var ink: Color? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium))
            Text(placeholder).font(.system(size: 16)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink ?? STVTheme.secondary)
    }
}

// MARK: - Section header (`.sech`)

struct DSSectionHeader<Trailing: View>: View {
    let title: String
    var note: String? = nil
    var inset: CGFloat = 16
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(STVTheme.text)
            if let note { Text(note).font(.system(size: 13)).foregroundStyle(STVTheme.secondary) }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, inset)
    }
}

extension DSSectionHeader where Trailing == EmptyView {
    init(title: String, note: String? = nil, inset: CGFloat = 16) { self.title = title; self.note = note; self.inset = inset; self.trailing = EmptyView() }
}

/// "全部 ›" link label (`.more`).
struct MoreLabel: View {
    var title = "全部"
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 1) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)).padding(.trailing, 3) }
            Text(title)
            if icon == nil { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
        }
        .font(.system(size: 13)).foregroundStyle(STVTheme.secondary)
    }
}

// MARK: - Small labels

/// `.tag`: 20 pt neutral label.
struct DSTag: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(STVTheme.secondary).lineLimit(1)
            .padding(.horizontal, 7).frame(height: 20)
            .background(STVTheme.glass, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// `.st`: status label (ok / warn / muted / accent).
struct DSStatus: View {
    enum Tone { case ok, warn, muted, accent }
    let text: String
    var tone: Tone
    var body: some View {
        let (fg, bg): (Color, Color) = switch tone {
        case .ok: (STVTheme.ok, STVTheme.okSoft)
        case .warn: (STVTheme.accentWarm, STVTheme.warmSoft)
        case .muted: (STVTheme.tertiary, STVTheme.glass)
        case .accent: (STVTheme.accent, STVTheme.accentSoft)
        }
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(fg).lineLimit(1)
            .padding(.horizontal, 7).frame(height: 20)
            .background(bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// `.bar`: 3 pt progress track.
struct DSProgressBar: View {
    var value: Double
    var body: some View {
        GeometryReader { g in
            Capsule().fill(STVTheme.glassBorder)
                .overlay(alignment: .leading) { Capsule().fill(STVTheme.accent).frame(width: g.size.width * min(max(value, 0), 1)) }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// `.mini`: small accent capsule action.
struct MiniButtonLabel: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(STVTheme.accent)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(STVTheme.accentSoft))
            .contentShape(Capsule())
    }
}

/// `.dot` / `.lico`: tinted icon wells.
struct IconWell: View {
    let systemName: String
    var size: CGFloat = 34
    var corner: CGFloat? = nil
    var body: some View {
        Image(systemName: systemName).font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(STVTheme.accent)
            .frame(width: size, height: size)
            .background(STVTheme.accentSoft, in: RoundedRectangle(cornerRadius: corner ?? size / 2, style: .continuous))
    }
}

// MARK: - Posters

/// Rank numeral on a poster (`.pnum`): italic 900, white with a 2 pt medal-coloured offset shadow.
struct PosterRankNumeral: View {
    let rank: Int
    var body: some View {
        let shadow: Color = switch rank {
        case 1: Color(red: 1, green: 0.78, blue: 0.25)
        case 2: Color(red: 0.68, green: 0.73, blue: 0.84)
        case 3: Color(red: 0.86, green: 0.55, blue: 0.32)
        default: .black
        }
        Text("\(rank)").font(.system(size: 36, weight: .black)).italic()
            .foregroundStyle(.white).shadow(color: shadow, radius: 0, x: 2, y: 2)
            .padding(.leading, 7).offset(y: -3)
    }
}

/// 3:4 poster with the bottom scrim, optional rank / 新剧 badges and the episode label (`.poster`).
struct PosterArt: View {
    let series: HGSeries
    var rank: Int? = nil
    var corner: CGFloat = 12
    var showEpisodes = true
    var body: some View {
        Color.clear
            .aspectRatio(series.isLandscapeCover ? 16 / 9 : 3 / 4, contentMode: .fit)
            .overlay { CoverView(url: series.cover, corner: 0) }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.46), .init(color: .black.opacity(0.62), location: 1)],
                               startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) { if let rank { PosterRankNumeral(rank: rank) } }
            .overlay(alignment: .topTrailing) {
                if series.isNew {
                    Text("新剧").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5)).padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showEpisodes, let e = DS.episodes(series) {
                    Text(e).font(.system(size: 11)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                        .padding(.trailing, 8).padding(.bottom, 7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Grid / shelf cell: poster + 14 pt title + 12 pt subtitle (`.cell`).
struct PosterCellView: View {
    let series: HGSeries
    var rank: Int? = nil
    var subtitle: String? = nil
    @Environment(\.zoomNS) private var ns
    var body: some View {
        NavigationLink(value: Route.series(series)) {
            VStack(alignment: .leading, spacing: 0) {
                PosterArt(series: series, rank: rank).zoomSource(series.id, ns)
                Text(series.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1)
                    .padding(.top, 7)
                let sub = subtitle ?? DS.heat(series)
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 12)).foregroundStyle(STVTheme.secondary).lineLimit(1).padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.97))
    }
}

/// Ranked list row from #4 on (`.rrow`): numeral · 62×84 poster · title, tags, episodes + heat.
struct RankListRow: View {
    let series: HGSeries
    let rank: Int
    @Environment(\.zoomNS) private var ns
    var body: some View {
        NavigationLink(value: Route.series(series)) {
            HStack(spacing: 12) {
                Text("\(rank)").font(.system(size: 20, weight: .heavy)).italic()
                    .foregroundStyle(STVTheme.rankColor(rank)).frame(width: 26)
                    .minimumScaleFactor(0.6).lineLimit(1)
                CoverView(url: series.cover, corner: 9).frame(width: 62, height: 84).zoomSource(series.id, ns)
                VStack(alignment: .leading, spacing: 0) {
                    Text(series.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(STVTheme.text).lineLimit(1)
                    let tags = Array((series.tags + (series.isNew ? ["新剧"] : [])).prefix(3))
                    if !tags.isEmpty {
                        HStack(spacing: 5) { ForEach(tags, id: \.self) { DSTag(text: $0) } }.padding(.top, 6)
                    }
                    HStack(spacing: 5) {
                        if let e = DS.episodes(series) { Text(e) }
                        if series.playCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "flame").font(.system(size: 11, weight: .semibold))
                                Text(DS.count(series.playCount))
                            }
                            .fontWeight(.semibold).foregroundStyle(STVTheme.accentWarm)
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(STVTheme.secondary).padding(.top, 7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.98))
    }
}

/// Hairline separator (`+ .row { border-top }`).
struct Hairline: View {
    var body: some View { STVTheme.hairline.frame(height: 1) }
}
