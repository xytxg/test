import SwiftUI
import UniformTypeIdentifiers

struct SourcePickerView:View{
    @EnvironmentObject private var app:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    @State private var configure:SourceEntry?
    @State private var manage=false
    var visible:[SourceEntry]{app.enabledSources.filter{query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.kindLabel.contains(query)}}
    var body:some View{
        NavigationStack{
            List{
                if app.sources.isEmpty{Section{VStack(alignment:.leading,spacing:8){Text("添加你的第一个源").font(.headline);Text("支持 WeBox、Widget 与 XPTV JS 接口。内容源由你自行提供。").font(.subheadline).foregroundStyle(.secondary)}.padding(.vertical,8);SourceImportActions()}}
                else{
                    Section("内容源"){
                        ForEach(visible){source in
                            HStack(spacing:12){
                                Button{app.select(source);dismiss()}label:{SourceRow(source:source,selected:app.selectedID==source.id,needsConfiguration:app.needsConfiguration(source))}.buttonStyle(.plain)
                                if !(source.manifest?.settings.isEmpty ?? true){Button{configure=source}label:{Image(systemName:"slider.horizontal.3").padding(8)}.buttonStyle(.borderless).accessibilityLabel("配置 "+source.name)}
                            }
                        }
                    }
                    Section{Button{manage=true}label:{Label("管理与导入内容源",systemImage:"externaldrive.badge.plus")}}
                }
            }
            .navigationTitle("切换内容源").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$query,prompt:"搜索名称、视频或电台")
            .toolbar{ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}}}
            .navigationDestination(isPresented:$manage){SourcesView()}
            .sheet(item:$configure){source in NavigationStack{SourceConfigurationView(source:source)}}
        }.sourceImportPresentation().onAppear{ScreenshotSupport.mark("sources")}.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
}
struct SourceRow:View{
    let source:SourceEntry
    var selected=false
    var needsConfiguration=false
    var body:some View{
        HStack(spacing:13){
            ZStack{RoundedRectangle(cornerRadius:11).fill(Color.accentColor.opacity(0.08));if let icon=source.icon,!icon.isEmpty{ArtworkView(reference:icon).clipShape(RoundedRectangle(cornerRadius:11))}else{Image(systemName:source.kindLabel=="视频" ? "play.rectangle":"waveform").font(.title3).foregroundStyle(.tint)}}.frame(width:44,height:44)
            VStack(alignment:.leading,spacing:5){Text(source.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1);Text(needsConfiguration ? "需要配置":source.kindLabel+" · "+source.formatLabel+" · "+source.version).font(.caption).foregroundStyle(needsConfiguration ? Color.orange:Color.secondary).lineLimit(1)}
            Spacer(minLength:8)
            if selected{Image(systemName:"checkmark.circle.fill").foregroundStyle(.tint)}
        }.padding(.vertical,5).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
    }
}
struct SourceImportActions:View{
    @EnvironmentObject private var app:AppModel
    @EnvironmentObject private var importer:SourceImportCoordinator
    var body:some View{
        Group{
            Button{importer.openFiles()}label:{Label("从文件导入 JS",systemImage:"folder")}.disabled(app.importing).accessibilityIdentifier("import-local-js")
            Button{importer.link=true}label:{Label("从链接导入",systemImage:"link")}.disabled(app.importing)
        }
    }
}
struct SourcesView:View{
    @EnvironmentObject private var app:AppModel
    @State private var configure:SourceEntry?
    @State private var remove:SourceEntry?
    var body:some View{
        List{
            Section("添加内容源"){SourceImportActions()}
            Section("已添加 · \(app.sources.count)"){
                ForEach(app.sources){source in
                    Button{if !(source.manifest?.settings.isEmpty ?? true){configure=source}else{app.select(source)}}label:{SourceRow(source:source,selected:app.selectedID==source.id,needsConfiguration:app.needsConfiguration(source)).opacity(source.isEnabled ? 1:0.45)}.buttonStyle(.plain)
                        .swipeActions(edge:.trailing){Button("删除",role:.destructive){remove=source};Button(source.isEnabled ? "停用":"启用"){app.toggleEnabled(source)}.tint(.gray)}
                        .contextMenu{Button("设为当前源"){app.select(source)};if !(source.manifest?.settings.isEmpty ?? true){Button("配置"){configure=source}};Button(source.isEnabled ? "停用":"启用"){app.toggleEnabled(source)}}
                }
                if app.sources.isEmpty{Text("尚未导入内容源").foregroundStyle(.secondary)}
            }
            Section{Text("源脚本定义数据、分类和播放地址；界面保持一致。源仅在本机运行，导入同一 ID 会更新脚本并保留原配置。仅导入你信任的脚本。").font(.footnote).foregroundStyle(.secondary)}
        }.navigationTitle("内容源").navigationBarTitleDisplayMode(.inline)
            .sourceImportPresentation()
            .sheet(item:$configure){source in NavigationStack{SourceConfigurationView(source:source)}}
            .confirmationDialog("删除这个源及其配置？",isPresented:Binding(get:{remove != nil},set:{if !$0{remove=nil}}),titleVisibility:.visible){Button("删除源",role:.destructive){if let remove{app.remove(remove)};remove=nil}}
    }
}
struct SourceConfigurationView:View{
    let source:SourceEntry
    @EnvironmentObject private var app:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var values:[String:JSONValue]=[:]
    @State private var error:String?
    var body:some View{
        Form{
            Section{SourceRow(source:source)}
            ForEach(source.manifest?.settings ?? []){field in
                if field.visible(in:values){Section{editor(field)}footer:{if let help=field.help,!help.isEmpty{Text(help)}}}
            }
            if let error{Section{Text(error).foregroundStyle(.red).font(.subheadline)}}
            if source.manifest?.settings.isEmpty != false{Section{Text("这个源不需要额外配置。").foregroundStyle(.secondary)}}
            Section{LabeledContent("协议",value:source.formatLabel);LabeledContent("版本",value:source.version);if let origin=source.origin{Text(origin).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}}
        }.navigationTitle("源配置").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.topBarLeading){Button("取消"){dismiss()}};ToolbarItem(placement:.topBarTrailing){Button("保存"){do{try app.saveConfiguration(values,source:source);dismiss()}catch{self.error=error.localizedDescription}}.fontWeight(.semibold)}}
            .onAppear{values=app.configuration(source)}
    }
    @ViewBuilder private func editor(_ field:SourceField)->some View{
        let label=field.label+(field.required==true ? " *":"")
        if field.type=="boolean"{Toggle(label,isOn:Binding(get:{values[field.key] == .bool(true)},set:{values[field.key] = .bool($0)}))}
        else if field.type=="select"{Picker(label,selection:Binding(get:{values[field.key]?.text ?? ""},set:{values[field.key] = .string($0)})){ForEach(field.options ?? []){option in Text(option.label).tag(option.value)}}}
        else if field.type=="secret" || field.sensitive==true{SecureField(label,text:stringBinding(field)).textInputAutocapitalization(.never).autocorrectionDisabled()}
        else{TextField(label,text:stringBinding(field),prompt:Text(field.placeholder ?? "")).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(field.type=="number" ? .decimalPad:field.type=="url" ? .URL:.default)}
    }
    private func stringBinding(_ field:SourceField)->Binding<String>{Binding(get:{values[field.key]?.text ?? ""},set:{value in
        if field.type=="number"{values[field.key]=Double(value).map(JSONValue.number)}else{values[field.key] = .string(String(value.prefix(field.maxLength ?? 8192)))}
    })}
}
struct ImportResultsView:View{
    @EnvironmentObject private var app:AppModel
    var body:some View{
        NavigationStack{List{ForEach(app.importResults){item in
            HStack(alignment:.top,spacing:12){Image(systemName:item.error==nil ? "checkmark.circle.fill":"exclamationmark.circle").foregroundStyle(item.error==nil ? Color.green:Color.orange);VStack(alignment:.leading,spacing:6){Text(item.sourceName ?? item.filename).font(.headline);Text(item.error ?? (item.updated ? "脚本已更新，原配置已保留":"已添加到内容源")).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)}}.padding(.vertical,6)
        }}.navigationTitle("导入结果").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarTrailing){Button("完成"){app.importResults=[]}}}}
            .presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
}
