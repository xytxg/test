var $app={id:'test.xptv.library',title:'影集精选',site:'https://fixture.invalid',ver:'1.0.0'};
async function getConfig(){return JSON.stringify({...$app,tabs:[{name:'全部',ext:{id:'all'}}]})}
async function getCards(){return JSON.stringify({list:[{vod_id:'3',vod_name:'城市微光',vod_pic:'http://127.0.0.1:8765/poster-3.png',vod_remarks:'完结',ext:{id:'3'}}],hasMore:false})}
async function getTracks(){return JSON.stringify([{title:'高清',tracks:[{name:'第01集',ext:{vid:'one'}},{name:'第02集',ext:{vid:'two'}}]},{title:'备用',tracks:[{name:'第01集',ext:{vid:'backup-one'}}]}])}
async function getPlayinfo(){return JSON.stringify({urls:['http://127.0.0.1:8765/sample.mp4'],names:['高清']})}
async function search(){return getCards()}
