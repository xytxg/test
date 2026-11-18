WeBox.define({api:'1.5',id:'test.proxy',name:'Proxy Test',version:'1.0.0',allowHttp:false,
    filters:async()=>[],list:async ctx=>{
        const reply=await ctx.http.post('https://webox-transport.test:8766/register?signature=a%2Bb',
            {bytes:'AP94Kz0=',headers:{'Content-Type':'application/octet-stream'},responseType:'base64'});
        if(reply.status!==200)throw Error('HTTP '+reply.status);
        return {items:[{id:'v',title:reply.data,kind:'movie'}],nextCursor:null};
    },
    detail:async()=>({}),play:async()=>({sources:[]})});
