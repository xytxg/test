WeBox.define({api:'1.5',id:'test.paging',name:'Paging',version:'1.0.0',allowHttp:false,filters:async()=>[],
 list:async(ctx,req)=>({items:[{id:req.cursor?'second':'first',title:req.cursor?'Second':'First',kind:'movie'}],nextCursor:req.cursor?null:'opaque-next-token'}),
 detail:async()=>({}),play:async()=>({sources:[]})});
