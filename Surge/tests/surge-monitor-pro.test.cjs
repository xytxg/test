'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const srcFile = path.resolve(__dirname, '../scripts/surge-monitor-pro-v3.3.0.js');
const source = fs.readFileSync(srcFile, 'utf8');
const runner = new vm.Script(source, {filename:srcFile});
const store = new Map();
let clock = 1794902400000;
let start = Math.floor((clock - 600000) / 1000);
let mib = 30.0;
let dns = 200;
let badMetrics = false;
let metricsRequests = 0;
let reloads = 0;
let tests = 0;
class FakeDate extends Date {
  constructor(...v) { super(...(v.length ? v : [clock])); }
  static now() { return clock; }
}
const metrics = () => [
  'surge_memory_bytes ' + Math.round(mib * 1048576),
  'surge_active_requests 35',
  'surge_dns_cache_entries ' + dns,
  'surge_build_info{build="4032",version="6.100.0"} 1'
].join('\n');
const saved = () => JSON.parse(store.get('xy_surge_monitor_pro_v3') || 'null');
const check = (condition, description) => { assert.ok(condition, description); ++tests; };
function run(mode, {key='',tap='refresh',view='compact',button=false}={}) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('No $done: '+mode)), 1000);
    const end = out => {clearTimeout(timer);resolve(out);};
    const context = {
      Date:FakeDate,Promise,setTimeout,clearTimeout,console:{log(){}},
      $trigger:button?'button':'auto-interval',
      $argument:'mode='+mode+'&api_port=6171&api_key='+key+'&tap='+tap+'&view='+view,
      $environment:{'surge-version':'6.100.0','surge-build':'4032'},
      $persistentStore:{read:k=>store.get(k)||null,write:(v,k)=>{store.set(k,v);return true;}},
      $httpAPI:(method,url,body,cb)=>{
        if(url==='/v1/traffic') cb({startTime:start});
        else if(url==='/v1/metrics'){metricsRequests++;cb(badMetrics?{error:'failed'}:metrics());}
        else if(url==='/v1/profiles/reload'){reloads++;cb({success:true});}
        else cb({error:'Unknown path'});
      },
      $httpClient:{get:(opts,cb)=>{
        assert.equal(opts.url,'http://127.0.0.1:6171/v1/metrics');
        cb(null,{status:200},badMetrics?'':metrics());
      }},
      $done:end
    };
    try {runner.runInNewContext(context,{timeout:1000});}
    catch(err){clearTimeout(timer);reject(err);}
  });
}
(async()=>{
  check(!/[▁▂▃▄▅▆▇█▌]/.test(source),'No huge block glyphs in panel');
  check(!/\btimeOf\s*\(/.test(source),'No timeOf regression');
  let panel=await run('panel');
  check(panel.content.includes('等待自动采样'),'Initial state');
  check(saved()===null,'Panel remains read-only before sampling');
  await run('start');
  check(saved().samples.length===1,'Startup observation');
  const firstReads=metricsRequests;
  await run('panel',{button:true});
  check(metricsRequests===firstReads,'Refresh performs no metric reads');
  check(saved().samples.length===1,'Refresh does not append data');
  clock+=25000; mib=30.4;
  await run('sample');
  check(saved().samples.length===1,'Coalesce near-duplicate samples');
  for(let i=0;i<5;i++){clock+=360000;mib+=2.2;dns+=4;await run('sample');}
  panel=await run('panel');
  check(panel.content.includes('预警 持续上涨'),'Sustained memory growth alert');
  check(panel.content.includes('24h峰'),'24 hour peak in compact view');
  check(panel.title.includes('Surge 内存 · ') && panel.title.includes('MiB'),
    'Native bold title contains the headline memory metric');
  check(panel.content.split('\n').length <= 7,
    'Default layout stays within seven lines including warning');
  check(panel.content.includes('DNS '),'DNS stats');
  check(panel.content.includes('Surge 6.100.0 (4032)'),'Version metadata');
  check(panel.content.split('\n').every(x=>x.length<44),'No excessive line lengths');
  check(panel['icon-color']==='#FF9500','Growth warning changes icon color');
  const glance=await run('panel',{view:'glance'});
  check(glance.title.startsWith('内存 '),'Glance uses the actual bold title');
  check(glance.content.includes('近30分钟'),'Glance shows 30-minute trend');
  check(glance.content.includes('24h峰'),'Glance still shows observed peak');
  check(glance.content.split('\n').length <= 5,'Glance has at most five lines, including warning');
  check(!glance.content.includes('Surge 6.'),'Glance hides secondary version text');
  const len=saved().samples.length;
  await run('reloaded');
  clock+=360000;mib+=1;await run('sample');
  check(saved().reloadCount===1,'Reload count event-based');
  const detailed=await run('panel',{view:'detail'});
  check(detailed.content.includes('重载前后 +1.0 MiB'),'Detail reload comparison');
  check(detailed.content.includes('本次最低 ') && detailed.content.includes('有效样本 '),
    'Detailed view retains minimum and sample count');
  await run('panel',{button:true,tap:'reload'});
  check(reloads===1&&saved().reloadCount===1,'Manual reload avoids double count');
  badMetrics=true;clock+=360000;await run('sample');
  check(saved().failures===1&&saved().samples.length===len+1,'Failure preserves good samples');
  check((await run('panel')).content.includes('采样异常 连续失败1次'),'Failure shown');
  badMetrics=false;clock+=360000;await run('sample',{key:'local-only'});
  check(saved().failures===0,'Successful authenticated request resets failures');
  clock+=1140000;
  check((await run('panel')).content.includes('数据已过期'),'Stale sample warning');
  start+=3600;
  check((await run('panel')).content.includes('旧历史已隔离'),'Restart isolation before new sample');
  await run('start');
  check(saved().samples.length===1&&saved().reloadCount===0,'Restart resets session');
  console.log('Surge Monitor Pro v3.3.0: '+tests+' regression checks passed');
})().catch(err=>{console.error(err);process.exitCode=1;});
