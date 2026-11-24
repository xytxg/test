/* Surge Monitor Pro v3.8.0 simulated runtime tests (no dependencies).
 * node Surge/tests/surge-monitor-pro.test.cjs */
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const filename=path.resolve(__dirname,'../scripts/surge-monitor-pro-v3.8.0.js');
const source=fs.readFileSync(filename,'utf8');
const entry=new vm.Script(source,{filename});
const STORE='xy_surge_monitor_pro_v3', storage=new Map(), logs=[];
let now=1795592400000, boot=now-600000, mib=30, dns=140, active=18;
let build='4500',ver='6.12.0',os='iOS',status=200,bad=false,failOnce=false;
let bans=null;
let requests=0,reloads=0,checks=0;
class FakeDate extends Date{
 constructor(...a){super(...(a.length?a:[now]));}
 static now(){return now;}
}
const ok=(yes,label)=>{assert.ok(yes,label);checks++;};
const saved=()=>JSON.parse(storage.get(STORE)||'null');
function metrics(){
 return ['surge_memory_bytes '+Math.round(mib*1048576),
  'surge_uptime_seconds '+Math.max(0,Math.floor((now-boot)/1000)),
  'surge_active_requests '+active,'surge_dns_cache_entries '+dns,
  'surge_build_info{version="'+ver+'",build="'+build+'",system="'+os+'"} 1',
  'surge_policy_in_bytes_total{policy="DIRECT"} 1234',
  ...(bans===null?[]:['surge_active_bans '+bans])].join('\n');
}
function run(mode='panel',{button=false,view='glance',key='test-key',tap='refresh',
eventName='profile-reloaded'}={}){
 return new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(new Error('Missing $done '+mode)),3000);
  let finished=false;
  const finish=v=>{if(finished)return;finished=true;clearTimeout(timer);resolve(v);};
  const context={
   Date:FakeDate,Promise,setTimeout,clearTimeout,console:{log:x=>logs.push(String(x))},
   $trigger:button?'button':'auto-interval',
   $argument:'mode='+mode+'&view='+view+'&api_key='+key+'&tap='+tap+
     '&api_port=6171&warn_mib=45&growth_mib=10',
   $event:{name:eventName},
   $environment:{system:os,'surge-version':ver,'surge-build':build},
   $persistentStore:{read:k=>storage.get(k)||null,write:(v,k)=>{storage.set(k,v);return true;}},
   $httpAPI:(method,url,body,cb)=>{
    if(url==='/v1/traffic')cb({startTime:boot/1000});
    else if(url==='/v1/metrics'){requests++;cb(bad?{error:'unavailable'}:metrics());}
    else if(url==='/v1/profiles/reload'){reloads++;cb({success:true});}
    else cb({error:'unknown endpoint'});
   },
   $httpClient:{get:(opt,cb)=>{
    requests++;
    assert.equal(opt.url,'http://127.0.0.1:6171/v1/metrics');
    assert.equal(opt.headers['X-Key'],key);
    if(failOnce){failOnce=false;cb('unavailable',null,null);return;}
    cb(null,{status},bad?'':metrics());
   }},
   $done:finish
  };
  try{entry.runInNewContext(context,{timeout:1000});}
  catch(error){clearTimeout(timer);reject(error);}
 });
}
function tick(minutes=6,increase=0){now+=minutes*60000;mib+=increase;dns++;}
(async()=>{
 ok(!/\btimeOf\s*\(/.test(source),'No undefined timeOf');
 ok(!/[▁▂▃▄▅▆▇█▌]/.test(source),'No oversized block glyphs');
 let panel=await run();
 ok(panel.content.includes('等待首次自动采样'),'Empty panel');
 ok(storage.size===0,'Panel read-only before collection');
 await run('start');
 ok(saved().samples.length===1,'Engine-started sample');
 ok(saved().runs.length===1,'Engine run metadata');
 const count0=requests;
 panel=await run();
 ok(requests===count0,'Auto panel uses cached data');
 ok(panel.content.split('\n').length<=6,'Compact native layout');
 const previousStorage=storage.get(STORE);
 mib=31.5;panel=await run('panel',{button:true});
 ok(panel.title.includes('实时内存'),'Button reads live memory');
 ok(requests===count0+1,'Only one on-demand read');
 ok(storage.get(STORE)===previousStorage,'Manual read does not create history');
 tick(6,0.5);await run('sample');
 ok(saved().samples.length===2,'Scheduled sample');
 tick(.25,.1);await run('sample');
 ok(saved().samples.length===2,'30s duplicate merge');
 for(let i=0;i<5;i++){tick(6,2.6);await run('sample');}
 panel=await run();
 ok(panel.content.includes('内存持续上涨'),'Sustained growth warning');
 ok(panel.content.includes('24h峰'),'Peak displayed');
 ok(panel['icon-color']==='#FF9500','Growth warning color');
 const reloadBefore=saved().reloadCount;
 await run('reloaded',{eventName:'manually'});
 ok(saved().reloadCount===reloadBefore,'Ignore unrelated event');
 await run('reloaded');
 ok(saved().reloadCount===reloadBefore+1,'Count actual reload');
 await run('panel',{button:true,tap:'reload'});
 ok(reloads===1 && saved().reloadCount===reloadBefore+1,'No double-count on button reload');
 tick(6,.5);await run('sample');
 panel=await run('panel',{view:'detail'});
 ok(panel.content.includes('重载前后采样'),'Reload delta recorded');
 status=403;tick();await run('sample');
 ok(saved().failures===1 && saved().lastError.includes('密钥'),'403 classified');
 const errorLogs=logs.filter(x=>x.includes('密钥或权限异常')).length;
 tick();await run('sample');
 ok(saved().failures===2,'Consecutive failures');
 ok(logs.filter(x=>x.includes('密钥或权限异常')).length===errorLogs,'Only transition logs');
 status=200;tick();await run('sample');
 ok(saved().failures===0 && saved().recoveryCount===1,'Recovery recorded');
 ok(logs.some(x=>x.includes('采样恢复')),'Recovery logged');
 ok((await run('panel',{view:'detail'})).content.includes('采样已恢复'),'Detail shows recovery');
 tick(19);panel=await run();
 ok(panel.title.includes('历史内存'),'Stale sample title');
 ok(panel['icon-color']==='#FF9500','Stale icon');
 const oldCount=saved().samples.length;
 os='macOS';build='4501';boot=now;tick(6);mib=24.2;await run('start');
 ok(saved().samples.length>=oldCount,'Keep old build observations');
 ok(saved().runs.length>=2,'New build metadata');
 tick(6,.2);await run('sample');
 panel=await run('panel',{view:'detail'});
 ok(panel.content.includes('24h峰 24.4'),'New-run peak excludes previous build');
 ok(panel.content.includes('上个 Build'),'Previous build identified');
 ok(panel.content.includes('Mac 15+ 新网络栈'),'Mac memory attribution note');
 ok(saved().high<30,'Session-high reset on change');
 const state=saved(),last=state.samples[state.samples.length-1];
 state.samples.push({t:last.t,v:1000,active:0,dns:0});
 state.samples.unshift({t:-1000,v:0});
 storage.set(STORE,JSON.stringify(state));
 const before=storage.get(STORE);panel=await run();
 ok(storage.get(STORE)===before,'Panel never rewrites malformed data');
 ok(!panel.content.includes('1000.0 MiB'),'Timestamp conflict retains earlier observation');
 tick(6);boot=now;build='4502';failOnce=true;
 const earlier=requests;await run('start');
 ok(requests===earlier+2,'One bounded startup retry');
 ok(saved().failures===0,'Startup recovered');
 status=503;const intact=storage.get(STORE);
 panel=await run('panel',{button:true});
 ok(panel.content.includes('实时读取失败'),'Live API failure message');
 ok(storage.get(STORE)===intact,'Live failure preserves data');
 status=200;
 tick(6,0);mib=25;await run('sample');
 tick(1,3);const original=storage.get(STORE);
 panel=await run('panel',{button:true});
 ok(panel.title==='实时内存 28.0 MiB','Live headline reflects fresh value');
 ok(panel.content.includes('较上次  ↑ 3.0 MiB'),'Live trend uses fresh endpoint');
 ok(storage.get(STORE)===original,'Live trend leaves history intact');
 bans=2;panel=await run('panel',{button:true});
 ok(panel.content.includes('未授权访问封禁 2 个'),'Official active-bans metric shown');
 ok(panel['icon-color']==='#FF9500','Active bans highlight status');
 ok(storage.get(STORE)===original,'Live bans read remains read-only');
 bans=0;panel=await run('panel',{button:true});
 ok(!panel.content.includes('未授权访问封禁'),'Zero bans do not clutter glance');
 panel=await run('panel',{button:true,view:'detail'});
 ok(panel.content.includes('未授权访问封禁 0 个'),'Detail shows zero');
 bans=null;panel=await run('panel',{button:true,view:'detail'});
 ok(!panel.content.includes('未授权访问封禁'),'Missing metric is not invented');
 status=503;tick(6);await run('sample');
 status=200;panel=await run('panel',{button:true});
 ok(panel.content.includes('实时已读 · 后台连续失败'),'Live success distinguished from background recovery');
 ok(saved().failures===1,'Live success does not erase background failures');
 tick(6);await run('sample');
 ok(saved().failures===0,'Actual background success clears failure');
 bad=true;tick(6);await run('sample',{key:''});
 ok(saved().lastError.includes('API 设置'),'Internal API error not mislabeled as missing key');
 bad=false;tick(6);await run('sample',{key:''});
 ok(saved().failures===0,'Legacy keyless successful sample remains supported');
 console.log('Surge Monitor Pro v3.8.0: '+checks+' assertions passed');
})().catch(e=>{console.error(e);process.exitCode=1;});
