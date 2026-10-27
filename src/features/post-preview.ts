import type { Feature } from '../core/types';
import { createPostPreview } from '../views/post-preview';

export const postPreview: Feature = {
  id: 'post-preview', title: '帖子卡片预览', group: '阅读',
  description: '桌面悬停预览；移动端默认点击标题进入原帖，另有“预览”按钮。可在设置中恢复点击标题预览。',
  defaults: { enabled: true, mobileTap: 'original' },
  fields: { mobileTap: { label: '移动端点击标题', type: 'select', options: [{ label: '进入原帖（推荐）', value: 'original' }, { label: '打开预览弹窗', value: 'preview' }] } },
  mount(ctx) {
    const preview = createPostPreview(ctx);
    const bound = new Map<HTMLAnchorElement, { title: string | null; button: HTMLButtonElement }>();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const stop = ctx.watch(() => {
      for (const [link, value] of bound) if (!link.isConnected) { value.button.remove(); bound.delete(link); }
      document.querySelectorAll<HTMLAnchorElement>('.post-list-item .post-title a').forEach(link => {
        if (bound.has(link)) return;
        const url = new URL(link.href, location.origin);
        if (url.origin !== location.origin || !/^\/post-\d+(?:-\d+)?(?:\.html)?\/?$/.test(url.pathname)) return;
        const title = link.getAttribute('title');
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'nspp-title-preview';
        button.textContent = '预览';
        button.title = '预览帖子内容（不离开当前页）';
        button.setAttribute('aria-label', '预览帖子');
        button.addEventListener('click', () => { clearTimeout(timer); preview.open(link, 'preview'); }, { signal: ctx.signal });
        link.after(button);
        bound.set(link, { title, button });
        link.removeAttribute('title');
        link.addEventListener('mouseenter', () => {
          if (!matchMedia('(hover: hover)').matches) return;
          preview.keepOpen();
          clearTimeout(timer); timer = setTimeout(() => preview.open(link, 'preview'), 400);
        }, { signal: ctx.signal });
        link.addEventListener('mouseleave', () => { clearTimeout(timer); preview.scheduleClose(); }, { signal: ctx.signal });
        link.addEventListener('click', event => {
          if (ctx.get<string>('mobileTap') !== 'preview' || !matchMedia('(max-width: 700px), (hover: none)').matches || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
          event.preventDefault(); clearTimeout(timer);
          preview.open(link, 'preview');
        }, { signal: ctx.signal });
      });
    });
    return () => {
      stop(); clearTimeout(timer);
      for (const [link, { title, button }] of bound) {
        button.remove();
        if (title !== null) link.setAttribute('title', title);
      }
      bound.clear(); preview.destroy();
    };
  },
};
