/*
 * Surge Monitor Pro 4.0.0
 * Scheduled memory history, cached panels and on-demand metrics.
 * The storage key and schema remain compatible with previous 3.x releases.
 */
'use strict';

const VERSION = '4.0.0';
const STORE_KEY = 'xy_surge_monitor_pro_v3';
const MAX_SAMPLES = 240;
const MiB = 1048576;
const MINUTE = 60000;
const HISTORY_AGE = 1440 * MINUTE;
const MAX_SAMPLE_GAP = 12 * MINUTE;
const STALE_AGE = 18 * MINUTE;
const STARTED_AT = Date.now();
const args = parseArgs(typeof $argument === 'string' ? $argument : '');
const MODE = args.mode || 'panel';
const VIEW = args.view === 'detail' ? 'detail' : args.view === 'compact' ? 'compact' : 'glance';
const EN = args.lang === 'en';
function L(zh, en) { return EN ? en : zh; }
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
    title: L('Surge 状态监控', 'Surge Monitor'),
    content: L('状态暂不可用，请查看脚本日志', 'Unavailable · see script logs'),
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
    schema: 3, epoch: null, samples: [], runs: [], high: null, low: null, lastRestart: 0,
    reloadCount: 0, lastReload: 0, reloadProbe: null,
    lastSuccess: 0, lastAttempt: 0, lastError: '', failures: 0,
    outageSince: 0, lastRecovered: 0, recoveryCount: 0,
    lastOutageSpan: null, lastTransition: ''
  };
}
function readState(now = Date.now()) {
  let data;
  try { data = JSON.parse($persistentStore.read(STORE_KEY) || '{}'); }
  catch (_) { return blankState(); }
  if (!data || data.schema !== 3 || !Array.isArray(data.samples)) return blankState();
  // Keep normal read work bounded, and tolerate legacy/out-of-order records.
  const cutoff = now - HISTORY_AGE;
  // JSON.parse already created a private array. Compact it in place.
  // Ordered history is the usual path: no extra slice/filter/sort allocation.
  const ordered = data.samples;
  let length = 0, needsSort = false;
  for (let i = Math.max(0, ordered.length - MAX_SAMPLES * 4); i < ordered.length; i++) {
    const item = ordered[i];
    if (!item || !finite(item.t) || !finite(item.v) || item.v >= 100000 ||
        item.t < cutoff || item.t > now) continue;
    if (length && item.t < ordered[length - 1].t) needsSort = true;
    if (length && item.t === ordered[length - 1].t) continue;
    ordered[length++] = item;
  }
  ordered.length = length;
  if (needsSort) {
    ordered.sort((a,b) => a.t - b.t);
    let unique = 0;
    for (let i = 0; i < ordered.length; i++) {
      const item = ordered[i];
      if (unique && item.t === ordered[unique - 1].t) continue;
      ordered[unique++] = item;
    }
    ordered.length = unique;
  }
  if (!Array.isArray(data.runs)) {
    const prev = data.metricsCache && typeof data.metricsCache === 'object'
      ? data.metricsCache : {};
    const from = (ordered[0] && ordered[0].t) || data.lastSuccess || data.epoch;
    data.runs = finite(from) && from <= now ? [{
      from, __version:clean(prev.__version), __build:clean(prev.__build),
      __system:clean(prev.__system)
    }] : [];
  }
  delete data.metricsCache;
  const runs = data.runs;
  let runCount = 0, sortRuns = false;
  for (let i = Math.max(0, runs.length - 256); i < runs.length; i++) {
    const item = runs[i];
    if (!item || typeof item !== 'object' || !finite(item.from) || item.from > now) continue;
    if (runCount && item.from < runs[runCount - 1].from) sortRuns = true;
    runs[runCount++] = item;
  }
  runs.length = runCount;
  if (sortRuns) runs.sort((a,b) => a.from - b.from);
  if (runs.length > 64) runs.splice(0, runs.length - 64);
  for(const name of ['reloadCount','failures','recoveryCount'])
    if(!finite(data[name]))data[name]=0;
  for(const name of ['lastAttempt','lastReload','outageSince','lastRecovered',
                     'lastRestart','lastSuccess'])
    if(!finite(data[name])||data[name]>now)data[name]=0;
  if(!finite(data.epoch)||data.epoch>now)data.epoch=null;
  if(!data.reloadProbe||typeof data.reloadProbe!=='object'||
     !finite(data.reloadProbe.at)||data.reloadProbe.at>now)data.reloadProbe=null;
  if(!finite(data.high))data.high=null;
  if(!finite(data.low))data.low=null;
  if(typeof data.lastError!=='string')data.lastError='';
  if(!finite(data.lastOutageSpan))data.lastOutageSpan=null;
  if(!['epoch','build','version'].includes(data.lastTransition))data.lastTransition='';
  pruneHistory(data,now);
  return data;
}

function pruneHistory(state, now) {
  const samples = state.samples;
  const cutoff = now - HISTORY_AGE;
  let remove = Math.max(0, samples.length - MAX_SAMPLES);
  while (remove < samples.length && samples[remove].t < cutoff) remove++;
  if (remove) samples.splice(0, remove);
  const oldest = samples.length ? samples[0].t : now;
  const runs = state.runs;
  let first = 0;
  while (first + 1 < runs.length && runs[first + 1].from <= oldest) first++;
  if (first) runs.splice(0, first);
  if (!samples.length && runs.length > 1) runs.splice(0, runs.length - 1);
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
function currentRun(state) {
  return state.runs[state.runs.length - 1];
}
function updateRun(state, epoch, info, observedAt) {
  const current = currentRun(state);
  const bootChanged = epochChanged(state, epoch);
  const buildChanged = !!(current && current.__build && info.__build && current.__build !== info.__build);
  const versionChanged = !!(current && current.__version && info.__version && current.__version !== info.__version);
  const changed = bootChanged || buildChanged || versionChanged;
  if (changed) {
    // Build/version changes are a new statistics baseline, not proof of a VPN stop.
    state.lastTransition = bootChanged ? 'epoch' : buildChanged ? 'build' : 'version';
    if (bootChanged) state.lastRestart = epoch;
    state.lastOutageSpan = null;
    state.epoch = null;
    state.high = state.low = state.reloadProbe = null;
    state.lastReload = state.reloadCount = state.lastSuccess = 0;
    state.lastError = '';
    state.failures = state.outageSince = state.lastRecovered = state.recoveryCount = 0;
  }
  if (!current || changed) state.runs.push({from: observedAt, ...info});
  else {
    if (info.__version) current.__version = info.__version;
    if (info.__build) current.__build = info.__build;
    if (info.__system) current.__system = info.__system;
  }
  if (epoch !== null) state.epoch = epoch;
  return changed;
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
    dns: value(metrics, 'surge_dns_cache_entries'),
    bans: value(metrics, 'surge_active_bans')
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
  const state = readState();
  // A delayed startup retry must not overwrite a newer cron attempt.
  if (state.lastAttempt > STARTED_AT) return;
  const changed = updateRun(state, epoch, buildInfo(metrics), observedAt);
  if(changed)console.log('[Surge Monitor Pro] [engine] 已切换统计基线 · '+(state.lastTransition==='epoch'?'启动时间变化':'版本变化')+'；停止原因请查看 Surge Logbook');
  state.lastAttempt = STARTED_AT;
  if (metrics.fault) {
    if(state.failures===0 || state.lastError!==metrics.fault)
      console.log('[Surge Monitor Pro] [sample] '+faultText(metrics.fault));
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
  if (last && !changed && last.t >= currentRun(state).from && observedAt - last.t < 30000) {
    samples[samples.length - 1] = observation;
  } else samples.push(observation);
  pruneHistory(state, observedAt);
  state.high = finite(state.high) ? Math.max(state.high, observation.v) : observation.v;
  state.low = finite(state.low) ? Math.min(state.low, observation.v) : observation.v;
  attachReloadSample(state.reloadProbe, observation);
  if (state.failures > 0) {
    console.log('[Surge Monitor Pro] [sample] 采样恢复，之前连续失败'+state.failures+L('次', ''));
    state.lastOutageSpan = state.outageSince > 0 && observedAt >= state.outageSince ? observedAt - state.outageSince : null;
    state.lastRecovered = observedAt;
    state.recoveryCount += 1;
  }
  state.outageSince = 0;
  state.lastSuccess = observedAt;
  state.lastError = '';
  state.failures = 0;
  saveState(state);
}

async function recordReload() {
  if (typeof $event === 'object' && $event && $event.name !== 'profile-reloaded') return;
  const epoch = await trafficEpoch();
  const state = readState();
  updateRun(state, epoch, buildInfo({}), STARTED_AT);
  state.reloadCount += 1;
  if (STARTED_AT >= state.lastReload) {
    const index = state.samples.findIndex(sample => sample.t >= STARTED_AT);
    const before = state.samples[index < 0 ? state.samples.length - 1 : index - 1];
    state.lastReload = STARTED_AT;
    state.reloadProbe = {
      at: STARTED_AT,
      before: before && before.t >= currentRun(state).from && STARTED_AT - before.t <= MAX_SAMPLE_GAP
        ? before.v : null,
      after: null, delta: null
    };
    if (index >= 0) attachReloadSample(state.reloadProbe, state.samples[index]);
  }
  saveState(state);
}

function attachReloadSample(probe, observation) {
  if (!probe || probe.after != null || observation.t < probe.at) return;
  probe.after = observation.v;
  probe.afterAt = observation.t;
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
      note = actionFailed ? L('重载请求失败，请查看 Surge 日志', 'Reload failed · see Surge logs') : L('已请求重载配置', 'Profile reload requested');
    } else {
      metrics = await getMetrics();
      const time = Date.now();
      actionFailed = !!metrics.fault;
      if (actionFailed) note = L('实时读取失败 · ', 'Live read failed · ') + faultText(metrics.fault);
      else {
        live = observationAt(metrics, time);
        epoch = epochFromMetrics(metrics, time);
      }
    }
  }
  const now = Date.now();
  const state = readState(now);
  const changed = live ? updateRun(state, epoch, buildInfo(metrics), live.t) : false;
  return renderPanel(state, {now, live, changed, note, actionFailed});
}

function renderPanel(state, {now, live, changed, note, actionFailed}) {
  const detail = VIEW === 'detail';
  const glance = VIEW === 'glance';
  const samples = state.samples;
  const run = currentRun(state);
  const runStart = run ? run.from : 0;
  const last = samples[samples.length - 1];
  const previous = samples[samples.length - 2];
  const recent = last && !changed && last.t >= runStart ? last : null;
  const latest = live || recent;
  const stale = !!latest && now - latest.t > STALE_AGE;
  const expiredHistory = !latest && state.lastSuccess > 0 && now - state.lastSuccess > STALE_AGE;
  const failed = state.failures > 0;
  const overLimit = latest && !stale && (!failed || live) && latest.v >= warnMiB;
  const growth = recent && !failed && now - recent.t <= STALE_AGE
    ? continuousGrowth(samples, runStart, growthMiB, live) : null;
  const lines = [];
  const title = latest
    ? (live ? L('实时内存 ', 'Live memory ') : stale || failed ? L('历史内存 ', 'Last memory ') : L('内存 ', 'Memory ')) + fixed(latest.v) + ' MiB'
    : L('Surge 内存', 'Surge Memory');

  if (latest) {
    if (recent && now - recent.t <= STALE_AGE && (!failed || live)) {
      // The live observation is the trend endpoint, not a new history point.
      const endpoint = live || recent;
      const base = live ? recent : previous;
      const thirty = aroundDelta(samples, 'v', runStart, 30 * MINUTE, endpoint);
      const lastDelta = base && base.t >= runStart && endpoint.t >= base.t &&
        endpoint.t - base.t <= MAX_SAMPLE_GAP ? endpoint.v - base.v : null;
      if (thirty !== null) lines.push(L('近30分钟  ', 'Last 30m  ') + motion(thirty));
      else if (lastDelta !== null) lines.push(L('较上次  ', 'Since last  ') + motion(lastDelta));
      else lines.push(L('趋势  积累样本中', 'Trend · collecting samples'));
      const {hourMean, dayPeak} = summarize(samples, now, runStart);
      if (hourMean !== null && dayPeak !== null) {
        lines.push(L('1h均 ', '1h avg ') + fixed(hourMean) + L(' · 24h峰 ', ' · 24h max ') + fixed(dayPeak) + ' MiB');
      } else if (finite(state.high)) {
        lines.push(L('本次采样峰值 ', 'Session peak ') + fixed(state.high) + ' MiB');
      }
      if (detail) {
        const dnsDelta = aroundDelta(samples, 'dns', runStart, 30 * MINUTE, endpoint);
        if (dnsDelta !== null) lines.push(L('DNS近30分钟 ', 'DNS 30m ') + signed(dnsDelta, 0) + L(' 条', ' entries'));
      }
    }
    lines.push(L('请求 ', 'Requests ') + count(latest.active) + ' · DNS ' + count(latest.dns));
    if (detail && finite(latest.bans))
      lines.push(L('未授权访问封禁 ', 'Active access bans ') + count(latest.bans) + L(' 个', '') + (stale || (failed && !live) ? L('（历史）', ' (old)') : ''));
    else if (!stale && (!failed || live) && finite(latest.bans) && latest.bans > 0)
      lines.push(L('未授权访问封禁 ', 'Active access bans ') + count(latest.bans) + L(' 个', ''));
  } else if (!failed) {
    lines.push(expiredHistory ? L('采样已过期 · 等待新采样', 'Samples expired · awaiting data') : (state.lastTransition || state.lastRestart > 0) ? L('等待本次运行首次采样', 'Awaiting session sample') : L('等待首次自动采样', 'Awaiting first sample'));
  }
  if (changed) lines.push(state.lastTransition === 'epoch' ? L('启动时间变化 · 等待新一轮采样', 'Boot time changed · awaiting sample') : L('版本变化 · 等待新一轮采样', 'Version changed · awaiting sample'));
  const epoch = state.epoch;
  const uptime = finite(epoch) ? Math.max(0, (now - epoch) / 1000) : null;
  lines.push(L('运行 ', 'Up ') + (uptime === null ? L('暂无数据', 'unknown') : briefDuration(uptime)) +
    (glance ? (latest ? ' · ' + sampleAge(latest, now, live, stale) : '') : L(' · 重载', ' · reloads ') + state.reloadCount + L('次', '')));

  if (overLimit) lines.push(L('内存达到预警线 ', 'Memory threshold ') + warnMiB + ' MiB');
  if (growth !== null) lines.push(L('内存持续上涨 ', 'Sustained rise ') + signed(growth) + ' MiB');
  if (failed) lines.push((live ? L('实时已读 · 后台连续失败 ', 'Live OK · background failures ') : L('后台采样失败 ', 'Background failures ')) + state.failures + L(' 次 · ', ' · ') + faultText(state.lastError));
  else if (recentlyRecovered(state, now, (detail ? 60 : 15) * MINUTE)) {
    lines.push(L('采样已恢复 · ', 'Sampling recovered · ') + timeHM(state.lastRecovered) +
      (detail ? L(' · 累计', ' · total ') + state.recoveryCount + L('次', '') : ''));
  }
  if (!glance) {
    if (latest) lines.push(sampleAge(latest, now, live, stale) + ' · ' + timeHM(latest.t));
    lines.push('Surge ' + versionText(run || buildInfo({})) +
      (detail ? L(' · 监控 ', ' · monitor ') + VERSION : ''));
  }
  if (detail) {
    if (finite(epoch)) lines.push(L('启动 ', 'Started ') + dateTime(epoch));
    if (state.lastRestart > 0) lines.push(L('检测到启动时间变化 ', 'Boot change ') + dateTime(state.lastRestart));
    if (state.lastTransition) lines.push(L('停止原因以 Surge Logbook 为准', 'See Surge Logbook for stop reason'));
    if (finite(state.lastOutageSpan) && state.lastRecovered > 0)
      lines.push(L('上次采样故障观测跨度 ', 'Last observed outage span ') + briefDuration(state.lastOutageSpan / 1000));
    if (last && previous && last.t - previous.t > MAX_SAMPLE_GAP) {
      lines.push(L('最近两次采样间隔 ', 'Last sampling gap ') + briefDuration((last.t - previous.t) / 1000));
    }
    const earlier = previousBuildSample(samples, state.runs);
    if (earlier) {
      lines.push(L('上个 Build ', 'Previous build ') + earlier.build + ' · ' + fixed(earlier.sample.v) + ' MiB');
      if(macNetworkBufferNotice(run))lines.push(L('Mac 15+ 新网络栈：进程内存口径可能变化', 'macOS 15+: memory accounting may differ'));
    }
    if (finite(state.low)) lines.push(L('本次采样最低 ', 'Session min ') + fixed(state.low) + ' MiB');
    if (state.lastReload > 0) lines.push(L('最近重载 ', 'Last reload ') + dateTime(state.lastReload));
    const probe = state.reloadProbe;
    if (probe && Number.isFinite(probe.delta) && now - probe.at <= 60 * MINUTE) {
      lines.push(L('重载前后采样 ', 'Reload sample delta ') + signed(probe.delta) + ' MiB' +
        (probe.afterAt ? L(' · 重载后', ' · after ') + briefDuration((probe.afterAt - probe.at) / 1000) : ''));
    }
    lines.push(L('有效样本 ', 'Samples ') + samples.length + '/' + MAX_SAMPLES);
  }
  if (note) lines.push(note);
  const securityAlert = latest && !stale && (!failed || live) && finite(latest.bans) && latest.bans > 0;
  const alert = failed || stale || expiredHistory || growth !== null || overLimit || actionFailed || securityAlert;
  return {
    title, content: lines.join('\n'),
    icon: alert ? 'exclamationmark.circle.fill' : 'gauge.medium',
    'icon-color': alert ? '#FF9500' : latest ? '#0A84FF' : '#8E8E93'
  };
}

// Only translate messages generated by this module; never inspect native Surge log text.
function faultText(fault) {
  if (!EN) return fault;
  switch (fault) {
    case '内部指标接口暂不可用；请检查本机 API 设置': return 'Internal metrics API unavailable';
    case '内存指标不可读；可在模块参数填写本机 HTTP API 密钥': return 'Memory metric unavailable · check API key';
    case '本机 HTTP API 无响应，请检查端口和 API 设置': return 'Local API unavailable · check port/settings';
    case 'HTTP API 密钥或权限异常': return 'HTTP API key or permission error';
    case '当前 Surge 版本未提供内存指标接口': return 'Memory metrics endpoint unavailable';
    case 'HTTP API 服务暂不可用': return 'HTTP API service unavailable';
    case '指标响应处理异常': return 'Metric response processing error';
    case '内存指标缺失或格式异常': return 'Missing or invalid memory metric';
    default: {
      const status = /^HTTP API 请求失败（(\d+)）$/.exec(fault);
      return status ? 'HTTP API request failed (' + status[1] + ')' : 'Sampling error · see script logs';
    }
  }
}
function sampleAge(sample, now, live, stale) {
  if (live) return L('刚刚读取', 'Live now');
  return stale ? L('采样已过期', 'Sample expired') : L('采样', 'Sample ') + briefAge(now - sample.t);
}

function recentlyRecovered(state, now, maxAge) {
  return state.lastRecovered > 0 && now >= state.lastRecovered && now - state.lastRecovered < maxAge;
}
function motion(diff) {
  if (Math.abs(diff) < 0.05) return L('→ 持平', '→ steady');
  return (diff > 0 ? '↑ ' : '↓ ') + Math.abs(diff).toFixed(1) + ' MiB';
}

function summarize(samples, now, runStart) {
  const hourStart=Math.max(runStart,now-60*MINUTE);
  const dayStart=Math.max(runStart,now-HISTORY_AGE);
  let peak=null, sum=0, n=0;
  for(let i=samples.length-1;i>=0;i--){
    const row=samples[i];
    if(row.t<dayStart)break;
    peak=peak===null?row.v:Math.max(peak,row.v);
    if(row.t>=hourStart){sum+=row.v;n++;}
  }
  return {hourMean:n>=2?sum/n:null,dayPeak:peak};
}
function macNetworkBufferNotice(run){
  const ver=run&&run.__version;
  const match=typeof ver==='string' && /^(\d+)\.(\d+)/.exec(ver);
  const os=run&&run.__system;
  return !!(typeof os==='string' && /mac/i.test(os) && match &&
    (Number(match[1])>6 || (Number(match[1])===6&&Number(match[2])>=12)));
}
function previousBuildSample(samples, runs) {
  const current = runs[runs.length - 1];
  if (!current || !current.__build || runs.length < 2) return null;
  let index = runs.length - 1;
  for (let i = samples.length - 1; i >= 0 && index >= 0; i--) {
    const sample = samples[i];
    while (index >= 0 && sample.t < runs[index].from) index--;
    const build = index >= 0 && runs[index].__build;
    if (build && build !== current.__build) return {build, sample};
  }
  return null;
}
function aroundDelta(samples, key, runStart, duration, current = samples[samples.length - 1]) {
  if (!current || !finite(current[key])) return null;
  const target = current.t - duration;
  let best = null, diff = Infinity;
  const earliest = Math.max(runStart, target - 8 * MINUTE);
  for (let i = samples.length - 1; i >= 0; i--) {
    const item = samples[i];
    if (item.t < earliest) break;
    if (!finite(item[key]) || item.t >= current.t) continue;
    const distance = Math.abs(item.t - target);
    if (distance <= diff) { diff = distance; best = item; }
    else if (item.t < target) break;
  }
  return best && diff <= 8 * MINUTE ? current[key] - best[key] : null;
}
function continuousGrowth(samples, runStart, threshold, live = null) {
  const start = samples.length - 6;
  if (start < 0 || samples[start].t < runStart) return null;
  const last = samples[samples.length - 1];
  const span = last.t - samples[start].t;
  if (span < 1500000 || span > 2700000) return null;
  for (let i = start + 1; i < samples.length; i++) {
    const gap = samples[i].t - samples[i - 1].t;
    if (gap <= 0 || gap > MAX_SAMPLE_GAP || samples[i].v < samples[i - 1].v - 0.15) return null;
  }
  if (live && (live.t < last.t || live.t - last.t > MAX_SAMPLE_GAP || live.v < last.v - 0.15)) return null;
  const endpoint = live || last;
  if (endpoint.t - samples[start].t > 2700000) return null;
  const increase = endpoint.v - samples[start].v;
  return increase >= threshold ? increase : null;
}

// Surge's HTTP API is JSON except /v1/metrics (Prometheus plaintext).
function getMetrics() {
  const useKey = !!apiKey && !/^\{\{\{.*\}\}\}$/.test(apiKey);
  if (!useKey) {
    // Keep the legacy fallback for environments which return a wrapped text body.
    return httpAPI('GET', '/v1/metrics', 3500).then(data => {
      if (hasError(data)) return {fault: '内部指标接口暂不可用；请检查本机 API 设置', retryable: true};
      const metrics = parseMetrics(data);
      return metrics.fault ? {fault: '内存指标不可读；可在模块参数填写本机 HTTP API 密钥', retryable: true} : metrics;
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
      try {
      const status = Number(response && (response.status || response.statusCode));
      if (status === 401 || status === 403) return finish({fault: 'HTTP API 密钥或权限异常'});
      if (status === 404) return finish({fault: '当前 Surge 版本未提供内存指标接口'});
      if (status >= 500) return finish({fault: 'HTTP API 服务暂不可用', retryable: true});
      if (error || !status) return finish(unavailable);
      if (status !== 200) return finish({fault: 'HTTP API 请求失败（' + status + '）'});
      finish(parseMetrics(body));
      } catch (_) { finish({fault: '指标响应处理异常', retryable: true}); }
    });
  });
}
function parseMetrics(body) {
  if (body && typeof body === 'object') body = body.content || body.body || body.data || '';
  const result = {};
  if (typeof body === 'string') {
    // Stop at the last required series to avoid scanning per-policy counters.
    const rows = /^[\uFEFF \t]*surge_(?:(memory_bytes|uptime_seconds|active_requests|dns_cache_entries|active_bans)[ \t]+([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)(?=\s|$)|build_info\{([^\r\n]*)\})/gm;
    let row;
    while ((row = rows.exec(body)) !== null) {
      if (row[1]) result['surge_' + row[1]] = Number(row[2]);
      else {
        const version = /(?:^|,)\s*version="([^"]*)"/.exec(row[3]);
        const build = /(?:^|,)\s*build="([^"]*)"/.exec(row[3]);
        if (version) result.__version = version[1];
        if (build) result.__build = build[1];
        const system = /(?:^|,)\s*system="([^"]*)"/.exec(row[3]);
        if (system) result.__system = system[1];
      }
      if (result.__version && result.__build && result.surge_memory_bytes > 0 &&
          finite(result.surge_uptime_seconds) && finite(result.surge_active_requests) &&
          finite(result.surge_dns_cache_entries) && finite(result.surge_active_bans)) break;
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
function buildInfo(metrics) {
  const env = typeof $environment === 'object' && $environment ? $environment : {};
  return {
    __version: clean(metrics.__version) || clean(env['surge-version']),
    __build: clean(metrics.__build) || clean(env['surge-build']),
    __system: clean(metrics.__system) || clean(env.system)
  };
}
function versionText(info) {
  const version = info.__version, revision = info.__build;
  return version ? version + (revision && !version.includes(revision) ? ' (' + revision + ')' : '') : L('版本未知', 'version unknown');
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
  if (ms < 60000) return L('刚刚', 'just now');
  if (ms < 3600000) return Math.floor(ms / 60000) + L('分前', 'm ago');
  return Math.floor(ms / 3600000) + L('小时前', 'h ago');
}
function briefDuration(seconds) {
  let minutes = Math.floor(seconds / 60);
  const days = Math.floor(minutes / 1440); minutes %= 1440;
  const hours = Math.floor(minutes / 60); minutes %= 60;
  return (days ? days + L('天', 'd ') : '') + (hours ? hours + L('时', 'h ') : '') + minutes + L('分', 'm');
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
