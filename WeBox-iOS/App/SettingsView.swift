import SwiftUI

struct SettingsView:View{
    @EnvironmentObject private var app:AppModel
    @State private var cleared=false
    var body:some View{
        List{
            Section{
                NavigationLink{SourcesView()}label:{Label{HStack{Text("内容源");Spacer();Text("\(app.sources.count)").foregroundStyle(.secondary)}}icon:{Image(systemName:"square.stack.3d.up")}}
                NavigationLink{PlayerSettingsView()}label:{Label("播放设置",systemImage:"play.rectangle")}
            }
            Section("存储"){
                Button{Task{await ArtworkCache.shared.clear();cleared=true}}label:{Label(cleared ? "图片内存缓存已清理":"清理图片内存缓存",systemImage:"photo.stack")}
                Text("收藏和播放记录仅保存在设备上。源配置中的私密字段保存在系统钥匙串。 ").font(.footnote).foregroundStyle(.secondary)
            }
            Section{
                NavigationLink{AboutView()}label:{Label("关于 WeBox",systemImage:"info.circle")}
                LabeledContent("版本",value:"0.2.0 beta").foregroundStyle(.secondary)
            }
        }.navigationTitle("设置")
    }
}
struct PlayerSettingsView:View{
    @EnvironmentObject private var app:AppModel
    var body:some View{
        Form{
            Section("连续观看"){
                Toggle("自动播放下一集",isOn:$app.preferences.autoNext)
                Toggle("预解析并预热下一集",isOn:$app.preferences.prefetchNext)
                Text("接近片尾时准备下一集。切换源或分集会取消旧的预加载任务。 ").font(.footnote).foregroundStyle(.secondary)
            }
            Section("播放与缓冲"){
                Picker("缓冲策略",selection:$app.preferences.bufferMode){Text("均衡").tag("balanced");Text("起播优先").tag("quick");Text("弱网稳定").tag("stable")}
                Picker("默认倍速",selection:$app.preferences.rate){ForEach([Float(0.5),0.75,1,1.25,1.5,2,2.5,3],id:\.self){value in Text("\(value.formatted())×").tag(value)}}
                Text("视频由系统播放器硬件解码。字幕、音轨、AirPlay 和画中画使用系统播放控件。 ").font(.footnote).foregroundStyle(.secondary)
            }
            Section("跳过片头片尾"){
                Stepper("片头 · \(Int(app.preferences.skipIntro)) 秒",value:$app.preferences.skipIntro,in:0...180,step:5)
                Stepper("片尾 · \(Int(app.preferences.skipOutro)) 秒",value:$app.preferences.skipOutro,in:0...180,step:5)
                Text("仅对可确定时长的点播生效。0 秒表示不跳过。 ").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("播放设置").navigationBarTitleDisplayMode(.inline)
    }
}
struct AboutView:View{
    @State private var license=false
    var body:some View{
        List{
            Section{VStack(alignment:.leading,spacing:12){Image(systemName:"play.rectangle.on.rectangle").font(.system(size:42,weight:.light)).foregroundStyle(.tint);Text("WeBox").font(.title.bold());Text("为你的内容源，提供一致的观看体验。").foregroundStyle(.secondary)}.padding(.vertical,15)}
            Section("当前支持"){
                Text("WeBox API 1.0–1.5、Widget JS、XPTV 常用接口")
                Text("HTML / CryptoJS、原生加密、DOM 与独立计算、加密封面、CENC MP4")
                Text("来源配置、跨源搜索、资源切换、续播与下一集预热")
            }.font(.subheadline)
            Section{Text("不包含内容源。浏览器会话、媒体响应处理器、内存 HLS 等扩展当前会提示不兼容；不将不同协议的任意 JS 伪装成可运行源。 ").font(.footnote).foregroundStyle(.secondary)}
            Section{Button("开源许可与第三方声明"){license=true};Link("源码与兼容说明",destination:URL(string:"https://github.com/xytxg/test/tree/main/WeBox-iOS")!)}
        }.navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$license){NavigationStack{ScrollView{Text(licenseText).font(.caption.monospaced()).textSelection(.enabled).padding(20)}.navigationTitle("开源许可").toolbar{ToolbarItem(placement:.topBarTrailing){Button("完成"){license=false}}}}}
    }
    private var licenseText:String{
        guard let folder=Bundle.main.url(forResource:"licenses",withExtension:nil) else{return "GPL-3.0-only · 完整许可与第三方声明见源码仓库。"}
        let urls=(try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []
        return urls.sorted{$0.lastPathComponent<$1.lastPathComponent}.compactMap{try? String(contentsOf:$0,encoding:.utf8)}.joined(separator:"\n\n")
    }
}
