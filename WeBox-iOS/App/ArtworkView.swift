import SwiftUI
import ImageIO

actor ArtworkCache {
    static let shared = ArtworkCache()
    private let images = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage, Error>] = [:]
    private let client = HTTPClient()
    init() { images.totalCostLimit = 48 * 1024 * 1024 }
    func clear() { images.removeAllObjects() }
    func image(_ reference: String) async throws -> UIImage {
        if let cached = images.object(forKey: reference as NSString) { return cached }
        if let task = inflight[reference] { return try await task.value }
        let client = self.client
        let task = Task<UIImage, Error> {
            var address = reference, decoder: [String:Any]?
            if reference.hasPrefix("webox:image:") {
                let data = Data(reference.dropFirst(12).utf8)
                guard let value = try JSONSerialization.jsonObject(with:data) as? [String:Any],let url=value["url"] as? String else {throw WeBoxError("封面格式无效")}
                address=url;decoder=value["decode"] as? [String:Any]
            }
            guard let url=URL(string:address),HTTPClient.valid(url,httpsOnly:false) else {throw WeBoxError("封面地址无效")}
            let response=try await client.fetch(URLRequest(url:url,timeoutInterval:15),limit:8*1024*1024)
            guard response.response.statusCode==200 else {throw WeBoxError("封面加载失败")}
            var data=response.data
            if let decoder {
                guard decoder["algorithm"] as? String == "aes-cbc" else {throw WeBoxError("不支持的封面解码方式")}
                data=try SourceCrypto.aes(data,key:SourceCrypto.decode(decoder["key"] as? String ?? "","hex"),iv:SourceCrypto.decode(decoder["iv"] as? String ?? "","hex"),mode:"CBC",padding:decoder["padding"] as? String == "pkcs7",decrypt:true)
            }
            guard let source=CGImageSourceCreateWithData(data as CFData,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1200,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else {throw WeBoxError("封面图片无法解码")}
            return UIImage(cgImage:cg)
        }
        inflight[reference]=task
        do {let value=try await task.value;inflight.removeValue(forKey:reference);images.setObject(value,forKey:reference as NSString,cost:Int(value.size.width*value.size.height)*4);return value}
        catch{inflight.removeValue(forKey:reference);throw error}
    }
}
struct ArtworkView: View {
    let reference: String?
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image { Image(uiImage:image).resizable().scaledToFill() }
                else { ZStack { Color(uiColor:.secondarySystemFill);Image(systemName:"film").font(.system(size:28,weight:.ultraLight)).foregroundStyle(.tertiary) } }
            }.frame(width:proxy.size.width,height:proxy.size.height).clipped()
        }
        .task(id:reference) {
            image=nil
            if let reference,!reference.isEmpty { let loaded=try? await ArtworkCache.shared.image(reference);if !Task.isCancelled{image=loaded} }
        }
        .accessibilityHidden(true)
    }
    @State private var image: UIImage?
}
struct PosterCard: View {
    let card: Card
    var width: CGFloat? = nil
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ArtworkView(reference:card.poster).aspectRatio(2/3,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:14))
            Text(card.title).font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
            Text(card.subtitle ?? " ").font(.caption).lineLimit(1).foregroundStyle(.secondary)
        }.frame(width:width,alignment:.topLeading).accessibilityElement(children:.combine)
    }
}
struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0,*) { content.glassEffect(.regular.interactive(),in:Capsule()) }
        else { content.background(.ultraThinMaterial,in:Capsule()) }
    }
}
extension View { func glassPill() -> some View { modifier(GlassPill()) } }
extension Double {
    var playbackTime: String {
        guard isFinite,self>=0,self<10000000 else{return "0:00"};let value=Int(self)
        return value>=3600 ? String(format:"%d:%02d:%02d",value/3600,(value%3600)/60,value%60) : String(format:"%d:%02d",value/60,value%60)
    }
}
