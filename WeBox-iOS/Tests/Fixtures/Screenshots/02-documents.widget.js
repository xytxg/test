WidgetMetadata={id:'test.widget.documents',title:'原野纪录',version:'1.1.0',modules:[{id:'films',title:'自然与远方',functionName:'catalog',params:[]},{id:'play',title:'播放',functionName:'loadResource',type:'stream',params:[]}],search:{id:'search',functionName:'search',params:[{name:'keyword',type:'input'}]}};
const rows=[{id:'one',type:'url',title:'山海之间',posterPath:'http://127.0.0.1:8765/poster-2.png',description:'自然 · 纪录片',link:'documentary:one'}];
async function catalog(){return rows}
async function search(p){return rows.filter(x=>x.title.includes(p.keyword))}
async function loadDetail(link){return {...rows[0],overview:'独立 Widget 接口测试源。',childItems:[{id:'one',title:'正片',link:'documentary:one',episodeGroup:'原画'}]}}
async function loadResource(){return [{name:'原画',url:'http://127.0.0.1:8765/sample.mp4'}]}
