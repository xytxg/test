/*
 * Surge Monitor Pro 3.5.0
 * Scheduled memory history, cached panels and on-demand metrics.
 * The storage key and schema remain compatible with previous 3.x releases.
 */
'use strict';

const VERSION = '3.5.0';
const STORE_KEY = 'xy_surge_monitor_pro_v3';
const MAX_SAMPLES = 240;
const MiB = 1048576;
const MINUTE = 60000;
const MAX_SAMPLE_GAP = 12 * MINUTE;
const STALE_AGE = 18 * MINUTE;
const STARTED_AT = Date.now();
const args = parseArgs(typeof $argument === 'string' ? $argument : '');
const MODE = args.mode || 'panel';
const VIEW = args.view === 'detail' ? 'detail' : args.view === 'glance' ? 'glance' : 'compact';
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
    content: '状态暂不可用，请查看脚本日志',
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
    lastSuccess: 0, lastAttempt: 0, lastError: '', failures: 0,
    outageSince: 0, lastRecovered: 0, recoveryCount: 0
  };
}
function readState(now = Date.now()) {
  let data;
  try { data = JSON.parse($persistentStore.read(STORE_KEY) || '{}'); }
  catch (_) { return blankState(); }
  if (!data || data.schema !== 3 || !Array.isArray(data.samples)) return blankState();
  data.samples = data.samples.filter(x => x && finite(x.t) && finite(x.v) && x.t <= now)
    .sort((a, b) => a.t - b.t).slice(-MAX_SAMPLES);
  for (const key of ['reloadCount', 'failures', 'recoveryCount']) {
    if (!finite(data[key])) data[key] = 0;
  }
  for (const key of ['lastAttempt', 'lastReload', 'outageSince', 'lastRecovered']) {
    if (!finite(data[key]) || data[key] > now) data[key] = 0;
  }
  return data;
}
function saveState(state) {
  try {
    if (!$persistentStore.write(JSON.stringify(state), STORE_KEY)) {
      console.log('[Surge Monitor Pro] 无法保存采样状态');
    }
  }
  catch (error) { console.log('[Surge Monitor Pro] Storage: ' + message(error)); }
}
function epochChanged(state, epoch) {
  return finite(epoch) && finite(state.epoch) && Math.abs(epoch - state.epoch) > 30000;
}

function epochFromMetrics(metrics, observedAt) {
  const uptime = value(metrics, 'surge_uptime_seconds');
  return uptime !== null && uptime * 1000 <= observedAt ? observedAt - uptime * 1000 : null;
}

async function trafficEpoch() {
  const traffic = await httpAPI('GET', '/v1/traffic', 2500);
  const time = Number(traffic && traffic.startTime);
  if (!finite(time) || time === 0) return null;
  const epoch = time > 1e12 ? time : time * 1000;
  return epoch <= Date.now() ? epoch : null;
}

function observationAt(metrics, time) {
  return {
    t: time, v: value(metrics, 'surge_memory_bytes') / MiB,
    active: value(metrics, 'surge_active_requests'),
    dns: value(metrics, 'surge_dns_cache_entries')
  };
}

async function collect() {
  let metrics = await getMetrics();
  if (MODE === 'start' && metrics.fault && metrics.retryable) {
    await new Promise(resolve => setTimeout(resolve, 650));
    metrics = await getMetrics();
  }
  const observedAt = Date.now();
  let epoch = epochFromMetrics(metrics, observedAt);
  if (epoch === null && (!metrics.fault || MODE === 'start')) epoch = await trafficEpoch();
  let state = readState();
  // A delayed startup retry must not overwrite a newer cron attempt.
  if (state.lastAttempt > STARTED_AT) return;
  if (epochChanged(state, epoch)) state = blankState();
  if (epoch !== null) state.epoch = epoch;
  state.lastAttempt = STARTED_AT;
  if (metrics.fault) {
    state.failures = Math.min(9999, state.failures + 1);
    if (!state.outageSince) state.outageSince = observedAt;
    state.lastError = metrics.fault;
    saveState(state);
    return;
  }
  const observation = observationAt(metrics, observedAt);
  const samples = state.samples, last = samples[samples.length - 1];
  if (last && last.t > observedAt) return;
  // Avoid duplicate startup/cron observations that happen within 30 seconds.
  if (last && observedAt - last.t < 30000) samples[samples.length - 1] = observation;
  else samples.push(observation);
  state.samples = samples.slice(-MAX_SAMPLES);
  state.high = finite(state.high) ? Math.max(state.high, observation.v) : observation.v;
  state.low = finite(state.low) ? Math.min(state.low, observation.v) : observation.v;
  attachReloadSample(state.reloadProbe, observation);
  if (state.failures > 0) {
    state.lastRecovered = observedAt;
    state.recoveryCount += 1;
  }
  state.outageSince = 0;
  state.lastSuccess = observedAt;
  state.lastError = '';
  state.failures = 0;
  state.metricsCache = {__version: metrics.__version, __build: metrics.__build};
  saveState(state);
}

async function recordReload() {
  if (typeof $event === 'object' && $event && $event.name !== 'profile-reloaded') return;
  const epoch = await trafficEpoch();
  let state = readState();
  if (epochChanged(state, epoch)) state = blankState();
  if (epoch !== null) state.epoch = epoch;
  state.reloadCount += 1;
  if (STARTED_AT >= state.lastReload) {
    const index = state.samples.findIndex(sample => sample.t >= STARTED_AT);
    const before = state.samples[index < 0 ? state.samples.length - 1 : index - 1];
    state.lastReload = STARTED_AT;
    state.reloadProbe = {
      at: STARTED_AT, before: before && STARTED_AT - before.t <= MAX_SAMPLE_GAP ? before.v : null,
      after: null, delta: null
    };
    if (index >= 0) attachReloadSample(state.reloadProbe, state.samples[index]);
  }
  saveState(state);
}

function attachReloadSample(probe, observation) {
  if (!probe || probe.after != null || observation.t < probe.at) return;
  probe.after = observation.v;
  probe.delta = finite(probe.before) && observation.t - probe.at <= MAX_SAMPLE_GAP
    ? observation.v - probe.before : null;
}

async function display() {
  let metrics = null;
  let live = null;
  let epoch = null;
  let note = '';
  let actionFailed = false;
  if (tapped) {
    if (tapAction === 'reload') {
      const result = await httpAPI('POST', '/v1/profiles/reload');
      actionFailed = hasError(result);
      note = actionFailed ? '重载请求失败，请查看 Surge 日志' : '已请求重载配置';
    } else {
      metrics = await getMetrics();
      const time = Date.now();
      actionFailed = !!metrics.fault;
      if (actionFailed) note = '实时读取失败 · ' + metrics.fault;
      else {
        live = observationAt(metrics, time);
        epoch = epochFromMetrics(metrics, time);
      }
    }
  }
  const now = Date.now();
  let state = readState(now);
  const changed = epochChanged(state, epoch);
  if (changed) state = blankState();
  return renderPanel(state, {now, epoch: epoch === null ? state.epoch : epoch, live, metrics, changed, note, actionFailed});
}

function renderPanel(state, {now, epoch, live, metrics, changed, note, actionFailed}) {
  const detail = VIEW === 'detail';
  const glance = VIEW === 'glance';
  const samples = state.samples;
  const recent = samples[samples.length - 1];
  const previous = samples[samples.length - 2];
  const latest = live || recent;
  const stale = !!latest && now - latest.t > STALE_AGE;
  const failed = state.failures > 0;
  const overLimit = latest && !stale && (!failed || live) && latest.v >= warnMiB;
  const growth = recent && !failed && now - recent.t <= STALE_AGE
    ? continuousGrowth(samples, growthMiB) : null;
  const lines = [];
  const title = latest
    ? (live ? '实时内存 ' : stale || failed ? '历史内存 ' : '内存 ') + fixed(latest.v) + ' MiB'
    : 'Surge 内存';

  if (latest) {
    if (recent && now - recent.t <= STALE_AGE) {
      const thirty = aroundDelta(samples, 'v', 30 * MINUTE);
      const lastDelta = previous && recent.t - previous.t <= MAX_SAMPLE_GAP
        ? recent.v - previous.v : null;
      if (thirty !== null) lines.push('近30分钟  ' + motion(thirty));
      else if (lastDelta !== null) lines.push('较上次  ' + motion(lastDelta));
      else lines.push('趋势  积累样本中');
      const hour = period(samples, now, 60 * MINUTE);
      const day = period(samples, now, 1440 * MINUTE);
      if (hour.length >= 2) {
        lines.push('1h均 ' + fixed(average(hour)) + ' · 24h峰 ' + fixed(maxValue(day)) + ' MiB');
      } else if (finite(state.high)) {
        lines.push('本次采样峰值 ' + fixed(state.high) + ' MiB');
      }
      if (detail) {
        const dnsDelta = aroundDelta(samples, 'dns', 30 * MINUTE);
        if (dnsDelta !== null) lines.push('DNS近30分钟 ' + signed(dnsDelta, 0) + ' 条');
      }
    }
    lines.push('请求 ' + count(latest.active) + ' · DNS ' + count(latest.dns));
  } else if (!failed) {
    lines.push('等待首次自动采样');
  }
  if (changed) lines.push('检测到引擎重启，等待新一轮自动采样');
  const uptime = finite(epoch) ? Math.max(0, (now - epoch) / 1000) : null;
  lines.push('运行 ' + (uptime === null ? '暂无数据' : briefDuration(uptime)) +
    (glance ? (latest ? ' · ' + sampleAge(latest, now, live, stale) : '') : ' · 重载' + state.reloadCount + '次'));

  if (overLimit) lines.push('内存达到预警线 ' + warnMiB + ' MiB');
  if (growth !== null) lines.push('内存持续上涨 ' + signed(growth) + ' MiB');
  if (failed) lines.push('后台采样失败 ' + state.failures + ' 次 · ' + state.lastError);
  else if (recentlyRecovered(state, now, (detail ? 60 : 15) * MINUTE)) {
    lines.push('采样已恢复 · ' + timeHM(state.lastRecovered) +
      (detail ? ' · 累计' + state.recoveryCount + '次' : ''));
  }
  if (!glance) {
    if (latest) lines.push(sampleAge(latest, now, live, stale) + ' · ' + timeHM(latest.t));
    lines.push('Surge ' + versionText(live ? metrics : state.metricsCache || {}) +
      (detail ? ' · 监控 ' + VERSION : ''));
  }
  if (detail) {
    if (finite(epoch)) lines.push('启动 ' + dateTime(epoch));
    if (finite(state.low)) lines.push('本次采样最低 ' + fixed(state.low) + ' MiB');
    if (state.lastReload > 0) lines.push('最近重载 ' + dateTime(state.lastReload));
    const probe = state.reloadProbe;
    if (probe && Number.isFinite(probe.delta) && now - probe.at <= 60 * MINUTE) {
      lines.push('重载前后 ' + signed(probe.delta) + ' MiB');
    }
    lines.push('有效样本 ' + samples.length + '/' + MAX_SAMPLES);
  }
  if (note) lines.push(note);
  const alert = failed || stale || growth !== null || overLimit || actionFailed;
  return {
    title, content: lines.join('\n'),
    icon: alert ? 'exclamationmark.circle.fill' : 'gauge.medium',
    'icon-color': alert ? '#FF9500' : latest ? '#0A84FF' : '#8E8E93'
  };
}

function sampleAge(sample, now, live, stale) {
  if (live) return '刚刚读取';
  return stale ? '采样已过期' : '采样' + briefAge(now - sample.t);
}

function recentlyRecovered(state, now, maxAge) {
  return state.lastRecovered > 0 && now - state.lastRecovered < maxAge;
}
function motion(diff) {
  if (Math.abs(diff) < 0.05) return '→ 持平';
  return (diff > 0 ? '↑ ' : '↓ ') + Math.abs(diff).toFixed(1) + ' MiB';
}

// Statistics use observed samples only, without invented intermediate points.
function period(samples, now, duration) {
  return samples.filter(sample => sample.t >= now - duration);
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
  return best && diff <= 8 * MINUTE ? current[key] - best[key] : null;
}
function continuousGrowth(samples, threshold) {
  if (samples.length < 6) return null;
  const last = samples.slice(-6);
  const span = last[5].t - last[0].t;
  if (span < 1500000 || span > 2700000) return null;
  for (let i = 1; i < last.length; i++) {
    const gap = last[i].t - last[i-1].t;
    if (gap <= 0 || gap > MAX_SAMPLE_GAP || last[i].v < last[i-1].v - 0.15) return null;
  }
  const increase = last[5].v - last[0].v;
  return increase >= threshold ? increase : null;
}

// Surge's HTTP API is JSON except /v1/metrics (Prometheus plaintext).
function getMetrics() {
  const useKey = !!apiKey && !/^\{\{\{.*\}\}\}$/.test(apiKey);
  if (!useKey) {
    // Keep the legacy fallback for environments which return a wrapped text body.
    return httpAPI('GET', '/v1/metrics', 3500).then(data => {
      const metrics = parseMetrics(data);
      return metrics.fault ? {fault: '请在模块参数填写本机 HTTP API 密钥'} : metrics;
    });
  }
  const unavailable = {fault: '本机 HTTP API 无响应，请检查端口和 API 设置', retryable: true};
  return withDeadline(4500, unavailable, finish => {
    $httpClient.get({
      url: 'http://127.0.0.1:' + apiPort + '/v1/metrics',
      headers: {'X-Key': apiKey, 'Accept': 'text/plain'},
      policy: 'DIRECT',
      'auto-redirect': false,
      timeout: 4
    }, (error, response, body) => {
      const status = Number(response && (response.status || response.statusCode));
      if (status === 401 || status === 403) return finish({fault: 'HTTP API 密钥或权限异常'});
      if (status === 404) return finish({fault: '当前 Surge 版本未提供内存指标接口'});
      if (status >= 500) return finish({fault: 'HTTP API 服务暂不可用', retryable: true});
      if (error || !status) return finish(unavailable);
      if (status !== 200) return finish({fault: 'HTTP API 请求失败（' + status + '）'});
      finish(parseMetrics(body));
    });
  });
}
function parseMetrics(body) {
  if (body && typeof body === 'object') body = body.content || body.body || body.data || '';
  const result = {};
  if (typeof body === 'string') {
    // Match the fields we render without allocating a line array for per-policy counters.
    const rows = /^[\uFEFF \t]*surge_(?:(memory_bytes|uptime_seconds|active_requests|dns_cache_entries)[ \t]+([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)(?=\s|$)|build_info\{([^\r\n]*)\})/gm;
    let row;
    while ((row = rows.exec(body)) !== null) {
      if (row[1]) result['surge_' + row[1]] = Number(row[2]);
      else {
        const version = /(?:^|,)\s*version="([^"]*)"/.exec(row[3]);
        const build = /(?:^|,)\s*build="([^"]*)"/.exec(row[3]);
        if (version) result.__version = version[1];
        if (build) result.__build = build[1];
      }
    }
  }
  if (!(value(result, 'surge_memory_bytes') > 0)) {
    result.fault = '内存指标缺失或格式异常';
    result.retryable = true;
  }
  return result;
}
function withDeadline(ms, fallback, invoke) {
  return new Promise(resolve => {
    let completed = false;
    const finish = result => {
      if (completed) return;
      completed = true;
      clearTimeout(timer);
      resolve(result);
    };
    const timer = setTimeout(() => finish(fallback), ms);
    try { invoke(finish); }
    catch (_) { finish(fallback); }
  });
}
function httpAPI(method, path, timeout = 4500) {
  return withDeadline(timeout, {error: '本机 API 无响应'}, finish => {
    $httpAPI(method, path, null, finish);
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
