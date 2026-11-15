/*
 * Surge Monitor Pro v3.0.0 — scheduled monitoring and read-only panel, two data sources.
 * Uptime/reload behaviour adapted from fishingworld and Rabbit-Spec SurgePro.js.
 * Metrics: official Surge /v1/metrics API (iOS 5.22+ / Mac 6.9+).
 * No external analytics, dependency, proxy rule or telemetry.
 */
const KEY = 'xy_surge_monitor_pro_v3';
const MAX_SAMPLES = 240;
const NOW = Date.now();
const MiB = 1048576;
const args = parseArgs(typeof $argument === 'string' ? $argument : '');
const MODE = args.mode || 'panel';
const pressed = typeof $trigger !== 'undefined' && $trigger === 'button';
const apiKey = String(args.api_key || '').trim();
const apiPort = /^\d{1,5}$/.test(String(args.api_port || '')) && +args.api_port > 0 && +args.api_port <= 65535 ? +args.api_port : 6171;
const tapAction = args.tap === 'reload' ? 'reload' : 'refresh';
const warnMiB = limitInt(args.warn_mib, 45, 1, 2000);

run().then(value => MODE === 'panel' ? $done(value) : $done()).catch(error => {
  console.log('[Surge Monitor Pro] ' + message(error));
  if (MODE !== 'panel') { $done(); return; }
  $done({
    title: 'Surge 状态监控',
    content: '状态读取失败\n' + message(error) + '\n轻点刷新重试',
    icon: 'exclamationmark.circle.fill',
    'icon-color': '#FF9500'
  });
});

async function run() {
  if (MODE === 'sample' || MODE === 'start') return collect();
  if (MODE === 'reloaded') return recordReload();
  return display();
}
function empty() {
  return {schema:3,epoch:null,samples:[],high:null,low:null,
    reloadCount:0,lastReload:0,lastSuccess:0,lastError:''};
}
function stateRead() {
  const raw = readState();
  if (raw.schema !== 3 || !Array.isArray(raw.samples)) return empty();
  raw.samples = raw.samples.filter(x => x && isValid(x.t) && isValid(x.v) && x.t <= NOW).slice(-MAX_SAMPLES);
  return raw;
}
function newSessionIfNeeded(state, epoch) {
  if (isValid(epoch) && isValid(state.epoch) && Math.abs(epoch-state.epoch) > 30000) state = empty();
  if (isValid(epoch)) state.epoch = epoch;
  return state;
}
async function collect() {
  const [traffic, metrics] = await Promise.all([httpAPI('GET','/v1/traffic'),getMetrics()]);
  const boot = parseStartTime(traffic && traffic.startTime, metric(metrics,'surge_uptime_seconds'));
  const state = newSessionIfNeeded(stateRead(),boot);
  const bytes = metric(metrics,'surge_memory_bytes');
  if (bytes === null) {
    state.lastError = '指标读取失败'; state.lastAttempt = NOW;
    writeState(state); return;
  }
  const value = bytes/MiB;
  const observation={t:NOW,v:value,active:metric(metrics,'surge_active_requests'),
    dns:metric(metrics,'surge_dns_cache_entries')};
  const last=state.samples[state.samples.length-1];
  if(last && last.t === NOW)state.samples[state.samples.length-1]=observation;
  else state.samples.push(observation);
  state.samples=state.samples.slice(-MAX_SAMPLES);
  state.high=isValid(state.high)?Math.max(state.high,value):value;
  state.low=isValid(state.low)?Math.min(state.low,value):value;
  state.lastSuccess=NOW; state.lastAttempt=NOW; state.lastError='';
  state.metricsCache=metrics;
  writeState(state);
}
async function recordReload() {
  const traffic=await httpAPI('GET','/v1/traffic');
  const state=newSessionIfNeeded(stateRead(),parseStartTime(traffic && traffic.startTime,null));
  state.reloadCount=(Number(state.reloadCount)||0)+1;
  state.lastReload=NOW;
  writeState(state);
}
async function display() {
  // The panel never writes monitoring data, even after manual refresh.
  const traffic=await httpAPI('GET','/v1/traffic');
  const epoch=parseStartTime(traffic && traffic.startTime,null);
  const stored=stateRead();
  const sessionChanged=isValid(epoch)&&isValid(stored.epoch)&&Math.abs(epoch-stored.epoch)>30000;
  const state=sessionChanged?empty():stored;
  const history=state.samples;
  const latest=history[history.length-1], previous=history[history.length-2];
  let note='';
  if(pressed && tapAction==='reload') {
    const response=await httpAPI('POST','/v1/profiles/reload');
    note=hasError(response)?'配置重载失败，请检查日志':'已发送配置重载请求';
    // The profile-reloaded event owns the counter.
  }
  const lines=[];
  if(latest) {
    lines.push('▌ 内存  '+toMiB(latest.v)+(previous?delta(latest.v,previous.v):''));
    lines.push('  峰值 '+number(state.high)+' · 最低 '+toMiB(state.low));
    lines.push('  趋势  '+(history.length>=2?sparkline(history):'定时采样积累中'));
    const age=Math.max(0,NOW-latest.t);
    lines.push('  采样 '+clock(latest.t)+' · '+ageText(age)+(age>1080000?'（可能暂停）':''));
  } else {
    lines.push('▌ 内存  等待自动采样');
    lines.push(sessionChanged?'  引擎已重启，旧采样已隔离':
      state.lastError?'  '+state.lastError+'，检查本机 API':'  定时任务启动后生成趋势');
  }
  const boot=isValid(epoch)?epoch:(isValid(state.epoch)?state.epoch:null);
  lines.push('');
  lines.push('▌ 运行  '+(boot?formatDuration((NOW-boot)/1000):'暂无数据'));
  lines.push('  启动 '+(boot?dateTime(boot):'未知')+' · 重载 '+(state.reloadCount||0)+' 次');
  if(latest)lines.push('  活跃请求 '+count(latest.active)+' · DNS '+count(latest.dns));
  if(state.lastReload)lines.push('  最近重载 '+dateTime(state.lastReload));
  lines.push('');
  lines.push('Surge '+versionText(state.metricsCache||{}));
  lines.push('面板更新 '+clock(NOW));
  if(note)lines.push(note);
  return {title:'Surge 状态监控',content:lines.join('\n'),icon:'gauge.medium',
    'icon-color':!latest?'#8E8E93':latest.v>=warnMiB?'#FF9500':'#0A84FF'};
}
function ageText(ms){
  if(ms<60000)return '刚刚';
  if(ms<3600000)return Math.floor(ms/60000)+' 分钟前';
  return Math.floor(ms/3600000)+' 小时前';
}

function getMetrics() {
  // HTTP API returns plaintext; scripting $httpAPI may only decode JSON.
  const useKey = !!apiKey && !/^\{\{\{.*\}\}\}$/.test(apiKey);
  if (!useKey) return httpAPI('GET', '/v1/metrics').then(parseMetrics);
  return new Promise(resolve => {
    try {
      $httpClient.get({
        url: 'http://127.0.0.1:' + apiPort + '/v1/metrics',
        headers: { 'X-Key': apiKey, 'Accept': 'text/plain' },
        timeout: 5
      }, (err, response, body) => {
        const status = Number(response && (response.status || response.statusCode));
        if (err || status !== 200) {
          console.log('[Surge Monitor Pro] metrics request unavailable');
          resolve({});
          return;
        }
        resolve(parseMetrics(body));
      });
    } catch (e) {
      console.log('[Surge Monitor Pro] metrics: ' + message(e));
      resolve({});
    }
  });
}

function parseMetrics(body) {
  if (body && typeof body === 'object') body = body.content || body.body || body.data || '';
  if (typeof body !== 'string') return {};
  const result = {};
  for (const line of body.split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue;
    const kv = /^(surge_(?:memory_bytes|uptime_seconds|active_requests|dns_cache_entries))\s+([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)(?:\s|$)/.exec(line);
    if (kv) { result[kv[1]] = Number(kv[2]); continue; }
    if (line.startsWith('surge_build_info{')) {
      const tag = /version="([^"]*)"/.exec(line);
      const build = /build="([^"]*)"/.exec(line);
      if (tag) result.__version = tag[1];
      if (build) result.__build = build[1];
    }
  }
  return result;
}
function metric(metrics, name) {
  const n = metrics && metrics[name];
  return typeof n === 'number' && Number.isFinite(n) && n >= 0 ? n : null;
}
function parseStartTime(value, fallbackUptime) {
  const start = Number(value);
  if (Number.isFinite(start) && start > 0) return start > 1e12 ? start : start * 1000;
  return fallbackUptime === null ? null : NOW - fallbackUptime * 1000;
}
function httpAPI(method, path) {
  return new Promise(resolve => {
    let finished = false;
    let timer;
    const done = result => {
      if (finished) return;
      finished = true;
      if (timer) clearTimeout(timer);
      resolve(result);
    };
    timer = setTimeout(() => done({ error: '本机 API 超时' }), 4500);
    try { $httpAPI(method, path, null, value => done(value)); }
    catch (err) { done({ error: message(err) }); }
  });
}
function hasError(value) {
  return value === undefined || value === null ||
    (typeof value === 'object' && !!(value.error || value.success === false));
}
function versionText(metrics) {
  const env = typeof $environment === 'object' && $environment ? $environment : {};
  // Prometheus metadata belongs to the running Surge engine. Keep its
  // version/build paired rather than mixing them with scripting metadata.
  const monitoredVersion = cleanVersion(metrics && metrics.__version);
  const monitoredBuild = cleanVersion(metrics && metrics.__build);
  const envVersion = cleanVersion(env['surge-version']);
  const envBuild = cleanVersion(env['surge-build']);
  const version = monitoredVersion || envVersion;
  const build = monitoredVersion ? monitoredBuild : envBuild;
  if (!version) return '版本读取失败';
  return version + (build && !version.includes(build) ? ' (' + build + ')' : '');
}
function cleanVersion(value) {
  if (value === null || value === undefined) return '';
  const text = String(value).trim();
  if (!text || text === 'undefined' || text === 'null') return '';
  return text.replace(/^Surge\s+/i, '').trim();
}
function readState() {
  try {
    const data = JSON.parse($persistentStore.read(KEY) || '{}');
    return data && typeof data === 'object' && !Array.isArray(data) ? data : {};
  } catch (_) { return {}; }
}
function writeState(state) {
  try { $persistentStore.write(JSON.stringify(state), KEY); }
  catch (e) { console.log('[Surge Monitor Pro] persistence: ' + message(e)); }
}
function parseArgs(input) {
  const result = {};
  for (const item of input.split('&')) {
    const pos = item.indexOf('=');
    if (pos < 0) continue;
    try { result[item.slice(0, pos).trim()] = decodeURIComponent(item.slice(pos + 1)); }
    catch (_) { result[item.slice(0, pos).trim()] = item.slice(pos + 1); }
  }
  return result;
}
function isValid(n) { return typeof n === 'number' && Number.isFinite(n) && n >= 0; }
function limitInt(v, fallback, min, max) {
  const num = Number(v);
  return Number.isFinite(num) && num >= min && num <= max ? Math.floor(num) : fallback;
}
function toMiB(v) { return v.toFixed(1) + ' MiB'; }
function number(v) { return isValid(v) ? v.toFixed(1) : '—'; }
function delta(v, previous) {
  if (previous === null) return '';
  const diff = v - previous;
  if (Math.abs(diff) < 0.05) return ' · 持平';
  return ' · ' + (diff > 0 ? '↑' : '↓') + Math.abs(diff).toFixed(1) + ' MiB';
}
function sparkline(samples) {
  const values = samples.map(x => x.v).filter(isValid);
  if (!values.length) return '—';
  const min = Math.min(...values), max = Math.max(...values);
  const glyph = '▁▂▃▄▅▆▇█';
  return values.slice(-20).map(v => glyph[max === min ? 3 : Math.min(7, Math.round(7 * (v - min) / (max - min)))]).join('');
}
function formatDuration(seconds) {
  let s = Math.floor(seconds);
  const days = Math.floor(s / 86400); s %= 86400;
  const hours = Math.floor(s / 3600); s %= 3600;
  const minutes = Math.floor(s / 60); s %= 60;
  return (days ? days + ' 天 ' : '') + (hours || days ? hours + ' 时 ' : '') + minutes + ' 分 ' + s + ' 秒';
}
function dateTime(t) {
  const x = new Date(t);
  return pad(x.getMonth() + 1) + '-' + pad(x.getDate()) + ' ' + pad(x.getHours()) + ':' + pad(x.getMinutes());
}
function clock(t) { const x = new Date(t); return pad(x.getHours()) + ':' + pad(x.getMinutes()) + ':' + pad(x.getSeconds()); }
function pad(v) { return String(v).padStart(2, '0'); }
function count(v) { return v === null ? '—' : String(Math.round(v)); }
function message(v) { return String(v && v.message ? v.message : v).slice(0, 140); }
