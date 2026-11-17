// Native transport and isolated utility hosts. Source/site algorithms belong in scripts.
'use strict';
(() => {
 const pending=new Map(),aborted=new Set(),binaries=new Map();let serial=0,binaryBytes=0;
 globalThis.__iosOperation='';
 const sync=(method,params={})=>{
  if(method==='runtime.capabilities')return {compute:true,dom:true,browserSession:false};
  if(method==='native.cancelled')return aborted.has(__iosOperation);
  if(method==='native.cache.generation')return 1;
  if(method==='native.cache.seconds')return Math.max(0,Math.min(86400,Number(params.seconds)||0));
  if(method.startsWith('url.')) {
   const u=new URL(String(params.url),params.base||undefined);
   if(!['https:','http:'].includes(u.protocol)||u.username||u.password||params.allowHttp===false&&u.protocol!=='https:')throw Error('地址必须是允许的 HTTP(S) URL');
   return method==='url.origin'?u.origin:u.href;
  }
  if(method==='i18n')return params.value;
  if(method.startsWith('binary.'))return binary(method,params);
  const reply=JSON.parse(prompt('webox.native',JSON.stringify({method,params}))||'{}');
  if(!reply.ok)throw Error(reply.error||'原生接口未返回结果');
  return reply.value;
 };
 const toBase64=bytes=>{let s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);};
 const fromBase64=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
 function put(bytes){if(binaryBytes+bytes.byteLength>32*1024*1024)throw Error('二进制存储超过 32 MiB');const id='binary.'+(++serial);binaries.set(id,bytes);binaryBytes+=bytes.byteLength;return id;}
 function binary(method,p){
  const b=binaries.get(p.handle);
  if(method==='binary.concat')return put(Uint8Array.from(p.handles.flatMap(h=>Array.from(binaries.get(h)||[]))));
  if(!b)throw Error('二进制句柄已失效');
  if(method==='binary.size')return b.length;
  const start=p.offset??0,len=p.length??(b.length-start);
  if(!Number.isSafeInteger(start)||!Number.isSafeInteger(len)||start<0||len<0||start+len>b.length)throw Error('二进制区间无效');
  if(method==='binary.read')return toBase64(b.subarray(start,start+len));
  if(method==='binary.slice')return put(b.slice(start,start+len));
  const patches=method==='binary.patch'?p.patches:[{offset:start,data:p.data}];
  for(const patch of patches){const bytes=fromBase64(patch.data);if(!Number.isSafeInteger(patch.offset)||patch.offset<0||patch.offset+bytes.length>b.length)throw Error('二进制写入越界');b.set(bytes,patch.offset);}
  return null;
 }
 globalThis.__nativeSync=raw=>JSON.stringify(sync(JSON.parse(raw).method,JSON.parse(raw).params));
 globalThis.__nativeCryptoResource=()=>'';
 globalThis.__nativeLog=()=>{};
 globalThis.__reply=(id,reply)=>{const entry=pending.get(id);if(!entry)return;pending.delete(id);reply.ok?entry.resolve(reply.value):entry.reject(Error(reply.error));};
 globalThis.__cancel=id=>{aborted.add(id);};
 globalThis.__binaryFromBase64=value=>put(fromBase64(value));
 globalThis.__nativeAsync=raw=>{
  const request=JSON.parse(raw);
  if(request.method==='compute')return compute(request.params);
  if(request.method==='dom.userAgent')return Promise.resolve(navigator.userAgent);
  if(request.method==='dom')return dom(request.params);
  const id=String(++serial),operation=__iosOperation;
  return new Promise((resolve,reject)=>{pending.set(id,{resolve,reject});webkit.messageHandlers.rpc.postMessage({id,method:request.method,args:request.params,operation});});
 };
 function compute(request){
  if(typeof request.code!=='string'||request.code.length>524288)throw Error('计算脚本无效或过大');
  const input={...request,binaries:Object.fromEntries(Object.entries(request.binaries||{}).map(([key,value])=>[key,typeof value==='string'&&binaries.has(value)?toBase64(binaries.get(value)):value]))};
  return new Promise((resolve,reject)=>{
   const url=URL.createObjectURL(new Blob([globalThis.__computeWorkerSource],{type:'text/javascript'})),worker=new Worker(url);
   const timer=setTimeout(()=>finish(null,Error('独立计算超时')),Math.min(60000,(request.timeout??60)*1000));
   function finish(value,error){clearTimeout(timer);worker.terminate();URL.revokeObjectURL(url);error?reject(error):resolve(value);}
   worker.onmessage=e=>e.data.ok?finish(e.data.value):finish(null,Error(e.data.error));
   worker.onerror=e=>finish(null,Error(e.message||'计算失败'));worker.postMessage(input);
  });
 }
 function dom(request){
  let code=request.code;
  if(!code&&request.codeBase64)code=sync('code.decode',request);
  if(typeof code!=='string'||code.length>524288)throw Error('DOM 脚本无效或过大');
  return new Promise((resolve,reject)=>{
   const frame=document.createElement('iframe');frame.sandbox='allow-scripts';frame.style.cssText='position:absolute;inset:0;width:100%;height:100%;border:0;pointer-events:none';
   const timer=setTimeout(()=>finish(null,Error('DOM 计算超时')),Math.min(30000,(request.timeout??20)*1000));
   function finish(value,error){clearTimeout(timer);window.removeEventListener('message',receive);frame.remove();error?reject(error):resolve(value);}
   function receive(event){if(event.source!==frame.contentWindow)return;const d=event.data;if(!d||typeof d!=='object')return;if(d.type===request.errorType)return finish(null,Error('DOM 脚本报告失败'));if(d.type!==request.messageType)return;if(d.blocked)return finish(null,Error('网站不接受当前浏览器环境'));if(JSON.stringify(d).length>65536)return finish(null,Error('DOM 结果过大'));finish({result:d.result,viewport:[window.innerWidth,window.innerHeight],userAgent:navigator.userAgent});}
   window.addEventListener('message',receive);
   const boot='try{(0,eval)('+JSON.stringify(code).replace(/</g,'\\u003c')+')}catch(e){parent.postMessage({type:'+JSON.stringify(request.errorType)+'},"*")}';
   frame.srcdoc='<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\' \'unsafe-eval\'; style-src \'unsafe-inline\'; connect-src \'none\'"><script>'+boot+'<\/script>';
   document.body.appendChild(frame);
  });
 }
 globalThis.fetch=undefined;globalThis.XMLHttpRequest=undefined;globalThis.WebSocket=undefined;
})();
