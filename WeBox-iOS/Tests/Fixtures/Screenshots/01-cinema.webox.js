// Test data only. This file is copied into the simulator's Documents directory by CI.
(()=>{
 const titles=['山海来信','星际档案','远行的人','城市微光','漫长的夏天','海岸以南','寻山记','时间旅人','一日四季'];
 const card=(i,category)=>({id:String(i+1),title:titles[i],kind:'series',poster:'http://127.0.0.1:8765/poster-'+i+'.png',subtitle:'全 '+(24+i*4)+' 集 · '+category});
 WeBox.define({api:'1.5',id:'test.webox.cinema',name:'光影片库',version:'1.0.0',allowHttp:true,requires:['html','crypto'],
 settings:{fields:[{key:'region',label:'地区',type:'select',default:'all',options:[{label:'全部地区',value:'all'},{label:'中国',value:'cn'}]},{key:'token',label:'访问令牌',type:'secret',required:false,help:'测试可选字段，不需要填写'}]},
 filters:async()=>[{key:'category',label:'分类',type:'select',default:'series',options:[{value:'series',label:'精选剧集',home:true},{value:'movie',label:'周末电影',home:true},{value:'documentary',label:'纪录片',home:true}]}],
 list:async(ctx,req)=>({items:titles.map((_,i)=>card(i,req.filters.category==='movie'?'电影':'剧集')),nextCursor:null}),
 search:async(ctx,req)=>({items:titles.map((_,i)=>card(i,'剧集')).filter(x=>x.title.includes(req.query)),nextCursor:null}),
 detail:async(ctx,req)=>({id:req.id,title:titles[Number(req.id)-1],kind:'series',poster:'http://127.0.0.1:8765/poster-'+(Number(req.id)-1)+'.png',summary:'离开熟悉的街道，沿着海岸去寻找一封未寄出的信。故事关于远方，也关于那些始终留在身边的人。\n\n此片单为离线界面与播放测试数据，不提供商业影视内容。',groups:[{id:'primary',name:'高清线路',episodes:Array.from({length:113},(_,i)=>({id:String(i+1),name:String(i+1).padStart(2,'0')}))},{id:'backup',name:'备用线路',episodes:Array.from({length:113},(_,i)=>({id:'backup-'+(i+1),name:'第'+(i+1)+'集'}))}]}),
 play:async()=>({sources:[{id:'1080',name:'1080p · H.264',url:'http://127.0.0.1:8765/sample.mp4',mime:'video/mp4'},{id:'backup',name:'备用资源',url:'http://127.0.0.1:8765/sample.mp4',mime:'video/mp4'}]})});
})();
