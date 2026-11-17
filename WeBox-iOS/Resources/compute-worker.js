'use strict';
self.onmessage=async function(event){
  try{
    const request=event.data,binaries=Object.create(null);
    for(const [name,value] of Object.entries(request.binaries||{})){
      const raw=atob(value),bytes=new Uint8Array(raw.length);
      for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i);
      binaries[name]=bytes;
    }
    const invoke=new Function('input','binaries','"use strict";return ('+request.code+')(input,binaries);');
    const value=await invoke(request.input,binaries);
    const reply=JSON.stringify({ok:true,value:value===undefined?null:value});
    if(reply.length>1024*1024)throw Error('计算结果超过 1 MiB');
    self.postMessage(JSON.parse(reply));
  }catch(error){self.postMessage({ok:false,error:String(error&&error.message||error).slice(0,512)});}
};
