export function requestConcurrency(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(1, Math.min(10, Math.floor(value))) : 4;
}

export function requestInterval(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.min(5000, Math.floor(value))) : 200;
}

export function retryDelay(value: string | null, now = Date.now()): number {
  if (!value) return 60_000;
  const seconds = Number(value);
  const delay = Number.isFinite(seconds) ? seconds * 1000 : Date.parse(value) - now;
  return Number.isFinite(delay) ? Math.max(60_000, delay) : 60_000;
}

/** Requests cancelled before dispatch are removed from the queue immediately. */
export function createRequestQueue(limit: () => number = () => 1, interval: () => number = () => 0) {
  type Job = { priority: number; run(): Promise<void> };
  const pending: Job[] = [];
  let active = 0;
  let lastStarted = -Infinity;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const drain = () => {
    clearTimeout(timer);
    timer = undefined;
    while (pending.length && active < requestConcurrency(limit())) {
      const delay = lastStarted + requestInterval(interval()) - Date.now();
      if (delay > 0) { timer = setTimeout(drain, delay); return; }
      pending.sort((a, b) => a.priority - b.priority);
      const next = pending.shift()!;
      active++;
      lastStarted = Date.now();
      void next.run().finally(() => { active--; drain(); });
    }
  };
  return <T>(task: () => Promise<T>, priority = 0, signal?: AbortSignal): Promise<T> => new Promise((resolve, reject) => {
    if (signal?.aborted) { reject(signal.reason); return; }
    let started = false;
    const job: Job = {
      priority,
      run: async () => {
        started = true;
        signal?.removeEventListener('abort', cancel);
        try { signal?.throwIfAborted(); resolve(await task()); }
        catch (error) { reject(error); }
      },
    };
    const cancel = () => {
      if (started) return;
      const index = pending.indexOf(job);
      if (index >= 0) {
        pending.splice(index, 1);
        reject(signal?.reason ?? new DOMException('Aborted', 'AbortError'));
        drain();
      }
    };
    pending.push(job);
    signal?.addEventListener('abort', cancel, { once: true });
    drain();
  });
}
