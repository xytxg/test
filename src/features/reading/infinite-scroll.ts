import { toolIcon } from '../../lib/tool-icon';
import type { Context, Feature } from '../../core/types';
import { postPath } from '../reading-logic';
import { sweepShine } from '../../views/sweep-shine';
function mount(ctx: Context) {
    const comments = /^\/post-/.test(location.pathname);
    if (!ctx.get<boolean>(comments ? 'comments' : 'posts'))
        return;
    const selector = comments ? 'ul.comments' : 'ul.post-list:not(.topic-carousel-panel)';
    const list = document.querySelector(selector);
    if (!list)
        return;
    const postId = comments ? location.pathname.match(/^\/post-(\d+)/)?.[1] : undefined;
    const validNext = (href: string): boolean => {
        try {
            const url = new URL(href, location.href);
            if (url.origin !== location.origin || url.protocol !== location.protocol) return false;
            if (comments) return !!postId && url.pathname.match(/^\/post-(\d+)(?:-\d+)?(?:\.html)?\/?$/)?.[1] === postId;
            return true;
        } catch { return false; }
    };
    const initial = document.querySelector<HTMLAnchorElement>('.nsk-pager a.pager-next')?.href;
    let next = initial && validNext(initial) ? initial : undefined;
    let busy = false, failed = false, paused = false;
    // Retain all loaded content, but avoid automatically growing the DOM forever.
    // 0 means unlimited, and manual load never counts against the automatic budget.
    const configured = Number(ctx.get<number>('autoMaxPages'));
    const maxAutoPages = Number.isFinite(configured) ? Math.max(0, Math.min(50, Math.floor(configured))) : 6;
    let autoPages = 0;
    const atAutoLimit = () => maxAutoPages > 0 && autoPages >= maxAutoPages;
    const replying = () => comments && document.documentElement.hasAttribute('data-nspp-reply-open');
    let loading: AbortController | undefined;
    const visited = new Set([location.href]);
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'nspp-action';
    button.textContent = '加载下一页';
    list.after(button);
    const pause = document.createElement('button'); pause.type = 'button'; pause.className = 'nspp-tool-icon';
    const renderPause = () => {
        pause.replaceChildren(toolIcon(paused ? 'play' : 'stop'));
        pause.title = paused ? '继续自动翻页' : '暂停自动翻页';
        pause.setAttribute('aria-label', pause.title); pause.setAttribute('aria-pressed', String(paused));
    };
    renderPause();
    if (next) (document.querySelector('#nspp-tools') || document.body).append(pause);
    pause.addEventListener('click', () => {
        paused = !paused; renderPause();
        if (paused) { observer.disconnect(); loading?.abort(); }
        else if (next && !atAutoLimit()) observer.observe(button);
    }, { signal: ctx.signal });
    const load = async (manual = false) => {
        if (busy || !next || visited.has(next) || ctx.signal.aborted || replying() || (!manual && atAutoLimit()))
            return;
        const url = new URL(next, location.href);
        if (url.origin !== location.origin)
            return;
        busy = true;
        loading = new AbortController();
        button.disabled = true;
        button.setAttribute('aria-busy', 'true');
        button.replaceChildren(sweepShine('正在加载…'));
        try {
            const html = await ctx.request<string>(url.href, { responseType: 'text', signal: AbortSignal.any([ctx.signal, loading.signal]) });
            if (ctx.signal.aborted || loading.signal.aborted || replying() || (paused && !manual))
                return;
            const page = new DOMParser().parseFromString(html, 'text/html');
            const source = page.querySelector(selector);
            if (!source || !source.children.length)
                throw new Error('页面内容不可用');
            source.querySelectorAll('script, iframe, object, embed, base, link, style').forEach(el => el.remove());
            if (comments) {
                // Fetched comment controls have no original JavaScript listeners.
                // Remove dead reply/quote forms and provide the working original-page link instead.
                source.querySelectorAll('button, form, input, select, textarea').forEach(el => el.remove());
            }
            source.querySelectorAll('*').forEach(el => {
                for (const attr of Array.from(el.attributes)) {
                    if (attr.name === 'target' && attr.value === '_blank' && el.tagName === 'A') {
                        const current = el.getAttribute('rel') || '';
                        el.setAttribute('rel', [...new Set([...current.split(/\s+/).filter(Boolean), 'noopener', 'noreferrer'])].join(' '));
                    }
                    if (/^on/i.test(attr.name) || attr.name === 'srcdoc') {
                        el.removeAttribute(attr.name);
                    } else if (/^(href|src|action|formaction|xlink:href)$/i.test(attr.name)) {
                        try {
                            const resolved = new URL(attr.value, url);
                            if (!['http:', 'https:', 'mailto:', 'tel:'].includes(resolved.protocol)) el.removeAttribute(attr.name);
                            else if (!attr.value.startsWith('#')) el.setAttribute(attr.name, resolved.href);
                        } catch { el.removeAttribute(attr.name); }
                    }
                }
            });
            // Collect listed post paths once per page instead of rescanning the whole list for every fetched row.
            const listed = comments ? undefined : new Set(Array.from(list.querySelectorAll<HTMLAnchorElement>('.post-title a'), a => postPath(a.href, location.href)));
            for (const child of Array.from(source.children)) {
                const id = child.id;
                if (id && document.getElementById(id))
                    continue;
                if (listed) {
                    const href = child.querySelector<HTMLAnchorElement>('.post-title a')?.getAttribute('href');
                    if (href) {
                        const path = postPath(href, url.href);
                        if (listed.has(path))
                            continue;
                        listed.add(path);
                    }
                }
                const imported = document.importNode(child, true);
                if (comments) {
                    // Event handlers on fetched pages do not survive DOMParser/importNode.
                    // Link to the exact original page instead of showing a fake working reply.
                    const actions = document.createElement('a');
                    actions.className = 'nspp-original-comment-action';
                    actions.textContent = '前往原页引用或回复 ↗';
                    const original = new URL(url.href);
                    if (imported.id) original.hash = encodeURIComponent(imported.id);
                    actions.href = original.href;
                    actions.target = '_blank';
                    actions.rel = 'noopener noreferrer';
                    imported.append(actions);
                }
                list.append(imported);
            }
            visited.add(url.href);
            if (!manual) autoPages++;
            failed = false;
            const href = page.querySelector<HTMLAnchorElement>('.nsk-pager a.pager-next')?.getAttribute('href');
            const candidate = href ? new URL(href, url).href : undefined;
            next = candidate && validNext(candidate) ? candidate : undefined;
            if (next && visited.has(next))
                next = undefined;
            button.textContent = !next ? '已加载全部内容' : atAutoLimit() ? '自动加载已达上限，点击继续' : '加载下一页';
            pause.hidden = !next || atAutoLimit();
            if (atAutoLimit()) observer.unobserve(button);
        }
        catch {
            if (loading.signal.aborted) return;
            failed = true;
            button.textContent = '加载失败，点击重试';
        }
        finally {
            busy = false;
            button.disabled = !next;
            button.removeAttribute('aria-busy');
            if (paused && next) button.textContent = '已暂停，点击加载下一页';
            if (loading.signal.aborted && next) button.textContent = paused ? '已暂停，点击加载下一页' : atAutoLimit() ? '自动加载已达上限，点击继续' : '加载下一页';
            if (loading.signal.aborted && !ctx.signal.aborted && !paused && !replying() && next && !atAutoLimit()) { observer.unobserve(button); observer.observe(button); }
        }
    };
    button.addEventListener('click', () => { void load(true); }, { signal: ctx.signal });
    const observer = new IntersectionObserver(entries => { if (entries.some(e => e.isIntersecting) && !failed && !paused && !atAutoLimit() && !replying() && !document.hidden)
        void load(); }, { rootMargin: '150px' });
    document.addEventListener('nspp:reply-state', () => {
        if (replying()) { observer.disconnect(); loading?.abort(); }
        else if (next && !paused && !atAutoLimit()) observer.observe(button);
    }, { signal: ctx.signal });
    if (next)
        observer.observe(button);
    else
        button.hidden = true;
    return () => { observer.disconnect(); loading?.abort(); button.remove(); pause.remove(); };
}
export const infiniteScroll: Feature = { id: 'infinite-scroll', title: '自动翻页', description: '合并下一页帖子或评论；自动加载页数可限制，达到上限仍可手动继续。自动加载评论附有原页回复入口。', group: '阅读', defaults: { enabled: true, posts: true, comments: false, autoMaxPages: 6 }, fields: { posts: { label: '帖子自动翻页', type: 'text' }, comments: { label: '评论自动翻页（仅阅读）', type: 'text' }, autoMaxPages: { label: '最多自动加载页数（0 不限制，默认 6）', type: 'number' } }, mount };
