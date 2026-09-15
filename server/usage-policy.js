export const DEFAULT_MODEL = 'gpt-5.4-nano';
export const outputLimit = game => game === 'counterboss-contract' ? 1400 : game === 'indeterminate' ? 256 : game === 'rebirth-department' ? 360 : 600;

function limit(value, fallback, maximum) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 1 ? Math.min(maximum, Math.floor(n)) : fallback;
}

// Local prototype limits. Each server process owns its counters and short-lived cache.
export function createUsagePolicy({ now = Date.now } = {}) {
  const cache = new Map(), pending = new Map();
  let windowStart = now(), minuteCount = 0, totalCount = 0;
  const blocked = reason => ({ status: 429, body: { source: 'demo', reason } });
  const reused = result => ({ ...result, body: { ...result.body, cacheHit: true } });
  return {
    async run(key, env, request) {
      const time = now();
      for (const [k, entry] of cache) if (entry.expires <= time) cache.delete(k);
      if (cache.has(key)) return reused(cache.get(key).result);
      if (pending.has(key)) return reused(await pending.get(key));
      if (time - windowStart >= 60000) { windowStart = time; minuteCount = 0; }
      if (totalCount >= limit(env.AI_REQUESTS_PER_SESSION, 100, 10000)) return blocked('このサーバー起動中のAI試遊上限に達しました。手動操作・練習モードを利用できます');
      if (minuteCount >= limit(env.AI_REQUESTS_PER_MINUTE, 10, 120)) return blocked('AI試遊の呼び出し上限です。1分後に再試行できます');
      if (pending.size >= 2) return blocked('AIが応答中です。完了してから再度操作してください');
      minuteCount++; totalCount++;
      const promise = Promise.resolve().then(request);
      pending.set(key, promise);
      try {
        const result = await promise;
        if (result.status === 200 && result.body.source === 'live') {
          if (cache.size >= 100) cache.delete(cache.keys().next().value);
          cache.set(key, { result, expires: now() + 5 * 60000 });
        }
        return { ...result, body: { ...result.body, cacheHit: false } };
      } finally { pending.delete(key); }
    },
  };
}
