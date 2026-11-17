'use strict';
(() => {
  let definition = null, serial = 0;
  const pending = new Map(), signals = new Map();
  const native = (method, args) => {
    const result = JSON.parse(prompt('webox.native', JSON.stringify({method,args})) || '{}');
    if (!result.ok) throw Error(result.error || 'Native bridge failed');
    return result.value;
  };
  // All network traffic goes through the native, bounded transport.
  globalThis.fetch = undefined;
  globalThis.XMLHttpRequest = undefined;
  globalThis.WebSocket = undefined;
  Object.defineProperty(globalThis, 'crypto', {value: {getRandomValues(array) {
    if (!ArrayBuffer.isView(array) || array instanceof Float32Array || array instanceof Float64Array || array.byteLength > 65536) throw Error('Invalid random array');
    new Uint8Array(array.buffer,array.byteOffset,array.byteLength).set(native('random',[array.byteLength])); return array;
  }}, configurable: true});
  globalThis.WeBox = {define(value) {
    if (definition) throw Error('Only one source per file');
    if (!value || !/^1\.[0-5]$/.test(value.api) || !value.id || !value.name || typeof value.list !== 'function') throw Error('Unsupported WeBox source definition');
    definition = value;
  }};
  function rpc(method, args, operation) {
    const id = String(++serial);
    return new Promise((resolve,reject) => {
      pending.set(id,{resolve,reject});
      webkit.messageHandlers.rpc.postMessage({id,method,args,operation});
    });
  }
  globalThis.__reply = (id, result) => {
    const entry=pending.get(id); if(!entry) return; pending.delete(id);
    result.ok ? entry.resolve(result.value) : entry.reject(Error(result.error));
  };
  globalThis.__cancel = id => { const s=signals.get(id); if(s)s.aborted=true; };
  globalThis.__invoke = async (id, method, request) => {
    const signal = {aborted:false, throwIfAborted(){if(this.aborted)throw Error('操作已取消');}};
    signals.set(id,signal);
    const crypto = Object.fromEntries(['hash','gzip','aesEncrypt','aesDecrypt'].map(name=>[name,(...args)=>native(name,args)]));
    const ctx = {signal,crypto,capabilities:{cardSummary:true,cencMp4:true,crypto:true},
      http:{get:(url,options={})=>rpc('http',{url,options,verb:'GET'},id),post:(url,options={})=>rpc('http',{url,options,verb:'POST'},id)},
      store:{get:key=>rpc('store.get',{key},id),set:(key,value)=>rpc('store.set',{key,value},id),remove:key=>rpc('store.remove',{key},id)},
      fail:(code,message)=>{throw Error(code+': '+message);},log:()=>{},
      now:()=>Date.now()};
    try {
      if(!definition)throw Error('文件没有调用 WeBox.define');
      let result;
      if(method==='metadata') {
        result={id:definition.id,name:definition.name,api:definition.api,version:definition.version||'0',requires:definition.requires||[],allowHttp:!!definition.allowHttp};
      } else {
        if(typeof definition[method]!=='function')throw Error('此源不支持 '+method);
        result=await definition[method](ctx,request||{});
      }
      signal.throwIfAborted();
      webkit.messageHandlers.result.postMessage({id,ok:true,value:result===undefined?null:result});
    } catch(error) {webkit.messageHandlers.result.postMessage({id,ok:false,error:String(error.message||error)});}
    finally {signals.delete(id);}
  };
})();
