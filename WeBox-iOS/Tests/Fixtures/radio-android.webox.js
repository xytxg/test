WeBox.define({
 api:"1.3",category:"radio",id:"dev.webox.builtin.radio",name:"电台",version:"1.1.3",requires:["audio"],allowHttp:true,cache:{list:300,detail:60,filters:86400},
 settings:{fields:[{key:'country',label:'本地电台地区',type:'text',default:'CN',maxLength:2,help:'本地热门和新闻资讯使用此地区，例如 CN、US 或 SG'},{key:'server',label:'自定义目录服务',type:'url',default:'',required:false,placeholder:'留空自动选择',help:'通常保持留空；填写 Radio Browser API 服务的根地址'}]},
 async filters(){return [{key:'region',label:'地区',type:'select',default:'local',searchable:true,options:[{label:'默认地区',value:'local'},{label:'全球',value:'all'},{label:'中国',value:'CN'},{label:'美国',value:'US'},{label:'日本',value:'JP'},{label:'新加坡',value:'SG'}]},{key:'tag',label:'类型',type:'select',default:'all',searchable:true,options:[{label:'全部',value:'all'},{label:'音乐',value:'music'},{label:'新闻',value:'news'},{label:'古典',value:'classical'},{label:'爵士',value:'jazz'},{label:'谈话',value:'talk'},{label:'放松',value:'ambient'}]}]},
 async list(ctx,req){return radioList(ctx,req,'')},async search(ctx,req){return radioList(ctx,req,req.query)},
 async detail(ctx,req){const s=await radioStation(ctx,req.id);return {id:req.id,title:s.name,kind:'live',poster:radioIcon(s.favicon),summary:[s.country,radioLanguage(s.language),s.tags,s.bitrate?String(s.bitrate)+' kbps':''].filter(Boolean).join(' · '),groups:[{id:'live',name:'直播',episodes:[{id:s.stationuuid,name:s.name}]}]}},
 async play(ctx,req){const s=await radioStation(ctx,req.contentId);let url=s.url_resolved||s.url;if(!/^https?:\/\//i.test(url||''))ctx.fail('INVALID_RESPONSE','电台未提供 HTTP(S) 直播地址');
 try{const r=await radioRequest(ctx,'/json/url/'+encodeURIComponent(s.stationuuid));if(r.ok&&/^https?:\/\//i.test(r.url||''))url=r.url}catch(e){ctx.signal.throwIfAborted()}
 return {sources:[{id:s.stationuuid,name:s.name,url,mime:(s.hls===1||s.hls===true)?"application/x-mpegURL":"",downloadable:false}]}}
});
let radioServers=null,radioPreferred='';
function radioIcon(raw){return /^https?:\/\//i.test(raw||'')?raw:''}
function radioFatal(error){return /RATE_LIMITED|CONFIG_REQUIRED|INVALID_RESPONSE|out of memory/i.test(String(error.message))}
async function radioRequest(ctx,path){
 const custom=String(ctx.settings.server||'').trim().replace(/\/+$/,'');
 if(custom&&!/^https?:\/\/[^/?#]+$/i.test(custom))ctx.fail('CONFIG_REQUIRED','目录服务请填写根地址，不包含路径、参数或片段',{fields:['server']});
 if(!custom&&!radioServers){
  try{const value=await ctx.store.get('radio.preferred.server');if(/^https:\/\/[a-z0-9-]+\.api\.radio-browser\.info$/i.test(value||''))radioPreferred=value}catch(e){ctx.signal.throwIfAborted();if(radioFatal(e))throw e}
  radioServers=Array.from(new Set([radioPreferred,'https://de1.api.radio-browser.info','https://at1.api.radio-browser.info'].filter(Boolean)));
 }
 let servers=custom?[custom]:radioServers,last=0;const tried=new Set();
 for(let phase=0;phase<(custom?1:2);phase++){
  for(const server of servers.slice(0,phase===0?2:1)){
   ctx.signal.throwIfAborted();tried.add(server);
   try{
    const r=await ctx.http.get(server+path,{responseType:'text',timeoutMs:custom?7000:4500,headers:{'User-Agent':'WeBox-Radio/1.0'}});last=r.status;
    if(r.status===200){
     const data=radioJson(ctx,r);
     if(!custom){
      radioServers=[server,...radioServers.filter(x=>x!==server)];
      if(radioPreferred!==server){try{await ctx.store.set('radio.preferred.server',server)}catch(e){ctx.signal.throwIfAborted();if(radioFatal(e))throw e}radioPreferred=server}
     }
     return data;
    }
    if(r.status===429)ctx.fail('RATE_LIMITED','电台目录暂时限制请求，请稍后重试',{httpStatus:429,retryAfterSeconds:60});
   }catch(e){ctx.signal.throwIfAborted();if(radioFatal(e))throw e}
  }
  if(phase===0&&!custom){
   // Discovery is recovery, not a prerequisite for the first visible station row.
   try{
    const r=await ctx.http.get('https://all.api.radio-browser.info/json/servers',{responseType:'text',timeoutMs:2500});const data=radioJson(ctx,r);
    servers=Array.isArray(data)?data.map(x=>x.name).filter(x=>/^[a-z0-9-]+\.api\.radio-browser\.info$/i.test(x)).map(x=>'https://'+x).filter(x=>!tried.has(x)):[];
   }catch(e){ctx.signal.throwIfAborted();if(/out of memory/i.test(String(e.message)))throw e;servers=[]}
  }
 }
 ctx.fail('NETWORK',last?'电台目录返回 HTTP '+last:'无法连接电台目录，请检查网络');
}
async function radioList(ctx,req,query){const offset=req.cursor?Number(req.cursor):0;if(!Number.isSafeInteger(offset)||offset<0||offset>100000)ctx.fail('INVALID_RESPONSE','电台分页无效');const limit=req.surface==='home'?9:30;const p=['hidebroken=true','limit='+limit,'offset='+offset,'order=clickcount','reverse=true'];let region=req.filters.region||'local';if(region==='local')region=String(ctx.settings.country||'CN').toUpperCase();if(region!=='all'){if(!/^[A-Z]{2}$/.test(region))ctx.fail('CONFIG_REQUIRED','默认国家请填写两位代码',{fields:['country']});p.push('countrycode='+region)}if(req.filters.tag&&req.filters.tag!=='all')p.push('tag='+encodeURIComponent(req.filters.tag));if(query)p.push('name='+encodeURIComponent(query));const rows=await radioRequest(ctx,'/json/stations/search?'+p.join('&'));if(!Array.isArray(rows))ctx.fail('INVALID_RESPONSE','电台目录未返回列表');const seen=new Set();return {items:rows.slice(0,limit).filter(s=>s.stationuuid&&s.name&&!seen.has(s.stationuuid)&&seen.add(s.stationuuid)).map(s=>({id:s.stationuuid,title:s.name.slice(0,240),kind:'live',poster:radioIcon(s.favicon),subtitle:[s.country,String(s.tags||'').split(',').filter(Boolean).slice(0,2).join(' / '),s.bitrate?String(s.bitrate)+' kbps':''].filter(Boolean).join(' · ').slice(0,1024)})),nextCursor:req.surface!=='home'&&rows.length===limit?String(offset+rows.length):null}}
async function radioStation(ctx,id){if(!/^[a-f0-9-]{36}$/i.test(id))ctx.fail('NOT_FOUND','电台身份无效');const rows=await radioRequest(ctx,'/json/stations/byuuid/'+encodeURIComponent(id));const s=Array.isArray(rows)&&rows.find(x=>x.stationuuid===id);if(!s)ctx.fail('NOT_FOUND','电台已移除或暂不可用');return s}

function radioJson(ctx,response){
 if(response.status!==200)return null;
 const raw=response.data;
 if(typeof raw!=='string')ctx.fail('INVALID_RESPONSE','电台目录未返回文本数据');
 if(raw.length>524288)ctx.fail('INVALID_RESPONSE','电台目录返回的数据异常偏大，请检查目录服务',{stage:'radio-response'});
 try{return JSON.parse(raw)}catch(e){if(/out of memory/i.test(String(e.message)))throw e;ctx.fail('INVALID_RESPONSE','电台目录返回的数据格式无效',{stage:'radio-response'})}
}

function radioLanguage(raw){const names={chinese:'中文',mandarin:'普通话',cantonese:'粤语',english:'英语',japanese:'日语',korean:'韩语',french:'法语',german:'德语',spanish:'西班牙语'};return String(raw||'').split(',').map(x=>x.trim()).filter(Boolean).slice(0,3).map(x=>names[x.toLowerCase()]||x).join(' / ')}
