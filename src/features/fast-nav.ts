import { toolIcon } from '../lib/tool-icon';

// Proxies NodeSeek's native #fast-nav-button-group into the toolbar: clicks go to the native buttons so the site
// keeps its own scrolling behaviour, and each proxy mirrors its native button's visibility without changing its hit area.
const BUTTONS = [
  { id: 'back-to-top', icon: 'up', title: '回到顶部' },
  { id: 'back-to-parent', icon: 'back', title: '返回上级' },
  { id: 'back-to-bottom', icon: 'down', title: '到达底部' },
] as const;

export function mountFastNav(tools: HTMLElement): () => void {
  const group = document.createElement('div'); group.className = 'nspp-fast-nav';
  const controls = new AbortController(); const { signal } = controls;
  const proxies = BUTTONS.map(({ id, icon, title }) => {
    const button = document.createElement('button'); button.type = 'button'; button.className = 'nspp-tool-icon'; button.title = title;
    button.setAttribute('aria-label', title); button.dataset.nsppFastNav = id; button.hidden = true; button.append(toolIcon(icon));
    button.addEventListener('click', () => document.getElementById(id)?.click(), { signal });
    group.append(button); return button;
  });
  tools.prepend(group);
  let observed: Element | null = null, frame = 0;
  const groupObserver = new MutationObserver(() => schedule());
  const sync = () => {
    frame = 0;
    const native = document.getElementById('fast-nav-button-group');
    if (native !== observed) {
      groupObserver.disconnect(); observed = native;
      if (native) groupObserver.observe(native, { subtree: true, childList: true, attributes: true, attributeFilter: ['style', 'class', 'hidden'] });
    }
    // Hide the native group only while it exists, so the page never loses these controls.
    document.documentElement.toggleAttribute('data-nspp-fast-nav', !!native);
    proxies.forEach((proxy, index) => {
      const target = document.getElementById(BUTTONS[index].id);
      toggle(proxy, !!target && !target.hidden && getComputedStyle(target).display !== 'none');
    });
  };
  // Native controls can change on every scroll frame. Keep size in CSS (38px /
  // 44px on phones) instead of animating a hard-coded 30px height on each change.
  function toggle(proxy: HTMLButtonElement, visible: boolean) {
    if (proxy.hidden === visible) proxy.hidden = !visible;
  }
  function schedule() { if (!frame) frame = requestAnimationFrame(sync); }
  // The site renders the group late and swaps it on SPA navigation; watch for it at the body level (child list only).
  const bodyObserver = new MutationObserver(() => { if (document.getElementById('fast-nav-button-group') !== observed) schedule(); });
  bodyObserver.observe(document.body, { childList: true, subtree: true });
  window.addEventListener('scroll', schedule, { passive: true, signal });
  window.addEventListener('resize', schedule, { passive: true, signal });
  sync();
  return () => {
    controls.abort(); groupObserver.disconnect(); bodyObserver.disconnect(); cancelAnimationFrame(frame);
    document.documentElement.removeAttribute('data-nspp-fast-nav'); group.remove();
  };
}
