// Normalize the Android host's three script contracts to the fixed iOS UI models.
(() => {
 let definition=null,format='',settings={},hint='',pageMemory=new Map();
 const original=WeBox.define;
 globalThis.WeBox=Object.freeze({define(value){original(value);definition=value;format='webox';}});
 const parse=value=>typeof value==='string'?JSON.parse(value):value;
 const field=p=>p.nativeField||{key:p.name,label:p.title||p.name,type:p.type==='enumeration'?'select':p.type==='input'?'text':p.type==='constant'?'text':p.type,default:p.value,required:!!p.required,help:p.description||'',options:(p.enumOptions||[]).map(o=>({label:String(o.title||o.value),value:String(o.value)}))};
 const fields=ps=>(ps||[]).filter(p=>!['page','offset','constant'].includes(p.type)).map(field);
 function seed(){try{if(typeof $app==='object')return $app;if(typeof app==='object')return app;}catch(_){}return {};}
 function detect(){
  if(definition)return 'webox';
  if(typeof WidgetMetadata==='object'&&WidgetMetadata?.modules)return format='widget';
  if(typeof getConfig==='function'&&typeof getCards==='function'&&typeof getTracks==='function'&&typeof getPlayinfo==='function'){
   const app=seed();__weboxXptvAttach(String(app.id||'xptv.'+hint.slice(0,24)),()=>app);return format='xptv';
  }
  throw Error('未识别源协议：需要 WeBox.define、WidgetMetadata，或 getConfig/getCards/getTracks/getPlayinfo 接口');
 }
 function metadata(){
  detect();
  if(format==='webox')return {id:definition.id,name:definition.name,version:definition.version,api:definition.api,format,category:definition.category||'js',icon:definition.icon||null,requires:definition.requires||[],allowHttp:definition.allowHttp!==false,settings:definition.settings?.fields||[],supportsSearch:typeof definition.search==='function'};
  const m=WidgetMetadata;
  return {id:String(m.id||'script.'+hint.slice(0,24)),name:String(m.title||m.name||'JS 内容源'),version:String(m.version||'0'),api:'compat',format,category:m.sourceCategory||'js',icon:m.icon||null,requires:[],allowHttp:true,settings:format==='xptv'?[{key:'__xptv_config',label:'脚本配置',type:'text',default:'{}',help:'仅在脚本需要时填写 JSON 配置'}]:fields(m.globalParams),supportsSearch:!!m.search};
 }
 async function configure(){
  if(format==='webox'){__wbSetSettings(JSON.stringify(settings));const result=await __wbConfigure();globalThis.WidgetMetadata=result;return result;}
  if(format==='xptv')return await __weboxXptvConfigure({...settings,__xptv_config:settings.__xptv_config||'{}'});
  return WidgetMetadata;
 }
 function filter(p){const f=field(p);return {key:f.key,label:f.label,type:'select',default:f.default===undefined?null:String(f.default),options:(f.options||[]).map(o=>({value:String(o.value),label:String(o.label),home:o.home}))};}
 function moduleFilters(m){return (m?.params||[]).filter(p=>p.type==='enumeration').map(filter);}
 function listingModules(){return (WidgetMetadata?.modules||[]).filter(m=>m.type!=='stream');}
 function card(x){return {id:String(x.id??x.link??x.title),title:String(x.title||x.name||'未命名内容'),poster:x.posterPath||x.poster||null,subtitle:x.description||x.subtitle||null,summary:x.overview||null,kind:x.isLive?'live':x.childItems?'series':'unknown',link:x.link||x.id||'',rating:x.rating?String(x.rating):null};}
 function validRows(raw){const p=parse(raw);return Array.isArray(p)?{items:p}:p;}
 async function list(req,search){
  await configure();const page=Number(req.cursor||req.page||1),params={...settings,...req.filters,page,offset:(page-1)*30,__wb_page:page,__wb_surface:req.surface||'browse',keyword:req.query||''};
  let result;
  if(format==='webox')result=await(search?__wbSearch:__wbList)(params);
  else {
   const modules=listingModules(),module=search?WidgetMetadata.search:modules.find(m=>m.id===req.filters?.__module)||modules[0];
   if(!module||typeof globalThis[module.functionName]!=='function')throw Error(search?'此源未提供搜索':'此源没有列表入口');
   for(const p of module.params||[])if(params[p.name]===undefined&&p.value!==undefined)params[p.name]=p.value;
   result=validRows(await globalThis[module.functionName](params));
  }
  result=validRows(result);if(!Array.isArray(result?.items))throw Error('源列表返回格式无效');
  const items=result.items.map(card);const more=result.hasMore===true||(result.hasMore===undefined&&items.length>=30);
  const next=more?String(page+1):null;
  return {items,nextCursor:next,filters:result.filters?.filter(p=>p.type==='enumeration').map(filter)||null};
 }
 function groupEpisodes(rows){
  const groups=new Map();
  for(const x of rows){let gid=x.episodeGroup||'main',eid=String(x.id||x.link||x.title),link=x.link||'';
   if(link.startsWith('webox:episode:')){const id=JSON.parse(decodeURIComponent(link.slice(14)));gid=id.groupId;eid=id.episodeId;}
   if(!groups.has(gid))groups.set(gid,{id:String(gid),name:String(x.episodeGroup||'默认线路'),episodes:[]});
   groups.get(gid).episodes.push({id:eid,name:String(x.title||x.name||'播放'),link,subtitle:x.description||null});
  }
  return Array.from(groups.values());
 }
 async function detail(req){
  await configure();let value;
  if(format==='webox')value=await __wbDetail(req.link||'webox:content:'+encodeURIComponent(req.id));
  else {
   if(typeof loadDetail!=='function')throw Error('此源没有 loadDetail 详情接口');
   value=parse(await loadDetail(req.link||req.id));
  }
  if(Array.isArray(value))return {id:req.id,title:req.title||'',groups:groupEpisodes(value),kind:'series'};
  if(!value||typeof value!=='object')throw Error('源详情返回格式无效');
  const rows=value.childItems||value.episodes||[];
  if(!rows.length&&value.videoUrl)rows.push({id:value.id||req.id,title:'播放',link:value.link||req.link,videoUrl:value.videoUrl});
  return {id:req.id,title:value.title||req.title||'',poster:value.posterPath||value.poster||null,summary:value.overview||value.description||null,kind:value.isLive?'live':'series',groups:groupEpisodes(rows)};
 }
 async function play(req){
  await configure();let raw;
  if(format==='webox'){
   const link=req.episodeLink||'webox:episode:'+encodeURIComponent(JSON.stringify({contentId:req.contentId,groupId:req.groupId,episodeId:req.episodeId}));
   raw=await __wbPlay({link,__wbPurpose:'playback',__weboxRefresh:req.refresh?'true':'false'});
  }else{
   const stream=(WidgetMetadata.modules||[]).find(m=>m.type==='stream')||{functionName:'loadResource'};
   if(typeof globalThis[stream.functionName]!=='function')throw Error('此源未提供播放接口');
   raw=await globalThis[stream.functionName]({...settings,link:req.episodeLink||req.episodeId,id:req.episodeId});
  }
  const result=parse(raw),rows=Array.isArray(result)?result:result.sources||[result];
  if(rows.every(x=>x.processor||x.manifest)&&rows.length)throw Error('该资源需要尚未支持的媒体处理器或内存 HLS');
  return {sources:rows.map((x,i)=>({...x,id:String(x.sourceId||x.id||i),name:String(x.name||'线路 '+(i+1)),url:x.url||null,mime:x.mimeType||x.mime||null,headers:x.headers||{}}))};
 }
 globalThis.__configureHost=(value,id)=>{settings=value||{};hint=id;};
 globalThis.__invoke=async(id,method,req={})=>{
  __iosOperation=id;
  try{
   let value;
   if(method==='metadata')value=metadata();
   else if(method==='filters'){
    const m=await configure(),modules=listingModules();
    value=moduleFilters(m.modules?.find(x=>x.type!=='stream'));
    if(format!=='webox'&&modules.length>1)value.unshift({key:'__module',label:'栏目',type:'select',default:modules[0].id,options:modules.map(m=>({label:m.title||m.id,value:m.id}))});
   }else if(method==='list'||method==='search')value=await list(req,method==='search');
   else if(method==='detail')value=await detail(req);
   else if(method==='play')value=await play(req);
   else throw Error('未支持的源操作：'+method);
   if(JSON.parse(__nativeSync(JSON.stringify({method:'native.cancelled'}))))throw Error('操作已取消');
   webkit.messageHandlers.result.postMessage({id,ok:true,value:value??null});
  }catch(error){webkit.messageHandlers.result.postMessage({id,ok:false,error:String(error.message||error).slice(0,4096)});}
 };
})();
