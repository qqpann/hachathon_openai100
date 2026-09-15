import http from 'node:http';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { createUsagePolicy, DEFAULT_MODEL } from '../../../server/usage-policy.js';

export const SERVICE = 'seedlab-coach-v1';
export const catalog = JSON.parse(readFileSync(new URL('../data/upgrades.json', import.meta.url), 'utf8'));
const failure = (status, reason) => ({ status, body: { source: 'unavailable', reason } });
const integer = (x, min, max) => Number.isInteger(x) && x >= min && x <= max;
const vector = (x, count, min, max) => Array.isArray(x) && x.length === count && x.every(v => integer(v, min, max));
const boundedLimit = (value, cap) => integer(Number(value), 1, cap) ? String(value) : String(cap);

export function prepare(payload) {
  const s = payload?.state;
  if (!s || s.task !== 'mnist' || !integer(s.trials, 24, 1e7) || !integer(s.credits, 0, 1e7) || !vector(s.levels, 4, 0, 6)
      || !integer(s.camera, 0, 1) || !Array.isArray(s.recent) || s.recent.length > 24 || !s.recent.every(v => v === 0 || v === 1)
      || !vector(s.position_tries, 10, 0, 1e7) || !vector(s.position_wins, 10, 0, 1e7)
      || s.position_wins.some((v, i) => v > s.position_tries[i]) || !vector(s.exam_best, 2, -1, 10)
      || !integer(s.demonstrations, 0, s.trials) || !integer(s.learning_steps, 0, 1e10)
      || !integer(s.streak, 0, s.trials) || s.hidden !== 8 + s.levels[0] * 4) throw new Error('学習データの形式を確認できませんでした。');
  const unlocked = catalog.flatMap((branch, i) => branch.upgrades.slice(0, s.levels[i]).map(v => v.unlock).filter(Boolean));
  if (!unlocked.includes('coach')) throw new Error('学び方Lv.3「育成委任」の強化が必要です。');
  const image = payload.image;
  if (typeof image !== 'string' || image.length > 220000 || !/^data:image\/png;base64,[A-Za-z0-9+/]+=*$/.test(image)) throw new Error('盤面画像を読み込めませんでした。');
  const png = Buffer.from(image.slice(22), 'base64');
  if (png.length < 33 || png.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a'
      || png.toString('ascii', 12, 16) !== 'IHDR' || !integer(png.readUInt32BE(16), 1, 256)
      || !integer(png.readUInt32BE(20), 1, 256)) throw new Error('盤面画像のサイズが不正です。');
  const candidates = catalog.flatMap((branch, i) => {
    const level = s.levels[i];
    const cost = Math.round(branch.base_cost * 1.72 ** level);
    return level < 6 && s.credits - cost >= 30 ? [{ id: `${i}:${level}`, branch: i, level, cost, category: branch.name, ...branch.upgrades[level] }] : [];
  });
  // Explicit projection: no user text, credentials, arbitrary file paths or prompts.
  const state = Object.fromEntries(['task','trials','credits','levels','recent','camera','exam_best','demonstrations','position_tries','position_wins','hidden','learning_steps','streak'].map(k => [k, s[k]]));
  state.unlocked = unlocked;
  return { state, image, candidates };
}

export function createCoach({ env = {}, fetchImpl = fetch, now = Date.now } = {}) {
  const policy = createUsagePolicy({ now });
  const limits = { AI_REQUESTS_PER_MINUTE: boundedLimit(env.AI_REQUESTS_PER_MINUTE, 4), AI_REQUESTS_PER_SESSION: boundedLimit(env.AI_REQUESTS_PER_SESSION, 20) };
  return async payload => {
    let prepared;
    try { prepared = prepare(payload); } catch (error) { return failure(400, error.message); }
    if (!env.OPENAI_API_KEY) return failure(503, 'OpenAIキーが未設定です。接続サーバーの設定を確認してください。');
    const { state, image, candidates } = prepared;
    if (!candidates.length) return { status: 200, body: { source: 'local', decision: 'wait', reason: '購入できる強化がありません。Gを貯めるか、認定試験へ進もう。' } };
    const ids = ['wait', ...candidates.map(v => v.id)];
    const request = {
      model: DEFAULT_MODEL, store: false, max_output_tokens: 400, reasoning: { effort: 'none' },
      instructions: 'あなたは小さな画像学習NNを育てるゲームのOpenAIコーチ。日本語で簡潔に答える。NNは手書き数字MNISTをカメラで撮り12×12に縮めた画像144値→tanh隠れ層→0〜9の10クラスsoftmax予測。押す前は画像だけを見て、採点後に正解ラベルを教わり学習する。あなたはNN自身ではなく外部コーチ。候補の強化を1つ選ぶかwait。残金30G以上は確保済み。画像は現在の強化盤、統計は練習結果（recentには人のお手本も含む）。exam_bestは探索と学習を止めた、練習とは別の手書き画像10問の最高点、-1は未受験。position_tries/winsは数字0〜9別のNNの自動練習のみ。お金の単位はG。実データに基づく選択理由を100文字以内、次の目標を60文字以内。成果を保証しない。候補外を選ばない。未提供の統計を断言しない。recentなどのデータキーは日本語に言い換える。次の目標は実際に操作できるお手本・Aの自動練習・Tの認定試験・Vのカメラ切替から提案する。',
      input: [{ role: 'user', content: [
        { type: 'input_text', text: JSON.stringify({ state, candidates }) },
        { type: 'input_image', image_url: image, detail: 'low' },
      ] }],
      text: { format: { type: 'json_schema', name: 'seedlab_upgrade', strict: true, schema: {
        type: 'object', additionalProperties: false,
        properties: { decision: { type: 'string', enum: ids }, reason: { type: 'string' }, next_goal: { type: 'string' } },
        required: ['decision', 'reason', 'next_goal'],
      } } },
    };
    const key = createHash('sha256').update(env.OPENAI_API_KEY).update(JSON.stringify(request)).digest('hex');
    const result = await policy.run(key, limits, async () => {
      try {
        const upstream = await fetchImpl('https://api.openai.com/v1/responses', {
          method: 'POST', headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(request), signal: AbortSignal.timeout(20000),
        });
        if (!upstream.ok) return failure(502, `OpenAIに接続できませんでした（HTTP ${upstream.status}）。委任を停止しました。`);
        const response = await upstream.json();
        if (response.status !== 'completed') return failure(502, 'OpenAIの回答が完了しませんでした。委任を停止しました。');
        const content = (response.output ?? []).filter(item => item.type === 'message').flatMap(item => item.content ?? []);
        if (content.some(item => item.type === 'refusal')) return failure(502, 'OpenAIがこの依頼に回答しませんでした。');
        const data = JSON.parse(content.filter(item => item.type === 'output_text').map(item => item.text).join(''));
        if (!data || Object.keys(data).sort().join(',') !== 'decision,next_goal,reason' || !ids.includes(data.decision) || typeof data.reason !== 'string' || !data.reason.trim() || data.reason.length > 180
            || typeof data.next_goal !== 'string' || data.next_goal.length > 100) return failure(502, 'OpenAIの選択を確認できませんでした。Gは使っていません。');
        return { status: 200, body: { source: 'live', model: DEFAULT_MODEL, ...data,
          selection: candidates.find(v => v.id === data.decision) ?? null,
          usage: { inputTokens: response.usage?.input_tokens ?? 0, outputTokens: response.usage?.output_tokens ?? 0 },
        } };
      } catch { return failure(502, 'OpenAIとの通信が完了しませんでした。委任を停止しました。'); }
    });
    return result.body.source === 'demo' ? failure(result.status, result.body.reason) : result;
  };
}

export function createBridge(options = {}) {
  const coach = createCoach(options);
  return http.createServer(async (req, res) => {
    const send = result => {
      res.writeHead(result.status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify(result.body));
    };
    // Native Godot only. Reject cross-site browser requests and DNS rebinding.
    if (req.headers.origin || !/^(127\.0\.0\.1|localhost):\d+$/.test(req.headers.host ?? '')) return send(failure(403, 'ローカルのゲームから接続してください。'));
    if (req.method === 'GET' && req.url === '/health') return send({ status: 200, body: { service: SERVICE, configured: Boolean(options.env?.OPENAI_API_KEY), model: DEFAULT_MODEL } });
    if (req.method !== 'POST' || req.url !== '/coach') return send(failure(404, '見つかりません。'));
    if (!req.headers['content-type']?.startsWith('application/json')) return send(failure(415, 'JSONが必要です。'));
    try {
      let size = 0; const chunks = [];
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 250000) { send(failure(413, '画像が大きすぎます。')); req.resume(); return; }
        chunks.push(chunk);
      }
      let payload;
      try { payload = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return send(failure(400, 'JSONを確認できませんでした。')); }
      send(await coach(payload));
    } catch { if (!res.headersSent) send(failure(400, 'リクエストを読み込めませんでした。')); }
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.loadEnvFile(fileURLToPath(new URL('../../../.env.local', import.meta.url))); } catch (error) {
    if (error.code !== 'ENOENT') console.error('SEEDLAB: local environment could not be loaded.');
  }
  const server = createBridge({ env: process.env });
  server.requestTimeout = 25000;
  server.headersTimeout = 10000;
  server.listen(4873, '127.0.0.1', () => console.log('SEEDLAB coach ready on 127.0.0.1:4873; model=' + DEFAULT_MODEL));
  server.on('error', error => { console.error('SEEDLAB bridge could not start: ' + error.code); process.exitCode = 1; });
  for (const signal of ['SIGINT','SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
}
