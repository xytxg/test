import { GM_getValue, GM_setValue, hasStorage } from "../lib/userscript";
import { request } from "../lib/request";
import { normalizeSettings } from "./config";
import type { Context, Feature, Settings } from "./types";

export const SETTINGS_KEY = `nspp:settings:${location.hostname}`;
export function loadSettings(features: Feature[]): Settings {
  return normalizeSettings(features, GM_getValue(SETTINGS_KEY, {}));
}
export function saveSettings(features: Feature[], settings: Settings): void {
  if (!hasStorage()) throw new Error("油猴存储未就绪，请重新安装脚本后刷新");
  GM_setValue(SETTINGS_KEY, normalizeSettings(features, settings));
}

export function clearCaches(): void {
  if (!hasStorage()) throw new Error("油猴存储未就绪，请重新安装脚本后刷新");
  for (const [id, matches] of [
    ["user-level", (key: string) => key === "profiles"],
    ["notification-categories", (key: string) => key.startsWith("counts:")],
    ["footprints", (key: string) => key.startsWith("records:")],
  ] as const) {
    const key = `nspp:state:${location.hostname}:${id}`;
    const state = GM_getValue<Record<string, unknown>>(key, {});
    if (state && typeof state === "object" && !Array.isArray(state)) {
      GM_setValue(key, Object.fromEntries(Object.entries(state).filter(([name]) => !matches(name))));
    }
  }
}

export function startFeatures(features: Feature[], settings: Settings, notify: (text: string) => void): () => void {
  const callbacks = new Map<() => void, string | undefined>();
  const pending = new Set<() => void>();
  const cleanups: (() => void)[] = [];
  let timer: ReturnType<typeof setTimeout> | undefined;
  const run = (callback: () => void) => { try { callback(); } catch { notify("部分页面增强未能应用，可关闭对应模块后刷新重试"); } };
  const flush = () => {
    timer = undefined;
    if (document.hidden) return;
    const ready = [...pending];
    pending.clear();
    ready.forEach(callback => { if (callbacks.has(callback)) run(callback); });
  };
  const visibility = () => {
    document.documentElement.toggleAttribute('data-nspp-background', document.hidden);
    if (!document.hidden && pending.size && !timer) timer = setTimeout(flush, 100);
  };
  document.addEventListener('visibilitychange', visibility); visibility();
  // Avoid re-running every feature when our own dialogs, badges and toolbars change.
  // Keep native list changes observable, including mixed native/plugin batches.
  const ownedSelector = '#nspp-tools, #nspp-settings, .nspp-monitor, .nspp-user-hover, .nspp-user-badges, .nspp-message-editor, .nspp-compose, dialog.nspp-sheet, .nspp-post-preview, .nspp-image-viewer, .nspp-history, .nspp-hot-rankings, .nspp-quick-replies, .nspp-title-preview';
  const owned = (node: Node) => {
    const element = node instanceof Element ? node : node.parentElement;
    return !!element?.closest(ownedSelector);
  };
  const observer = new MutationObserver(records => {
    // Collect only native DOM changes. Plugin-generated buttons and dialogs must
    // never cause a feedback loop of full-document scans.
    const changes = records.flatMap(record => {
      if (owned(record.target)) return [];
      const nodes = [...record.addedNodes, ...record.removedNodes].filter(node => !owned(node));
      return nodes.length ? [{ target: record.target, nodes }] : [];
    });
    if (!changes.length) return;
    for (const [callback, selector] of callbacks) {
      if (!selector || changes.some(({ target, nodes }) => {
        // A hydrated child of an existing item may not itself match the selector.
        // Checking ancestors ensures these changes still re-run the watcher.
        const relevant = (node: Node) => {
          if (!(node instanceof Element)) return false;
          return node.matches(selector) || !!node.querySelector(selector) || !!node.closest(selector);
        };
        return relevant(target) || nodes.some(relevant);
      })) pending.add(callback);
    }
    if (pending.size && !timer && !document.hidden) timer = setTimeout(flush, 100);
  });
  observer.observe(document.body, { childList: true, subtree: true });
  for (const feature of features) {
    if (!settings[feature.id]?.enabled) continue;
    const controller = new AbortController();
    cleanups.push(() => controller.abort());
    const cacheKey = `nspp:state:${location.hostname}:${feature.id}`;
    const readState = () => {
      const cache = GM_getValue<Record<string, unknown>>(cacheKey, {});
      return cache && typeof cache === "object" && !Array.isArray(cache) ? cache : {};
    };
    const ctx: Context = {
      root: document,
      get: <T>(key: string) => (Object.hasOwn(settings[feature.id], key) ? settings[feature.id][key] : readState()[key]) as T,
      set: (key, value) => {
        if (["__proto__", "constructor", "prototype"].includes(key)) return;
        if (Object.hasOwn(feature.defaults, key)) {
          settings[feature.id][key] = value as never;
          saveSettings(features, settings);
        } else {
          const state = readState();
          state[key] = value;
          GM_setValue(cacheKey, state);
        }
      },
      watch: (callback, selector) => {
        callbacks.set(callback, selector);
        run(callback);
        const stop = () => { callbacks.delete(callback); pending.delete(callback); };
        cleanups.push(stop);
        return stop;
      },
      request: (url, options = {}) => request(url, { ...options, signal: options.signal ? AbortSignal.any([controller.signal, options.signal]) : controller.signal }),
      notify,
      signal: controller.signal,
    };
    try {
      const cleanup = feature.mount(ctx);
      if (cleanup) cleanups.push(cleanup);
    } catch { notify(`${feature.title}启动失败，其他模块可继续使用`); }
  }
  return () => {
    observer.disconnect();
    document.removeEventListener('visibilitychange', visibility);
    document.documentElement.removeAttribute('data-nspp-background');
    clearTimeout(timer);
    cleanups.reverse().forEach(cleanup => { try { cleanup(); } catch { /* Continue cleanup. */ } });
    callbacks.clear(); pending.clear();
  };
}
