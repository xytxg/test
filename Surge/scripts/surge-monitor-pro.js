/*
 * Surge Monitor Pro v2.1.1 — one compact dashboard, two data sources.
 * Uptime/reload behaviour adapted from fishingworld and Rabbit-Spec SurgePro.js.
 * Metrics: official Surge /v1/metrics API (iOS 5.22+ / Mac 6.9+).
 * No external analytics, dependency, proxy rule or telemetry.
 */
const KEY = 'xy_surge_monitor_pro_v1';
const NOW = Date.now();
const MiB = 1048576;
const args = parseArgs(typeof $argument === 'string' ? $argument : '');
const pressed = typeof $trigger !== 'undefined' && $trigger === 'button';
const apiKey = String(args.api_key || '').trim();
const apiPort = /^\d{1,5}$/.test(String(args.api_port || '')) && +args.api_port > 0 && +args.api_port <= 65535 ? +args.api_port : 6171;
const interval = limitInt(args.refresh, 60, 10, 3600);
const tapAction = args.restart === '1' ? 'restart' : ['reload', 'refresh', 'restart'].includes(args.tap) ? args.tap : 'reload';
const warnMiB = limitInt(args.warn_mib, 45, 1, 2000);

run().then(value => $done(value)).catch(error => {
  console.log('[Surge Monitor Pro] ' + message(error));
  $done({
    title: 'Surge 状态监控',
    content: '状态读取失败\n' + message(error) + '\n轻点刷新重试',
    icon: 'exclamationmark.circle.fill',
    'icon-color': '#FF9500'
  });
});

async function run() {
  let state = readState();
  if (!Array.isArray(state.samples)) state.samples = [];
  state.samples = state.samples.filter(x => x && isValid(x.t) && isValid(x.v)).slice(-24);

  const [traffic, metrics] = await Promise.all([
    httpAPI('GET', '/v1/traffic'),
    getMetrics()
  ]);
  const mUptime = metric(metrics, 'surge_uptime_seconds');
  const start = parseStartTime(traffic && traffic.startTime, mUptime);
  if (start && isValid(state.epoch) && Math.abs(start - state.epoch) > 30000) {
    // New engine session: old peak/trend and reload records are not current.
    state.samples = [];
    state.high = null;
    state.low = null;
    state.reloadCount = 0;
    state.lastReload = 0;
    state.pendingRestartUntil = 0;
  }
  if (start) state.epoch = start;

  const currentBytes = metric(metrics, 'surge_memory_bytes');
  const current = currentBytes === null ? null : currentBytes / MiB;
  const last = state.samples.length ? state.samples[state.samples.length - 1] : null;
  const previous = last ? last.v : null;
  if (current !== null) {
    if (last && NOW - last.t < 15000) {
      last.v = current;
      last.t = NOW;
    } else {
      state.samples.push({ t: NOW, v: current });
      state.samples = state.samples.slice(-24);
    }
    state.high = isValid(state.high) ? Math.max(state.high, current) : current;
    state.low = isValid(state.low) ? Math.min(state.low, current) : current;
  }

  let tip = '';
  if (pressed) {
    if (tapAction === 'restart') {
      const until = Number(state.pendingRestartUntil) || 0;
      if (until && NOW <= until) {
        state.pendingRestartUntil = 0;
        writeState(state);
        const reply = await httpAPI('POST', '/v1/stop');
        tip = hasError(reply) ? '停止请求失败，请查看日志' : '已请求停止；仅“始终开启”会自动重启';
      } else {
        state.pendingRestartUntil = NOW + 20000;
        tip = '确认重启：20 秒内再次轻点刷新\n注意：未开启“始终开启”只会停止引擎';
      }
    } else if (tapAction === 'reload') {
      state.pendingRestartUntil = 0;
      const reply = await httpAPI('POST', '/v1/profiles/reload');
      if (hasError(reply)) {
        tip = '配置重载失败，请查看日志';
      } else {
        state.reloadCount = (Number(state.reloadCount) || 0) + 1;
        state.lastReload = NOW;
        tip = '配置已重新加载';
      }
    } else {
      state.pendingRestartUntil = 0;
      tip = '已手动刷新数据';
    }
  } else if (tapAction === 'restart' && Number(state.pendingRestartUntil) > NOW) {
    tip = '等待二次确认：请手动点击刷新';
  }
  if (Number(state.pendingRestartUntil) <= NOW) state.pendingRestartUntil = 0;

  writeState(state);
  return formatPanel({
    current, previous, state, metrics, start, uptime: mUptime, tip
  });
}

function formatPanel(d) {
  const lines = [];
  lines.push('▌ 内存 · ' + (d.current === null ? '暂不可用' : toMiB(d.current)) +
    (d.current === null ? '' : '  ' + delta(d.current, d.previous)));
  if (d.current !== null) {
    lines.push('  峰值 ' + toMiB(d.state.high) + '   最低 ' + toMiB(d.state.low));
    lines.push('  趋势  ' + sparkline(d.state.samples));
  } else {
    const last = d.state.samples.length ? d.state.samples[d.state.samples.length - 1] : null;
    if (last) lines.push('  上次观测 ' + toMiB(last.v) + '（非实时）');
    lines.push('  请检查本机 HTTP API 与 api_key');
  }
  lines.push('');
  const seconds = d.start ? (NOW - d.start) / 1000 : d.uptime;
  lines.push('▌ 运行 · ' + (seconds === null || seconds < 0 ? '暂不可用' : formatDuration(seconds)));
  lines.push('  启动 ' + (d.start ? dateTime(d.start) : '未知') +
    '  ·  重载 ' + (Number(d.state.reloadCount) || 0) + ' 次');
  lines.push('  活跃请求 ' + count(metric(d.metrics, 'surge_active_requests')) +
    '  ·  DNS 缓存 ' + count(metric(d.metrics, 'surge_dns_cache_entries')));
  if (d.state.lastReload) lines.push('  上次重载 ' + dateTime(d.state.lastReload));
  lines.push('');
  lines.push('Surge ' + versionText(d.metrics));
  lines.push('更新 ' + clock(NOW) + '  ·  间隔 ' + interval + ' 秒');
  if (d.tip) lines.push(d.tip);
  return {
    title: 'Surge 状态监控',
    content: lines.join('\n'),
    icon: 'gauge.medium',
    'icon-color': d.current !== null && d.current >= warnMiB ? '#F59E0B' : '#0A84FF'
  };
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
  return value && typeof value === 'object' && !!(value.error || value.success === false);
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
function delta(v, previous) {
  if (previous === null) return '· 首次采样';
  const diff = v - previous;
  return '· ' + (diff > 0.05 ? '↑' : diff < -0.05 ? '↓' : '→') + Math.abs(diff).toFixed(1) + ' MiB';
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
