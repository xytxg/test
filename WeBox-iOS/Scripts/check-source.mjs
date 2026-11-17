import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import crypto from 'node:crypto';import zlib from 'node:zlib';
const root=new URL('../',import.meta.url);
async function engine(filename){
 const store=new Map(),waiting=new Map();let counter=0;
 const context=vm.createContext({URL,URLSearchParams,atob,btoa,setTimeout,clearTimeout,TextEncoder,TextDecoder,navigator:{userAgent:'Test WebKit'},crypto:crypto.webcrypto});
 const native=(method,p)=>{
  if(method==='crypto.random')return [...crypto.randomBytes(p.size)];
  if(method==='crypto.encode')return Buffer.from(p.text,p.from==='latin1'?'latin1':p.from||'utf8').toString(p.to||'base64');
  if(method==='crypto.hash')return crypto.createHash(p.algorithm.toLowerCase()).update(Buffer.from(p.text,p.inputEncoding||'utf8')).digest(p.outputEncoding||'hex');
  if(method==='crypto.gzip')return zlib.gzipSync(Buffer.from(p.text,p.inputEncoding||'utf8')).toString(p.outputEncoding||'base64');
  if(method==='crypto.aes'){const key=Buffer.from(p.key,p.keyEncoding||'utf8'),iv=Buffer.from(p.iv,p.ivEncoding||'utf8'),mode=p.mode.toLowerCase(),fn=p.decrypt?'createDecipheriv':'createCipheriv';const cipher=crypto[fn](`aes-${key.length*8}-${mode}`,key,mode==='ecb'?null:iv);cipher.setAutoPadding(p.padding?.toLowerCase()!=='nopadding');return Buffer.concat([cipher.update(Buffer.from(p.text,p.inputEncoding||'utf8')),cipher.final()]).toString(p.outputEncoding||'base64');}
  if(method.endsWith('.get')||method==='storage.getItem')return store.get(p.key)??null;
  if(method.endsWith('.set')||method==='storage.setItem'){store.set(p.key,p.value);return null;}
  if(method.endsWith('.remove')||method==='storage.removeItem'){store.delete(p.key);return null;}
  throw Error('Unmocked sync interface '+method);
 };
 context.prompt=(kind,raw)=>{try{const r=JSON.parse(raw);return JSON.stringify({ok:true,value:native(r.method,r.params)})}catch(e){return JSON.stringify({ok:false,error:e.message})}};
 context.webkit={messageHandlers:{result:{postMessage(r){const w=waiting.get(r.id);waiting.delete(r.id);r.ok?w.resolve(r.value):w.reject(Error(r.error));}},rpc:{postMessage(r){
  assert.equal(r.method,'request');let data;
  if(r.args.url.includes('search/result'))data='{"searchList":[{"video_data":{"series_id":7470092475068071998,"series_name":"测试短剧","episode_cnt":24}}],"hasMore":true}';
  else data='<script>window._ROUTER_DATA={"loaderData":{"player_(series_id)/page":{"seriesDetail":{"series_id":"7470092475068071998","series_name":"测试短剧","vid_list":["11","22"]}}}}</script>';
  queueMicrotask(()=>context.__reply(r.id,{ok:true,value:{statusCode:200,data,headers:{},url:r.args.url}}));
 }}}};
 for(const name of ['bridge','sdk-cheerio','sdk-cryptojs','sdk-widget','sdk-webox','sdk-xptv','source-adapter'])vm.runInContext(fs.readFileSync(new URL(`Resources/${name}.js`,root),'utf8'),context,{filename:name+'.js'});
 context.__configureHost({},filename);vm.runInContext(fs.readFileSync(new URL('Tests/Fixtures/'+filename,root),'utf8'),context,{filename});
 return async(method,request={})=>{const id=String(++counter);const promise=new Promise((resolve,reject)=>waiting.set(id,{resolve,reject}));context.__invoke(id,method,request);return promise;};
}
for(const [filename,format] of [['Screenshots/01-cinema.webox.js','webox'],['Screenshots/02-documents.widget.js','widget'],['Screenshots/03-xptv.js','xptv']]){
 const call=await engine(filename),metadata=await call('metadata');assert.equal(metadata.format,format);
 const filters=await call('filters'),selection=Object.fromEntries(filters.map(f=>[f.key,f.default||f.options[0]?.value]));
 const page=await call('list',{filters:selection,page:1});assert.ok(page.items.length>0);
 const card=page.items[0],detail=await call('detail',{id:card.id,link:card.link,title:card.title}),group=detail.groups[0],episode=group.episodes[0];
 const play=await call('play',{contentId:card.id,groupId:group.id,episodeId:episode.id,episodeLink:episode.link});assert.ok(play.sources[0].url.endsWith('sample.mp4'));
 console.log(`PASS ${format}: manifest → filters → catalog → detail → playback variants`);
}
const original=await engine('hongguo.webox.js');assert.equal((await original('metadata')).id,'dev.webox.hongguo');
const filters=await original('filters');assert.equal(filters[0].options.length,4);
const search=await original('search',{query:'test',filters:{}});assert.equal(search.items[0].id,'7470092475068071998');
const detail=await original('detail',{id:search.items[0].id});assert.equal(detail.groups[0].episodes.length,2);
console.log('PASS attachment compatibility and 64-bit identities');
for(const filename of ['bridge','source-adapter','compute-worker'])new vm.Script(fs.readFileSync(new URL(`Resources/${filename}.js`,root),'utf8'));
const bundleFiles=fs.readdirSync(new URL('Resources',root));assert.ok(!bundleFiles.some(n=>n.endsWith('.webox.js')));
console.log('PASS no bundled content source');
