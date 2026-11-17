/*
 * Surge Monitor Pro 3.2.1
 * Compact read-only dashboard + scheduled sampling + event-based reload tracking.
 * Official /v1/metrics; no MITM, remote telemetry, notifications or engine restart.
 * Storage schema and key stay compatible with v3.0 / v3.1.
 */
'use strict';

const VERSION = '3.2.1';
const STORE_KEY = 'xy_surge_monitor_pro_v3';
const MAX_SAMPLES = 240;
const MiB = 1048576;
const NOW = Date.now();
const args = parseArgs(typeof $argument === 'string' ? $argument : '');
const MODE = args.mode || 'panel';
const VIEW = args.view === 'detail' ? 'detail' : 'compact';
const tapped = typeof $trigger !== 'undefined' && $trigger === 'button';
const tapAction = args.tap === 'reload' ? 'reload' : 'refresh';
const warnMiB = limitInt(args.warn_mib, 45, 1, 2000);
const growthMiB = limitInt(args.growth_mib, 10, 1, 200);
const apiKey = String(args.api_key || '').trim();
const apiPort = limitInt(args.api_port, 6171, 1, 65535);

run().then(result => $done(MODE === 'panel' ? result : undefined)).catch(error => {
  console.log('[Surge Monitor Pro] ' + message(error));
  if (MODE !== 'panel') { $done(); return; }
  $done({
    title: 'Surge 状态监控',
    content: '状态暂不可用\n' + message(error) + '\n请检查本机 API',
    icon: 'exclamationmark.circle.fill',
    'icon-color': '#FF9500'
  });
});

async function run() {
  if (MODE === 'sample' || MODE === 'start') return collect();
  if (MODE === 'reloaded') return recordReload();
  return display();
}

// Persistent storage is shared by cron, event and panel scripts.
function blankState() {
  return {
    schema: 3, epoch: null, samples: [], high: null, low: null,
    reloadCount: 0, lastReload: 0, reloadProbe: null,
    lastSuccess: 0, lastAttempt: 0, lastError: '', failures: 0
  };
}
function readState() {
  let data;
  try { data = JSON.parse($persistentStore.read(STORE_KEY) || '{}'); }
  catch (_) { return blankState(); }
  if (!data || data.schema !== 3 || !Array.isArray(data.samples)) return blankState();
  data.samples = data.samples.filter(x => x && finite(x.t) && finite(x.v) && x.t <= NOW)
    .sort((a, b) => a.t - b.t).slice(-MAX_SAMPLES);
  data.reloadCount = finite(data.reloadCount) ? data.reloadCount : 0;
  data.failures = finite(data.failures) ? data.failures : 0;
  return data;
}
function saveState(state) {
  try { $persistentStore.write(JSON.stringify(state), STORE_KEY); }
  catch (error) { console.log('[Surge Monitor Pro] Storage: ' + message(error)); }
}
function epochReset(state, start) {
  if (finite(start) && finite(state.epoch) && Math.abs(start - state.epoch) > 30000) state = blankState();
  if (finite(start)) state.epoch = start;
  return state;
}

async function collect() {
  const results = await Promise.all([httpAPI('GET', '/v1/traffic'), getMetrics()]);
  const traffic = results[0], metrics = results[1];
  const boot = parseStartTime(traffic && traffic.startTime, value(metrics, 'surge_uptime_seconds'));
  const state = epochReset(readState(), boot);
  const bytes = value(metrics, 'surge_memory_bytes');
  if (bytes === null) {
    state.failures += 1;
    state.lastError = '指标不可用';
    state.lastAttempt = NOW;
    saveState(state);
    return;
  }
  const observation = {
    t: NOW, v: bytes / MiB,
    active: value(metrics, 'surge_active_requests'),
    dns: value(metrics, 'surge_dns_cache_entries')
  };
  const samples = state.samples, last = samples[samples.length - 1];
  // Avoid duplicate startup/cron observations that happen within 30 seconds.
  if (last && NOW - last.t >= 0 && NOW - last.t < 30000) samples[samples.length - 1] = observation;
  else samples.push(observation);
  state.samples = samples.slice(-MAX_SAMPLES);
  state.high = finite(state.high) ? Math.max(state.high, observation.v) : observation.v;
  state.low = finite(state.low) ? Math.min(state.low, observation.v) : observation.v;
  if (state.reloadProbe && state.reloadProbe.after == null && NOW >= state.reloadProbe.at) {
    state.reloadProbe.after = observation.v;
    state.reloadProbe.delta = finite(state.reloadProbe.before)
      ? observation.v - state.reloadProbe.before : null;
  }
  state.lastSuccess = NOW;
  state.lastAttempt = NOW;
  state.lastError = '';
  state.failures = 0;
  state.metricsCache = metrics;
  saveState(state);
}

async function recordReload() {
  const traffic = await httpAPI('GET', '/v1/traffic');
  const state = epochReset(readState(), parseStartTime(traffic && traffic.startTime, null));
  state.reloadCount += 1;
  state.lastReload = NOW;
  const last = state.samples[state.samples.length - 1];
  state.reloadProbe = {
    at: NOW, before: last && NOW - last.t <= 720000 ? last.v : null,
    after: null, delta: null
  };
  saveState(state);
}

async function display() {
  const traffic = await httpAPI('GET', '/v1/traffic');
  const epoch = parseStartTime(traffic && traffic.startTime, null);
  const stored = readState();
  const changed = finite(epoch) && finite(stored.epoch) && Math.abs(epoch - stored.epoch) > 30000;
  const state = changed ? blankState() : stored;
  let note = '';
  if (tapped && tapAction === 'reload') {
    const result = await httpAPI('POST', '/v1/profiles/reload');
    note = hasError(result) ? '重载失败，请查看日志' : '已请求重载配置';
  }
  return renderPanel(state, finite(epoch) ? epoch : state.epoch, changed, note, hasError(traffic));
}

function renderPanel(state, epoch, sessionChanged, note, trafficUnavailable) {
  const samples = state.samples;
  const latest = samples[samples.length - 1], previous = samples[samples.length - 2];
  const lines = [];
  const stale = !!latest && NOW - latest.t > 1080000;
  const failed = state.failures > 0;
  let title = 'Surge 状态监控';
  let growth = null;
  if (latest) {
    // Title uses Surge's native bold text; custom HTML/CSS is not supported.
    title = 'Surge 内存 · ' + fixed(latest.v) + ' MiB';
    const consecutive = previous && latest.t - previous.t <= 720000;
    const thirty = aroundDelta(samples, 'v', 1800000);
    lines.push('变化 ' + (consecutive ? arrow(latest.v - previous.v) : '—') +
      (thirty !== null ? ' · 30分 ' + signed(thirty) : '') + ' MiB');
    const hour = period(samples, 3600000);
    const day = period(samples, 86400000);
    lines.push(hour.length >= 2
      ? '1h均 ' + fixed(average(hour)) + ' · 24h峰 ' + fixed(maxValue(day))
      : '本次峰 ' + fixed(state.high) + ' MiB');
    lines.push('请求 ' + count(latest.active) + ' · DNS ' + count(latest.dns));
    growth = !stale ? continuousGrowth(samples, growthMiB) : null;
    if (growth !== null) lines.push('预警 持续上涨 +' + fixed(growth) + ' MiB');
    if (VIEW === 'detail') {
      if (finite(state.low)) lines.push('本次最低 ' + fixed(state.low) + ' MiB');
      const dnsDelta = aroundDelta(samples, 'dns', 1800000);
      if (dnsDelta !== null) lines.push('DNS近30分 ' + signed(dnsDelta, 0) + ' 条');
    }
  } else {
    lines.push('内存 等待自动采样');
    if (sessionChanged) lines.push('引擎已重启，旧历史已隔离');
  }
  const uptime = finite(epoch) ? Math.max(0, (NOW - epoch) / 1000) : null;
  lines.push('运行 ' + (uptime === null ? '暂无数据' : briefDuration(uptime)) +
    ' · 重载' + state.reloadCount + '次');

  if (VIEW === 'detail') {
    if (finite(epoch)) lines.push('启动 ' + dateTime(epoch));
    if (finite(state.lastReload) && state.lastReload > 0)
      lines.push('最近重载 ' + dateTime(state.lastReload));
    if (state.reloadProbe && finite(state.reloadProbe.delta) &&
        NOW - state.reloadProbe.at <= 3600000)
      lines.push('重载前后 ' + signed(state.reloadProbe.delta) + ' MiB');
    lines.push('有效样本 ' + samples.length + '/' + MAX_SAMPLES);
  }
  if (failed) lines.push('采样异常 连续失败' + state.failures + '次');
  if (latest) lines.push('采样 ' + timeHM(latest.t) + ' · ' +
    (stale ? '数据已过期' : briefAge(NOW - latest.t)));
  else if (state.lastError) lines.push('采样失败 · ' + state.lastError);
  if (trafficUnavailable) lines.push('引擎信息暂不可读');
  lines.push('Surge ' + versionText(state.metricsCache || {}));
  if (note) lines.push(note);
  const alert = failed || stale || growth !== null || (latest && latest.v >= warnMiB);
  return {
    title: title, content: lines.join('\n'),
    icon: alert ? 'exclamationmark.circle.fill' : 'gauge.medium',
    'icon-color': !latest ? '#8E8E93' : alert ? '#FF9500' : '#0A84FF'
  };
}

// Statistics use observed samples only, without invented intermediate points.
function period(samples, duration) {
  const last = samples[samples.length - 1];
  return last ? samples.filter(s => s.t >= last.t - duration) : [];
}
function average(samples) {
  return samples.reduce((sum, s) => sum + s.v, 0) / samples.length;
}
function maxValue(samples) {
  return Math.max(...samples.map(s => s.v));
}
function aroundDelta(samples, key, duration) {
  const current = samples[samples.length - 1];
  if (!current || !finite(current[key])) return null;
  const target = current.t - duration;
  let best = null, diff = Infinity;
  for (const item of samples) {
    if (!finite(item[key]) || item.t >= current.t) continue;
    const distance = Math.abs(item.t - target);
    if (distance < diff) { diff = distance; best = item; }
  }
  return best && diff <= 480000 ? current[key] - best[key] : null;
}
function continuousGrowth(samples, threshold) {
  if (samples.length < 6) return null;
  const last = samples.slice(-6);
  const span = last[5].t - last[0].t;
  if (span < 1500000 || span > 2700000) return null;
  for (let i = 1; i < last.length; i++) {
    const gap = last[i].t - last[i-1].t;
    if (gap <= 0 || gap > 720000 || last[i].v < last[i-1].v - 0.15) return null;
  }
  const increase = last[5].v - last[0].v;
  return increase >= threshold ? increase : null;
}

// Surge's HTTP API is JSON except /v1/metrics (Prometheus plaintext).
function getMetrics() {
  const hasKey = !!apiKey && !/^\{\{\{.*\}\}\}$/.test(apiKey);
  if (!hasKey) return httpAPI('GET', '/v1/metrics').then(parseMetrics);
  return new Promise(resolve => {
    try {
      $httpClient.get({
        url: 'http://127.0.0.1:' + apiPort + '/v1/metrics',
        headers: { 'X-Key': apiKey, 'Accept': 'text/plain' },
        timeout: 5
      }, (error, response, body) => {
        const status = Number(response && (response.status || response.statusCode));
        if (error || status !== 200) { resolve({}); return; }
        resolve(parseMetrics(body));
      });
    } catch (error) {
      console.log('[Surge Monitor Pro] Metrics: ' + message(error));
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
    const match = /^(surge_(?:memory_bytes|uptime_seconds|active_requests|dns_cache_entries))\s+([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)(?:\s|$)/.exec(line);
    if (match) { result[match[1]] = Number(match[2]); continue; }
    if (line.startsWith('surge_build_info{')) {
      const version = /version="([^"]*)"/.exec(line);
      const build = /build="([^"]*)"/.exec(line);
      if (version) result.__version = version[1];
      if (build) result.__build = build[1];
    }
  }
  return result;
}
function httpAPI(method, path) {
  return new Promise(resolve => {
    let completed = false, timer;
    const finish = result => {
      if (completed) return;
      completed = true;
      if (timer) clearTimeout(timer);
      resolve(result);
    };
    timer = setTimeout(() => finish({ error: '本机 API 超时' }), 4500);
    try { $httpAPI(method, path, null, finish); }
    catch (error) { finish({ error: message(error) }); }
  });
}
function hasError(result) {
  return result == null || (typeof result === 'object' &&
    !!(result.error || result.success === false));
}
function value(metrics, key) {
  const num = metrics && metrics[key];
  return finite(num) ? num : null;
}
function parseStartTime(time, uptime) {
  const t = Number(time);
  if (Number.isFinite(t) && t > 0) return t > 1e12 ? t : t * 1000;
  return finite(uptime) ? NOW - uptime * 1000 : null;
}
function versionText(metrics) {
  const env = typeof $environment === 'object' && $environment ? $environment : {};
  const monitored = clean(metrics.__version), build = clean(metrics.__build);
  const envVersion = clean(env['surge-version']), envBuild = clean(env['surge-build']);
  const version = monitored || envVersion;
  const revision = monitored ? build : envBuild;
  return version ? version + (revision && !version.includes(revision) ? ' (' + revision + ')' : '') : '版本未知';
}
function clean(input) {
  const s = input == null ? '' : String(input).trim();
  return !s || s === 'undefined' || s === 'null' ? '' : s.replace(/^Surge\s+/i, '');
}
function parseArgs(input) {
  const params = {};
  for (const item of input.split('&')) {
    const separator = item.indexOf('=');
    if (separator < 0) continue;
    const key = item.slice(0, separator).trim(), raw = item.slice(separator + 1);
    try { params[key] = decodeURIComponent(raw); }
    catch (_) { params[key] = raw; }
  }
  return params;
}
function finite(num) { return typeof num === 'number' && Number.isFinite(num) && num >= 0; }
function limitInt(value, fallback, low, high) {
  const num = Number(value);
  return Number.isFinite(num) && num >= low && num <= high ? Math.floor(num) : fallback;
}
function fixed(num) { return finite(num) ? num.toFixed(1) : '—'; }
function signed(num, decimals = 1) {
  const rounded = num.toFixed(decimals);
  return num >= 0 ? '+' + rounded : rounded;
}
function arrow(delta) {
  if (Math.abs(delta) < 0.05) return '→0.0';
  return (delta > 0 ? '↑' : '↓') + Math.abs(delta).toFixed(1);
}
function count(num) { return finite(num) ? String(Math.round(num)) : '—'; }
function briefAge(ms) {
  if (ms < 60000) return '刚刚';
  if (ms < 3600000) return Math.floor(ms / 60000) + '分前';
  return Math.floor(ms / 3600000) + '小时前';
}
function briefDuration(seconds) {
  let minutes = Math.floor(seconds / 60);
  const days = Math.floor(minutes / 1440); minutes %= 1440;
  const hours = Math.floor(minutes / 60); minutes %= 60;
  return (days ? days + '天' : '') + (hours ? hours + '时' : '') + minutes + '分';
}
function timeHM(ms) {
  const date = new Date(ms);
  return pad(date.getHours()) + ':' + pad(date.getMinutes());
}
function dateTime(ms) {
  const date = new Date(ms);
  return pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' + timeHM(ms);
}
function pad(num) { return String(num).padStart(2, '0'); }
function message(error) { return String(error && error.message ? error.message : error).slice(0, 140); }
