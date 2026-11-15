/*
 * Surge Monitor Pro - memory and uptime panels
 * Based on the uptime-panel behaviour in Rabbit-Spec/Surge/Module/Panel/Surge-Pro/Moore/SurgePro.js
 * Original authors: @fishingworld, @Rabbit-Spec; combined implementation: xytxg/test.
 * Surge iOS 5.22.0+ / Mac 6.9.0+ for /v1/metrics.
 * No external service, telemetry or automatic profile changes.
 */

const STORAGE_KEY = 'xy_surge_monitor_pro_v1';
const MiB = 1048576;
const now = Date.now();
const args = parseArguments(typeof $argument === 'string' ? $argument : '');
const panelName = typeof $input !== 'undefined' && $input && $input.panelName ? $input.panelName : '';
const isMemory = panelName === 'XY_Surge_Memory' || (!panelName && args.panel === 'memory');
const pressed = typeof $trigger !== 'undefined' && $trigger === 'button';
const allowRestart = args.restart === '1';
const port = validPort(args.api_port) ? +args.api_port : 6171;
const apiKey = args.api_key || '';
const updateSeconds = Math.max(10, Math.min(3600, parseInt(args.refresh, 10) || 60));

main().then(result => $done(result)).catch(err => {
  console.log('[Surge Monitor Pro] ' + safeError(err));
  $done({
    title: isMemory ? 'Surge 内存监控' : 'Surge 运行时长',
    content: '读取失败，请检查 Surge 日志\n' + safeError(err),
    icon: 'exclamationmark.circle.fill', 'icon-color': '#FF9500'
  });
});

async function main() {
  let state = loadState();
  let reloadNote = '';
  if (!isMemory && pressed) {
    // Retain the upstream Surge Pro panel's manual profile-reload action.
    const r = await api('POST', '/v1/profiles/reload');
    if (!isApiError(r)) {
      state.reloadCount = (Number(state.reloadCount) || 0) + 1;
      state.lastReload = now;
      reloadNote = '配置已重新加载';
    } else {
      reloadNote = '重载失败，请检查日志';
    }
  }

  const traffic = await api('GET', '/v1/traffic');
  let epoch = Number(traffic && traffic.startTime);
  epoch = Number.isFinite(epoch) && epoch > 0 ? epoch * (epoch > 1e12 ? 1 : 1000) : null;
  const metrics = await getMetrics();
  const uptime = metricNumber(metrics, 'surge_uptime_seconds');
  if (!epoch && uptime !== null) epoch = now - uptime * 1000;
  // Separate each engine session. Reloading a configuration is not a restart.
  if (epoch && state.epoch && Math.abs(epoch - state.epoch) > 30000) {
    state.samples = [];
    state.high = null;
    state.low = null;
    state.pendingRestartUntil = 0;
    state.reloadCount = 0;
    state.lastReload = 0;
  }
  if (epoch) state.epoch = epoch;
  if (!Array.isArray(state.samples)) state.samples = [];

  const memBytes = metricNumber(metrics, 'surge_memory_bytes');
  let previous = state.samples.length ? state.samples[state.samples.length - 1].v : null;
  let current = memBytes === null ? null : memBytes / MiB;
  if (current !== null) {
    const last = state.samples[state.samples.length - 1];
    // Merge near-simultaneous refreshes; samples remain bounded in storage.
    if (last && now - last.t < 15000) last.v = current;
    else state.samples.push({ t: now, v: current });
    state.samples = state.samples.slice(-24);
    state.high = state.high === null || !Number.isFinite(state.high) ? current : Math.max(state.high, current);
    state.low = state.low === null || !Number.isFinite(state.low) ? current : Math.min(state.low, current);
  }
  let result;
  if (isMemory) {
    let actionMessage = '';
    if (pressed && allowRestart) {
      if (state.pendingRestartUntil && now <= state.pendingRestartUntil) {
        state.pendingRestartUntil = 0;
        saveState(state);
        // /v1/stop stops the engine; it restarts only when Always On is enabled.
        const r = await api('POST', '/v1/stop');
        actionMessage = isApiError(r)
          ? '停止请求未获确认；检查运行状态'
          : '已发送停止请求；仅“始终开启”会自动重启';
      } else {
        state.pendingRestartUntil = now + 20000;
        actionMessage = '确认停止：20 秒内再次点右上角刷新\n⚠ 非“始终开启”模式将保持关闭';
      }
    } else if (state.pendingRestartUntil && now <= state.pendingRestartUntil && allowRestart) {
      actionMessage = '等待确认：20 秒内再次手动刷新';
    } else {
      state.pendingRestartUntil = 0;
    }
    result = {
      title: 'Surge 内存监控',
      content: memoryContent(current, previous, state, metrics, actionMessage),
      icon: 'memorychip.fill', 'icon-color': '#0785EA'
    };
  } else {
    result = {
      title: 'Surge 运行时长',
      content: uptimeContent(epoch, uptime, state, reloadNote),
      icon: 'info.circle.fill', 'icon-color': '#0785EA'
    };
  }
  saveState(state);
  return result;
}

function memoryContent(current, previous, state, metrics, actionMessage) {
  const active = metricNumber(metrics, 'surge_active_requests');
  const dns = metricNumber(metrics, 'surge_dns_cache_entries');
  const lines = current === null ? [
    '当前内存  暂不可用',
    '请配置本机 HTTP API 密钥与端口',
    '版本要求：iOS 5.22+ / Mac 6.9+',
    '未取得指标，不显示推算值'
  ] : [
    '当前内存  ' + fmtMiB(current),
    '观测峰值  ' + fmtMiB(state.high) + ' · 最低 ' + fmtMiB(state.low),
    '较上次  ' + (previous === null ? '首次采样' : fmtDelta(current - previous)),
    '活动连接  ' + (active === null ? '—' : Math.round(active)) + ' · DNS 缓存 ' + (dns === null ? '—' : Math.round(dns)),
    '近期采样  ' + chart(state.samples)
  ];
  lines.push('更新 ' + timeOf(now) + ' · 自动刷新 ' + updateSeconds + ' 秒');
  if (actionMessage) lines.push('', actionMessage);
  else if (!allowRestart) lines.push('', '刷新按钮只更新数据，不会停止 Surge');
  return lines.join('\n');
}

function uptimeContent(epoch, uptime, state, reloadNote) {
  const seconds = epoch ? (now - epoch) / 1000 : uptime;
  const v = typeof $environment === 'object' && $environment ? $environment : {};
  const version = v['surge-version'] || '未知';
  const build = v['surge-build'] || '';
  const lines = [
    '已运行 ' + (seconds === null || seconds < 0 ? '未知' : duration(seconds)),
    '启动于 ' + (epoch ? dayTime(epoch) : '未知'),
    '',
    '本模块重载 ' + (Number(state.reloadCount) || 0) + ' 次',
    '最近重载 ' + (state.lastReload ? dayTime(state.lastReload) : '无记录'),
    '',
    'Surge ' + version + (build ? ' (' + build + ')' : ''),
    '',
    '上次刷新 ' + dayTime(now) + ' · 每 ' + updateSeconds + ' 秒自动更新'
  ];
  if (reloadNote) lines.push(reloadNote);
  return lines.join('\n');
}

function getMetrics() {
  // /v1/metrics is plain text; $httpAPI only guarantees JSON responses.
  // With a user-provided local key, use $httpClient directly for reliability.
  if (apiKey && !/\{\{\{|\}\}\}/.test(apiKey)) {
    return new Promise(resolve => {
      try {
        $httpClient.get({
          url: 'http://127.0.0.1:' + port + '/v1/metrics',
          headers: { 'X-Key': apiKey, 'Accept': 'text/plain' },
          timeout: 5,
          'auto-redirect': false
        }, (error, response, data) => {
          if (error || !response || Number(response.status) !== 200) return resolve({});
          resolve(parseMetrics(data));
        });
      } catch (_) { resolve({}); }
    });
  }
  return api('GET', '/v1/metrics').then(value => parseMetrics(value));
}

function parseMetrics(data) {
  if (data && typeof data === 'object') {
    if (typeof data.content === 'string') data = data.content;
    else if (typeof data.body === 'string') data = data.body;
    else if (typeof data.data === 'string') data = data.data;
    else return {};
  }
  if (typeof data !== 'string') return {};
  const out = {};
  for (const line of data.split(/\r?\n/)) {
    const m = /^(surge_(?:memory_bytes|uptime_seconds|active_requests|dns_cache_entries))\s+([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)(?:\s|$)/.exec(line.trim());
    if (m) out[m[1]] = Number(m[2]);
  }
  return out;
}

function metricNumber(obj, key) {
  const n = obj && obj[key];
  return typeof n === 'number' && Number.isFinite(n) && n >= 0 ? n : null;
}

function api(method, path) {
  return new Promise(resolve => {
    let settled = false;
    const finish = value => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutId);
      resolve(value);
    };
    const timeoutId = setTimeout(() => finish({ error: '本机 API 超时' }), 2500);
    try { $httpAPI(method, path, null, result => finish(result)); }
    catch (e) { finish({ error: safeError(e) }); }
  });
}

function isApiError(result) {
  return result === undefined || result === null ||
    (typeof result === 'object' && (result.error || result.success === false));
}

function loadState() {
  try {
    const value = $persistentStore.read(STORAGE_KEY);
    const parsed = JSON.parse(value || '{}');
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed;
  } catch (_) {}
  return {};
}
function saveState(state) {
  try { $persistentStore.write(JSON.stringify(state), STORAGE_KEY); }
  catch (e) { console.log('[Surge Monitor Pro] storage error: ' + safeError(e)); }
}
function validPort(p) { return /^\d{1,5}$/.test(String(p || '')) && +p > 0 && +p <= 65535; }
function parseArguments(s) {
  const out = {};
  for (const part of s.split('&')) {
    const i = part.indexOf('=');
    if (i < 0) continue;
    const key = part.slice(0, i);
    try { out[key] = decodeURIComponent(part.slice(i + 1)); }
    catch (_) { out[key] = part.slice(i + 1); }
  }
  return out;
}
function duration(n) {
  let sec = Math.max(0, Math.floor(n));
  const d = Math.floor(sec / 86400); sec %= 86400;
  const h = Math.floor(sec / 3600); sec %= 3600;
  const m = Math.floor(sec / 60); sec %= 60;
  return (d ? d + ' 天 ' : '') + (h || d ? h + ' 时 ' : '') + m + ' 分 ' + sec + ' 秒';
}
function dayTime(t) {
  const d = new Date(t);
  return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}
function timeOf(t) { const d = new Date(t); return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds()); }
function pad(n) { return String(n).padStart(2, '0'); }
function fmtMiB(n) { return typeof n === 'number' && Number.isFinite(n) ? n.toFixed(1) + ' MiB' : '—'; }
function fmtDelta(n) { return (n >= 0 ? '+' : '-') + Math.abs(n).toFixed(1) + ' MiB'; }
function chart(history) {
  const values = history.map(x => x.v).filter(x => Number.isFinite(x));
  if (!values.length) return '暂无';
  const min = Math.min(...values), max = Math.max(...values);
  return values.map(v => '▁▂▃▄▅▆▇█'[max === min ? 3 : Math.min(7, Math.floor((v - min) / (max - min) * 7))]).join('');
}
function safeError(err) { return String(err && err.message ? err.message : err).slice(0, 160); }
