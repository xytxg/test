/* Run: node Surge/tests/surge-monitor-pro.test.cjs
 * No dependencies and no network access required.
 * The script is executed as Surge-like sandbox code in Node's VM.
 */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const filename = path.resolve(__dirname, "../scripts/surge-monitor-pro-v3.1.0.js");
const source = fs.readFileSync(filename, "utf8");
const entry = new vm.Script(source, { filename });
const CACHE_KEY = "xy_surge_monitor_pro_v3";
const memory = new Map();
let fakeClock = 1794710000000;
let engineStarted = 1794709000;
let valueMiB = 39.3;
let rejectMetrics = false;
let metricsRequests = 0;
let reloadCalls = 0;

class TestDate extends Date {
  constructor(...args) { super(...(args.length ? args : [fakeClock])); }
  static now() { return fakeClock; }
}

function execute(mode, { button = false, key = "", tap = "refresh" } = {}) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(mode + " did not call $done")), 1000);
    const finish = value => { clearTimeout(timer); resolve(value); };
    const ctx = {
      Date: TestDate, Promise, setTimeout, clearTimeout,
      console: { log() {} },
      $trigger: button ? "button" : "auto-interval",
      $argument: "mode=" + mode + "&tap=" + tap + "&api_port=6171&api_key=" + key,
      $environment: { "surge-version": "6.100.0", "surge-build": "4027" },
      $persistentStore: {
        read: k => memory.get(k) || null,
        write: (v, k) => { memory.set(k, v); return true; }
      },
      $httpAPI(method, url, body, cb) {
        if (url === "/v1/traffic") cb({ startTime: engineStarted });
        else if (url === "/v1/metrics") {
          metricsRequests++;
          cb(rejectMetrics ? { error: "unavailable" } : metricsText());
        } else if (url === "/v1/profiles/reload") {
          reloadCalls++;
          cb({ success: true });
        } else cb({ error: "unexpected HTTP API: " + url });
      },
      $httpClient: {
        get(options, cb) {
          assert.equal(options.url, "http://127.0.0.1:6171/v1/metrics");
          assert.equal(options.headers["X-Key"], key);
          cb(null, { status: 200 }, rejectMetrics ? "" : metricsText());
        }
      },
      $done: finish
    };
    try { entry.runInNewContext(ctx, { timeout: 1000 }); }
    catch (error) { clearTimeout(timer); reject(error); }
  });
}
function metricsText() {
  return [
    "surge_memory_bytes " + Math.round(valueMiB * 1048576),
    "surge_active_requests 21",
    "surge_dns_cache_entries 139",
    'surge_build_info{version="6.102.1",build="4041"} 1'
  ].join("\n");
}
function saved() { return JSON.parse(memory.get(CACHE_KEY) || "null"); }

(async () => {
  assert.doesNotMatch(source, /\btimeOf\s*\(/, "Undefined timeOf must not be called");
  assert.match(source, /function clock\(/, "Clock helper must exist");
  const initial = await execute("panel");
  assert.match(initial.content, /等待自动采样/);
  assert.equal(saved(), null, "Panel must not create monitoring data");

  await execute("start");
  assert.equal(saved().samples.length, 1);

  fakeClock += 1000;
  valueMiB = 39.0;
  const button = await execute("panel", { button: true });
  assert.equal(saved().samples.length, 1, "Panel button must not collect");

  fakeClock += 360000;
  await execute("sample");
  assert.equal(saved().samples.length, 2);
  assert.equal(metricsRequests, 2, "Only startup and cron can fetch metrics");
  const panel = await execute("panel");
  assert.match(panel.content, /↓0\.3 MiB/);
  assert.match(panel.content, /Surge 6\.102\.1 \(4041\)/);

  await execute("reloaded");
  assert.equal(saved().reloadCount, 1);
  await execute("panel", { button: true, tap: "reload" });
  assert.equal(saved().reloadCount, 1, "Manual button must not double count events");
  assert.equal(reloadCalls, 1);

  rejectMetrics = true;
  fakeClock += 360000;
  await execute("sample");
  assert.equal(saved().samples.length, 2, "Failed response must not create sample");
  assert.equal(saved().failures, 1, "Failed metric requests must be counted");
  assert.match((await execute("panel")).content, /采样失败 1 次/);

  rejectMetrics = false;
  valueMiB = 42;
  fakeClock += 360000;
  await execute("sample", { key: "test-local-key" });
  assert.equal(saved().samples.length, 3, "Authenticated local metrics must work");
  assert.equal(saved().failures, 0, "A successful sample resets the failure streak");
  assert.match((await execute("panel")).content, /最近重载前后/);
  // Six successive real observations span roughly 30 minutes and exceed 10 MiB.
  for (let i = 0; i < 6; i++) {
    fakeClock += 360000;
    valueMiB += 3;
    await execute("sample", { key: "test-local-key" });
  }
  const growing = await execute("panel");
  assert.match(growing.content, /持续上涨预警/);
  assert.match(growing.content, /1小时均值/);
  assert.match(growing.content, /DNS较30分钟前/);
  assert.equal(saved().samples.length, 9);

  fakeClock += 1000;
  engineStarted += 1200;
  const restarted = await execute("panel");
  assert.match(restarted.content, /旧采样已隔离/);
  await execute("start");
  assert.equal(saved().samples.length, 1);
  assert.equal(saved().reloadCount, 0);
  assert.doesNotMatch(button.content, /Can't find variable:/);

  console.log("Surge Monitor Pro v3.1.0: regression checks passed");
})().catch(e => { console.error(e); process.exitCode = 1; });
