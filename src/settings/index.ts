import { toolIcon } from "../lib/tool-icon";
import { hasStorage, flushStorage } from "../lib/userscript";
import css from "./style.css?inline";
import loadingCss from "../loading.css?inline";
import { parseSettings, normalizeSettings, exportSettings } from "../core/config";
import { clearCaches, loadSettings, saveSettings } from "../core/runtime";
import type { Feature, Settings } from "../core/types";
import { createUpdateChecker } from "../lib/script-update";
import { aboutContent } from "./about";
import { SHARE_TEXT } from "../features/share";
import { changedFeatures, matchesSearch, mergeSettings } from "./model";

const element = <K extends keyof HTMLElementTagNameMap>(tag: K, text?: string) => {
  const node = document.createElement(tag);
  if (text) node.textContent = text;
  return node;
};

const categoryOrder = ["浏览", "用户", "工具", "其他"];
const categories: Record<string, string> = { 阅读: "浏览", 外观: "浏览", 导航: "浏览", 过滤: "用户", 用户: "用户", 操作辅助: "工具", 监控: "工具", 编辑: "工具", 网络: "其他" };
const categoryOf = (feature: Feature) => categories[feature.group] || "其他";
// Options that only matter in a particular mode stay hidden until that mode is chosen.
const dependsOn: Record<string, (settings: Settings[string]) => boolean> = {
  "user-level.levelColor": settings => settings.colors === "custom",
  "user-level.trustColor": settings => settings.colors === "custom",
  "user-level.roleColor": settings => settings.colors === "custom",
  "image-upload.base": settings => settings.provider !== "NodeImage",
  "reading-focus.height": settings => settings.collapse === true,
};

export function mountSettings(features: Feature[]) {
  const host = element("div");
  host.id = "nspp-settings";
  host.toggleAttribute("data-dark", document.body.classList.contains("dark-layout"));
  const shadow = host.attachShadow({ mode: "open" });
  // Settings owns its responsive layout; generic bottom-sheet rules must not
  // override the flex scroll region and push the save button below the keyboard.
  const style = element("style", css + loadingCss);
  const launch = element("button");
  launch.type = "button"; launch.append(toolIcon("settings"));
  launch.className = "nspp-tool-icon";
  launch.dataset.nsppSettingsLauncher = "";
  launch.title = "打开 NodeSeek++ 设置";
  launch.setAttribute("aria-label", launch.title);
  const dialog = element("dialog");
  dialog.className = "nspp-sheet";
  dialog.setAttribute("aria-labelledby", "nspp-title");
  const header = element("header");
  const heading = element("div");
  const title = element("h2", "NodeSeek++");
  title.id = "nspp-title";
  heading.className = "heading";
  const enabledCount = element("small");
  enabledCount.className = "enabled-count";
  heading.append(title, element("small", `v${__APP_VERSION__}`), enabledCount);
  const brand = element("div"); brand.className = "settings-brand";
  const mark = element("span", "N+"); mark.className = "settings-mark"; mark.setAttribute("aria-hidden", "true");
  const brandCopy = element("div"); brandCopy.className = "settings-brand-copy";
  const subtitle = element("p", "XY EDITION / 论坛增强工作台");
  subtitle.className = "settings-subtitle"; brandCopy.append(heading, subtitle); brand.append(mark, brandCopy);
  const close = element("button", "关闭");
  close.type = "button";
  close.className = "settings-close";
  const headerClose = element("button"); headerClose.type = "button";
  headerClose.className = "header-close"; headerClose.append(toolIcon("close"));
  headerClose.setAttribute("aria-label", "关闭设置");
  const search = element("input");
  search.type = "search";
  search.placeholder = "搜索功能、选项或关键词";
  search.setAttribute("aria-label", "搜索功能");
  const searchBar = element("div");
  searchBar.className = "search-bar";
  const searchKey = element("kbd", "/"); searchKey.setAttribute("aria-hidden", "true");
  searchBar.append(search, searchKey);
  header.append(brand, headerClose);
  const content = element("div");
  content.className = "content"; content.setAttribute("aria-label", "功能列表");
  const navigation = element("nav");
  navigation.className = "categories";
  navigation.setAttribute("aria-label", "设置分类");
  const results = element("small"); results.className = "settings-results"; results.setAttribute("role", "status");
  const workspace = element("div");
  workspace.className = "settings-workspace";
  const sidebar = element("aside"); sidebar.className = "settings-sidebar";
  const sidebarNote = element("small", "按需开启，让浏览更轻松。"); sidebarNote.className = "sidebar-note";
  sidebar.append(element("small", "工作台"), navigation, sidebarNote);
  const main = element("div"); main.className = "settings-main";
  const intro = element("div"); intro.className = "settings-intro";
  const viewTitle = element("h3", "全部功能");
  const viewDescription = element("p", "阅读、互动与常用工具，按你的习惯调整。");
  intro.append(viewTitle, viewDescription);
  const filters = element("div"); filters.className = "settings-filters"; filters.setAttribute("role", "group"); filters.setAttribute("aria-label", "筛选功能");
  const filterButtons = new Map<string, HTMLButtonElement>();
  for (const [value, label] of [["all", "全部"], ["enabled", "已启用"], ["modified", "已修改"]]) {
    const button = element("button", label); button.type = "button"; button.dataset.filter = value;
    button.addEventListener("click", () => { filter = value; applyFilters(true); });
    filterButtons.set(value, button); filters.append(button);
  }
  const toolbar = element("div"); toolbar.className = "settings-toolbar"; toolbar.append(filters, results);
  main.append(intro, searchBar, toolbar, content);
  workspace.append(sidebar, main);
  const form = element("form");
  form.noValidate = true;

  const status = element("p");
  status.className = "status";
  status.setAttribute("role", "status");
  const actions = element("div");
  actions.className = "actions";
  const save = element("button", "保存并刷新");
  save.type = "submit";
  save.className = "primary";
  const reset = element("button", "恢复默认");
  const clearCache = element("button", "清空缓存");
  clearCache.title = "清除当前站点的插件用户资料、通知计数和回帖足迹缓存并刷新页面；保留配置、阅读历史和监控记录，未保存的设置不会保存。";
  const exportButton = element("button", "导出配置");
  const importButton = element("button", "导入配置");
  const undo = element("button", "撤销修改"); undo.type = "button"; undo.className = "settings-undo"; undo.hidden = true;
  reset.title = "所有功能恢复默认，保存后生效。";
  exportButton.title = "导出为 JSON，不含密钥和历史。";
  [reset, clearCache, exportButton, importButton].forEach(button => button.type = "button");
  const file = element("input");
  file.type = "file";
  file.accept = ".json,application/json";
  file.hidden = true;
  const dataTools = element("div");
  dataTools.className = "data-tools";
  dataTools.append(exportButton, importButton, clearCache, reset, file);
  actions.append(undo, close, save);
  const footer = element("footer");
  footer.className = "settings-footer";
  const footerHint = element("small", "设置已同步 · 修改后保存生效"); footerHint.setAttribute("role", "status");
  footerHint.className = "settings-footer-hint"; footer.prepend(footerHint);
  footer.append(actions);
  form.append(header, status, workspace, footer);
  dialog.append(form);
  const toast = element("div");
  toast.className = "toast";
  toast.hidden = true;
  toast.setAttribute("role", "status");
  toast.setAttribute("aria-live", "polite");
  toast.setAttribute("aria-atomic", "true");
  toast.setAttribute("popover", "manual");
  const toastIcon = element("span");
  toastIcon.className = "toast-icon";
  toastIcon.setAttribute("aria-hidden", "true");
  const toastMessage = element("span");
  toastMessage.className = "toast-message";
  const toastClose = element("button", "×");
  toastClose.type = "button";
  toastClose.className = "toast-close";
  toastClose.setAttribute("aria-label", "关闭提示");
  toast.append(toastIcon, toastMessage, toastClose);
  shadow.append(style, dialog, toast);
  (document.getElementById("nspp-tools") || document.body).append(launch);
  document.body.append(host);
  let draft: Settings = loadSettings(features);
  let baseline = structuredClone(draft);
  let filter = "all", selectedCategory = "全部";
  let saving = false, busy = false;
  const changed = () => changedFeatures(features, baseline, draft);
  let toastTimer: ReturnType<typeof setTimeout>;
  const dismissToast = () => {
    clearTimeout(toastTimer);
    toast.hidePopover?.();
    toast.hidden = true;
  };
  toastClose.addEventListener("click", dismissToast);
  const notify = (message: string, type: "info" | "success" | "error" = "info") => {
    host.toggleAttribute("data-dark", document.body.classList.contains("dark-layout"));
    toast.dataset.type = type;
    toastIcon.textContent = { info: "i", success: "✓", error: "!" }[type];
    toastMessage.textContent = message;
    toast.hidden = false;
    toast.hidePopover?.();
    toast.showPopover?.();
    clearTimeout(toastTimer);
    toastTimer = setTimeout(dismissToast, 6000);
  };
  const updates = createUpdateChecker(notify, () => !document.hidden && !dialog.open && !document.querySelector('dialog[open]'));

  const categoryDescriptions: Record<string, string> = {
    全部: "阅读、互动与常用工具，按你的习惯调整。",
    浏览: "更顺畅地阅读、预览和查找帖子。", 用户: "管理关注、过滤规则和用户信息。",
    工具: "签到、监控、编辑与日常操作。", 其他: "网络请求与扩展选项。",
    数据: "备份配置、管理缓存和检查版本。",
  };
  const categoryIcons = { 全部: "settings", 浏览: "history", 用户: "messages", 工具: "monitor", 其他: "ai", 数据: "share" } as const;
  const navButtons = new Map<string, HTMLButtonElement>();
  for (const name of ["全部", ...categoryOrder, "数据"]) {
    const button = element("button"); button.type = "button"; button.dataset.category = name;
    button.append(toolIcon(categoryIcons[name as keyof typeof categoryIcons]), element("span", name === "全部" ? "全部功能" : name === "数据" ? "数据与关于" : name));
    const count = element("small"); count.className = "category-count"; button.append(count);
    button.addEventListener("click", () => { selectedCategory = name; search.value = ""; applyFilters(true); });
    navButtons.set(name, button); navigation.append(button);
  }
  const sections = new Map<string, HTMLElement>();
  const cards = new Map<string, HTMLElement>();
  const searchIndex = new Map(features.map(feature => [feature.id,
    `${feature.title} ${feature.description} ${feature.group} ${categoryOf(feature)} ${Object.values(feature.fields || {}).map(field => field.label).join(' ')}`.toLocaleLowerCase(),
  ]));
  const empty = element("div"); empty.className = "settings-empty";
  empty.append(element("strong", "没有找到相关功能"), element("p", "换个关键词，或重置筛选查看全部功能。"));
  const resetFilters = element("button", "重置筛选"); resetFilters.type = "button";
  resetFilters.addEventListener("click", () => { search.value = ""; selectedCategory = "全部"; filter = "all"; applyFilters(true); });
  empty.append(resetFilters);
  function addSection(name: string) {
    const group = element("section");
    group.dataset.section = name;
    sections.set(name, group);
    group.append(element("h4", name === "数据" ? "数据与关于" : name));
    content.append(group);
    return group;
  }
  function renderFeature(feature: Feature) {
    const settings = draft[feature.id];
    const row = element("article"); row.className = "feature-card";
    row.dataset.feature = feature.id;
    const label = element("label");
    label.className = "feature-heading";
    const copy = element("span"); copy.className = "feature-copy";
    const description = element("small", feature.description);
    const featureName = element("strong", feature.title);
    const modified = element("span", "已修改"); modified.className = "modified-badge"; modified.hidden = true;
    featureName.append(modified);
    copy.append(featureName, description);
    const toggle = element("input");
    toggle.type = "checkbox";
    toggle.checked = settings.enabled === true;
    toggle.className = "feature-toggle"; row.dataset.enabled = String(toggle.checked);
    toggle.setAttribute("aria-label", `启用${feature.title}`);
    label.append(copy, toggle);
    row.append(label);
    const options = Object.keys(feature.defaults).filter(key => key !== "enabled");
    if (!options.length) {
      toggle.addEventListener("change", () => { settings.enabled = toggle.checked; row.dataset.enabled = String(toggle.checked); applyFilters(); });
      return row;
    }
    const details = element("fieldset");
    details.className = "feature-options";
    details.id = `options-${feature.id}`;
    details.setAttribute("aria-label", `${feature.title}的选项`);
    const expand = element("button", `${options.length} 项设置`); expand.type = "button";
    expand.className = "feature-expand"; expand.setAttribute("aria-controls", details.id);
    let expanded = false;
    const conditional: [HTMLElement, () => boolean][] = [];
    const sync = () => {
      details.hidden = !toggle.checked || !expanded;
      details.disabled = !toggle.checked;
      expand.hidden = !toggle.checked;
      expand.setAttribute("aria-expanded", String(expanded && toggle.checked));
      expand.setAttribute("aria-label", `${feature.title}：${expanded ? "收起" : "展开"}设置`);
      expand.textContent = expanded ? "收起设置" : `${options.length} 项设置`;
      for (const [field, visible] of conditional) {
        field.hidden = !visible();
        field.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>('input, select, textarea').forEach(control => control.disabled = !!field.hidden);
      }
    };
    expand.addEventListener("click", () => { expanded = !expanded; sync(); });
    toggle.addEventListener("change", () => { settings.enabled = toggle.checked; row.dataset.enabled = String(toggle.checked); sync(); applyFilters(); });
    for (const key of options) {
      const metadata = feature.fields?.[key];
      const value = settings[key];
      const field = element("label");
      field.className = "field";
      field.append(element("span", metadata?.label || key));
      let control: HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
      if (metadata?.type === "select") {
        control = element("select");
        for (const option of metadata.options || []) {
          const item = element("option", option.label);
          item.value = option.value;
          control.append(item);
        }
      } else if (metadata?.type === "textarea") {
        control = element("textarea");
        control.rows = 3;
      } else {
        control = element("input");
        control.type = metadata?.type === "color" ? "color" : typeof value === "boolean" ? "checkbox" : typeof value === "number" ? "number" : /^(api[-_]?key|token|password|secret|access[-_]?token)$/i.test(key) ? "password" : "text";
      }
      if (typeof value === "boolean" && control instanceof HTMLInputElement) control.checked = value;
      else if (feature.id === 'request-settings' && control instanceof HTMLInputElement) { control.min = key === 'maxConcurrent' ? '1' : '0'; control.max = key === 'maxConcurrent' ? '10' : '5000'; control.step = '1'; control.value = String(value); }
      else control.value = String(value);
      control.dataset.option = key;
      control.addEventListener("input", () => {
        settings[key] = typeof value === "boolean" ? (control as HTMLInputElement).checked
          : typeof value === "number" ? Number(control.value) : control.value;
        sync(); updateEnabledCount();
      });
      control.addEventListener("change", () => applyFilters());
      field.append(control);
      details.append(field);
      const visible = dependsOn[`${feature.id}.${key}`];
      if (visible) conditional.push([field, () => visible(settings)]);
    }
    sync();
    row.append(expand, details);
    return row;
  }
  function updateEnabledCount() {
    const active = features.filter(feature => draft[feature.id]?.enabled === true).length;
    enabledCount.textContent = `${active}/${features.length} 已启用`;
    const modified = changed();
    window.removeEventListener("beforeunload", beforeUnload);
    if (modified.size) window.addEventListener("beforeunload", beforeUnload);
    host.toggleAttribute("data-dirty", modified.size > 0);
    footerHint.textContent = modified.size ? `${modified.size} 项功能已修改 · 尚未保存` : "设置已同步 · 修改后保存生效";
    close.textContent = modified.size ? "稍后再改" : "关闭";
    undo.hidden = !modified.size;
    for (const [id, row] of cards) {
      row.querySelector<HTMLElement>(".modified-badge")!.hidden = !modified.has(id);
      row.toggleAttribute("data-modified", modified.has(id));
    }
    filterButtons.get("enabled")!.textContent = `已启用 ${active}`;
    filterButtons.get("modified")!.textContent = `已修改 ${modified.size}`;
  }
  function applyFilters(resetScroll = false) {
    const query = search.value.trim();
    const modified = changed();
    let visibleFeatures = 0;
    for (const feature of features) {
      const visible = (selectedCategory === "全部" || categoryOf(feature) === selectedCategory)
        && (filter === "all" || (filter === "enabled" ? draft[feature.id].enabled : modified.has(feature.id)))
        && matchesSearch(searchIndex.get(feature.id)!, query);
      cards.get(feature.id)!.hidden = !visible;
      if (visible) visibleFeatures++;
    }
    for (const [name, group] of sections) {
      if (name === "数据") continue;
      group.hidden = ![...group.querySelectorAll<HTMLElement>(".feature-card")].some(row => !row.hidden);
    }
    const data = sections.get("数据")!;
    data.hidden = !["全部", "数据"].includes(selectedCategory) || filter !== "all"
      || !matchesSearch("数据 导出 导入 配置 缓存 恢复默认 备份 关于 nodeseek++ github 项目地址 下载 安装 更新 版本 使用说明 反馈 开源 许可证", query);
    empty.hidden = visibleFeatures > 0 || !data.hidden;
    results.textContent = query ? `找到 ${visibleFeatures} 项匹配功能` : `${visibleFeatures} 项功能`;
    viewTitle.textContent = query ? "搜索结果" : selectedCategory === "全部" ? "全部功能" : selectedCategory === "数据" ? "数据与关于" : `${selectedCategory}设置`;
    viewDescription.textContent = query ? `在所有功能中查找「${query}」` : categoryDescriptions[selectedCategory];
    for (const [name, button] of navButtons) {
      if (name === selectedCategory) button.setAttribute("aria-current", "page"); else button.removeAttribute("aria-current");
      button.querySelector("small")!.textContent = name === "数据" ? "" : String(name === "全部" ? features.length : features.filter(feature => categoryOf(feature) === name).length);
    }
    filterButtons.forEach((button, value) => button.setAttribute("aria-pressed", String(filter === value)));
    updateEnabledCount();
    if (resetScroll) content.scrollTop = 0;
  }
  function render() {
    content.replaceChildren(); sections.clear(); cards.clear();
    const ordered = [...features].sort((a, b) => categoryOrder.indexOf(categoryOf(a)) - categoryOrder.indexOf(categoryOf(b)));
    for (const feature of ordered) {
      const category = categoryOf(feature);
      const group = sections.get(category) || addSection(category);
      const row = renderFeature(feature); cards.set(feature.id, row); group.append(row);
    }
    const group = addSection("数据");
    const row = element("article"); row.className = "data-card";
    row.append(element("strong", "配置与缓存"), element("p", "配置导出不含密钥或历史记录。清空缓存会刷新页面，阅读历史与私信存档会保留。"), dataTools);
    group.append(row, aboutContent(() => updates.check(), () => {
      const launcher = document.querySelector<HTMLButtonElement>('[data-nspp-share-launcher]');
      if (!launcher) {
        if (!navigator.clipboard) { notify('当前浏览器不支持复制，请从项目主页下载安装', 'error'); return; }
        void navigator.clipboard.writeText(SHARE_TEXT).then(() => notify('已复制分享文案和安装地址', 'success'), () => notify('复制失败，请手动复制项目地址', 'error'));
        return;
      }
      dialog.close(); launcher.click();
    }));
    content.append(empty);
    applyFilters(true);
  }
  // The forum can change themes without reloading; keep shadow-root tokens in sync.
  const syncTheme = () => host.toggleAttribute("data-dark", document.body.classList.contains("dark-layout"));
  const themeObserver = new MutationObserver(syncTheme);
  themeObserver.observe(document.body, { attributes: true, attributeFilter: ["class"] });
  const open = () => {
    syncTheme();
    if (dialog.open) return;
    // Keep this page's unsaved draft on reopen; a clean panel reads fresh storage.
    if (!changed().size) { draft = loadSettings(features); baseline = structuredClone(draft); }
    status.textContent = hasStorage() ? "" : "油猴存储未就绪，请重新安装脚本后刷新。";
    save.disabled = !hasStorage();
    clearCache.disabled = !hasStorage();
    render();
    if (!dialog.open) dialog.showModal();
    document.documentElement.setAttribute('data-nspp-settings-open', '');
    if (matchMedia("(min-width: 701px)").matches) search.focus();
    else close.focus();
  };
  launch.addEventListener("click", open);
  const closePanel = () => { if (!busy && !saving) dialog.close(); };
  close.addEventListener("click", closePanel);
  headerClose.addEventListener("click", closePanel);
  dialog.addEventListener("cancel", event => { if (busy || saving) event.preventDefault(); });
  dialog.addEventListener("click", event => { if (event.target === dialog) {
    const box = dialog.getBoundingClientRect();
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) closePanel();
  } });
  dialog.addEventListener("close", () => { document.documentElement.removeAttribute('data-nspp-settings-open'); launch.focus(); });
  search.addEventListener("input", () => {
    selectedCategory = "全部"; applyFilters(true);
  });
  // Pressing Enter in a search field inside the form must never submit all settings.
  search.addEventListener("keydown", event => {
    if (event.key === "Enter") event.preventDefault();
    if (event.key === "Escape" && search.value) {
      event.preventDefault(); event.stopPropagation();
      search.value = ""; applyFilters(true);
    }
  });
  dialog.addEventListener("keydown", event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
      event.preventDefault(); if (!save.disabled) form.requestSubmit(); return;
    }
    if (event.key !== "/" || event.ctrlKey || event.metaKey || event.altKey) return;
    const target = event.target as HTMLElement;
    if (target.closest("input,textarea,select,[contenteditable]")) return;
    event.preventDefault(); search.focus();
  });
  const setBusy = (value: boolean) => {
    busy = value;
    form.querySelectorAll<HTMLButtonElement>("button").forEach(button => button.disabled = value);
    form.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>("input,select,textarea").forEach(control => {
      if (value) { control.dataset.wasDisabled = String(control.disabled); control.disabled = true; }
      else if (control.dataset.wasDisabled !== undefined) { control.disabled = control.dataset.wasDisabled === "true"; delete control.dataset.wasDisabled; }
    });
    if (!value) { save.disabled = !hasStorage(); clearCache.disabled = !hasStorage(); }
  };
  function beforeUnload(event: BeforeUnloadEvent) {
    if (!saving && changed().size) { event.preventDefault(); event.returnValue = ""; }
  }
  form.addEventListener("submit", async event => {
    event.preventDefault();
    if (busy || saving || !hasStorage()) return;
    // Validate even collapsed fields. Reveal an invalid field before focusing it.
    const invalid = [...content.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>("input,select,textarea")]
      .find(control => !control.closest("fieldset[disabled]") && control.willValidate && !control.checkValidity());
    if (invalid) {
      search.value = ""; selectedCategory = "全部"; filter = "all"; applyFilters();
      const row = invalid.closest<HTMLElement>(".feature-card")!;
      const expand = row.querySelector<HTMLButtonElement>(".feature-expand");
      if (expand?.getAttribute("aria-expanded") === "false") expand.click();
      invalid.scrollIntoView({ block: "center" }); invalid.focus(); invalid.reportValidity(); return;
    }
    setBusy(true);
    save.setAttribute("aria-busy", "true"); save.textContent = "正在保存…";
    try {
      const next = mergeSettings(features, baseline, draft, loadSettings(features));
      saveSettings(features, next); await flushStorage();
      draft = next; baseline = structuredClone(next); saving = true; location.reload();
    } catch {
      setBusy(false); save.removeAttribute("aria-busy"); save.textContent = "保存并刷新";
      notify("保存失败，请检查油猴存储权限后重试。", "error");
    }
  });
  undo.addEventListener("click", () => { draft = structuredClone(baseline); render(); });
  reset.addEventListener("click", () => {
    draft = normalizeSettings(features, {});
    render();
    notify("已恢复默认，保存后生效。", "success");
  });
  clearCache.addEventListener("click", async () => {
    if (busy) return;
    if (changed().size) { notify("请先保存或撤销修改，再清空缓存。", "info"); return; }
    setBusy(true);
    clearCache.setAttribute("aria-busy", "true");
    clearCache.textContent = "正在清空…";
    try { clearCaches(); await flushStorage(); location.reload(); }
    catch {
      setBusy(false);
      clearCache.removeAttribute("aria-busy");
      clearCache.textContent = "清空缓存";
      notify("清空缓存失败，请检查油猴存储权限后重试。", "error");
    }
  });
  exportButton.addEventListener("click", () => {
    const blob = new Blob([exportSettings(draft)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = element("a");
    link.href = url;
    link.download = "nodeseek-plus-plus-settings.json";
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    notify("已导出配置（不含密钥和历史）。", "success");
  });
  importButton.addEventListener("click", () => file.click());
  file.addEventListener("change", async () => {
    const selected = file.files?.[0];
    if (!selected) return;
    if (busy) return;
    setBusy(true);
    importButton.setAttribute("aria-busy", "true");
    importButton.textContent = "正在导入…";
    try {
      if (selected.size > 1_000_000) throw new Error("配置文件不能超过 1 MB");
      draft = parseSettings(features, await selected.text());
      render();
      notify("已导入，保存后生效。", "success");
    } catch (error) { notify(error instanceof Error ? error.message : "导入失败", "error"); }
    finally { file.value = ""; setBusy(false); importButton.removeAttribute("aria-busy"); importButton.textContent = "导入配置"; }
  });
  return { open, notify, stopUpdates: () => { themeObserver.disconnect(); updates.stop(); dismissToast(); window.removeEventListener("beforeunload", beforeUnload); } };
}
