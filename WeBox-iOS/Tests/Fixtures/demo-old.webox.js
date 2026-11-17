// Offline fixture. Only selected with the --screenshots launch argument.
(() => {
 const titles=['等风也等你','山海之间','今天也要好好生活','逆光而行','春日来信','与你的第七天','小城故事','万家灯火','时光有约'];
 const items=titles.map((title,i)=>({id:String(i+1),title,kind:'series',subtitle:'全'+(24+i*4)+'集 · 都市',summary:'在平凡日子里，遇见属于自己的故事。此内容仅用于离线界面演示。'}));
 WeBox.define({api:'1.5',id:'dev.webox.ios.demo',name:'界面演示 · 离线样例',version:'1.0',
 filters:async()=>[{key:'category',label:'分类',type:'select',default:'hot',options:[{value:'hot',label:'热播榜'},{value:'real',label:'真人短剧'},{value:'comic',label:'漫剧'},{value:'ai',label:'AI 短剧'}]}],
 list:async()=>({items,nextCursor:null}),search:async(ctx,req)=>({items:items.filter(x=>x.title.includes(req.query)),nextCursor:null}),
 detail:async(ctx,req)=>({...items.find(x=>x.id===req.id),groups:[{id:'main',name:'演示线路',episodes:Array.from({length:36},(_,i)=>({id:String(i+1),name:'第'+(i+1)+'集'}))}]}),
 play:async(ctx)=>ctx.fail('OFFLINE','界面演示源不提供视频；请切换实际内容源。')});
})();
