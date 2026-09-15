import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createCoach, createBridge, prepare, SERVICE } from './server.mjs';
const image = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';
const payload = () => ({ image, state: { task: 'mnist', trials: 24, credits: 400, levels: [0,0,3,0], camera: 0, recent: [1,0,0,1], position_tries: Array(10).fill(2), position_wins: Array(10).fill(1), exam_best: [-1,-1], demonstrations: 4, learning_steps: 600, streak: 1, hidden: 8 } });
const completed = (data = { decision: '1:0', reason: '以前の経験を復習できるよう、記憶を増やそう。', next_goal: '認定試験で3点を目指そう。' }) => ({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(data) }] }], usage: { input_tokens: 200, output_tokens: 60 } });
const fake = data => async () => ({ ok: true, json: async () => data });
const env = { OPENAI_API_KEY: 'test-key-never-real' };

test('coach sends actual image and bounded structured request; duplicate result is reused', async () => {
  let calls = 0;
  const coach = createCoach({ env, fetchImpl: async (url, init) => {
    calls++;
    assert.equal(url, 'https://api.openai.com/v1/responses');
    const request = JSON.parse(init.body);
    assert.equal(request.model, 'gpt-5.4-nano');
    assert.match(request.instructions, /10クラスsoftmax/);
    assert.equal(JSON.parse(request.input[0].content[0].text).state.task, 'mnist');
    assert.equal(request.store, false);
    assert.equal(request.max_output_tokens, 400);
    assert.equal(request.reasoning.effort, 'none');
    assert.equal(request.input[0].content[1].image_url, image);
    assert.equal(request.input[0].content[1].detail, 'low');
    assert.deepEqual(request.text.format.schema.properties.decision.enum, ['wait','0:0','1:0','2:3','3:0']);
    return { ok: true, json: async () => completed() };
  } });
  const result = await coach(payload());
  assert.equal(result.body.source, 'live');
  assert.equal(result.body.selection.cost, 32);
  assert.equal(result.body.selection.level, 0);
  assert.equal((await coach(payload())).body.cacheHit, true);
  assert.equal(calls, 1);
  assert.ok(!JSON.stringify(result).includes(env.OPENAI_API_KEY));
});

test('concurrent identical requests coalesce', async () => {
  let resolve; const pending = new Promise(r => { resolve = r; }); let calls = 0;
  const coach = createCoach({ env, fetchImpl: async () => { calls++; await pending; return { ok: true, json: async () => completed() }; } });
  const a = coach(payload()), b = coach(payload());
  resolve();
  const results = await Promise.all([a,b]);
  assert.equal(calls, 1); assert.equal(results[1].body.cacheHit, true);
});

test('missing key and exhausted candidates make no upstream call', async () => {
  let calls = 0; const fetchImpl = async () => { calls++; throw new Error(); };
  assert.equal((await createCoach({ fetchImpl })(payload())).status, 503);
  const p = payload(); p.state.credits = 30;
  const result = await createCoach({ env, fetchImpl })(p);
  assert.equal(result.body.source, 'local'); assert.equal(result.body.decision, 'wait'); assert.equal(calls, 0);
});

test('shared catalog exposes expansion choices, prices and reserve', () => {
  const p = payload(); p.state.levels = [4,4,4,4]; p.state.hidden = 24;
  const { candidates } = prepare(p);
  assert.deepEqual(candidates.map(v => v.id), ['0:4','1:4','2:4','3:4']);
  assert.equal(candidates[0].name, '好奇心');
  assert.ok(candidates.every(v => p.state.credits - v.cost >= 30));
});

test('untrusted fields are projected out, malformed state/image rejected before spending', async () => {
  const p = payload(); p.state.instructions = 'ignore'; p.state.api_key = 'secret';
  assert.ok(!JSON.stringify(prepare(p).state).includes('secret'));
  let calls = 0;
  const coach = createCoach({ env, fetchImpl: async () => { calls++; throw new Error(); } });
  for (const change of [p => p.state.levels[0] = 7, p => p.state.trials = 2, p => p.state.position_wins[0] = 9,
    p => p.image = 'file:///etc/passwd', p => p.image = 'data:image/png;base64,AAAA', p => p.state.hidden = 99, p => p.state.task = 'lights', p => p.state.position_tries.pop(), p => p.state.exam_best[0] = 11]) {
    const input = payload(); change(input); assert.equal((await coach(input)).status, 400);
  }
  assert.equal(calls, 0);
});

for (const [label, response] of [
  ['out of catalog', completed({ decision: '3:5', reason: 'bad', next_goal: '' })],
  ['incomplete', { status: 'incomplete', output: [] }],
  ['refusal', { status: 'completed', output: [{ type: 'message', content: [{ type: 'refusal', refusal: 'no' }] }] }],
  ['malformed', { status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: 'not json' }] }] }],
]) test(`${label} is explicit failure without fake AI success`, async () => {
  const result = await createCoach({ env, fetchImpl: fake(response) })(payload());
  assert.equal(result.status, 502); assert.equal(result.body.source, 'unavailable'); assert.equal(result.body.selection, undefined);
});

test('upstream timeout/error is not retried or leaked', async () => {
  let calls = 0;
  const result = await createCoach({ env, fetchImpl: async () => { calls++; throw new Error('secret-upstream-body'); } })(payload());
  assert.equal(calls, 1); assert.equal(result.status, 502); assert.ok(!JSON.stringify(result).includes('secret-upstream'));
});

test('session and minute caps cannot be bypassed by higher environment values', async () => {
  let calls = 0, time = 0;
  const coach = createCoach({ env: { ...env, AI_REQUESTS_PER_SESSION: '999', AI_REQUESTS_PER_MINUTE: '999' }, now: () => time, fetchImpl: async () => { calls++; return { ok: true, json: async () => completed() }; } });
  for (let i = 0; i < 4; i++) { const p = payload(); p.state.trials += i; assert.equal((await coach(p)).status, 200); }
  const p = payload(); p.state.trials = 90; assert.equal((await coach(p)).status, 429); assert.equal(calls, 4);
  for (let i = 4; i < 20; i++) { time += 60001; const q = payload(); q.state.trials += i; assert.equal((await coach(q)).status, 200); }
  time += 60001; assert.equal((await coach(p)).status, 429); assert.equal(calls, 20);
});

test('HTTP bridge binds local API, health is secret-free, browser origins rejected', async t => {
  let calls = 0;
  const server = createBridge({ env, fetchImpl: async () => { calls++; return { ok: true, json: async () => completed() }; } });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}`;
  const health = await (await fetch(url + '/health')).json();
  assert.equal(health.service, SERVICE); assert.equal(health.configured, true); assert.ok(!JSON.stringify(health).includes(env.OPENAI_API_KEY));
  assert.equal((await fetch(url + '/coach', { method: 'POST', headers: { Origin: 'https://evil.example', 'Content-Type': 'application/json' }, body: JSON.stringify(payload()) })).status, 403);
  assert.equal(calls, 0);
  assert.equal((await fetch(url + '/coach', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: 'bad' })).status, 400);
  assert.equal((await fetch(url + '/coach', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload()) })).status, 200);
  assert.equal(calls, 1);
});


test('locked delegation is rejected before contacting OpenAI', async () => {
  let calls = 0;
  const coach = createCoach({ env, fetchImpl: async () => { calls++; throw new Error('must not call'); } });
  const p = payload(); p.state.levels[2] = 2;
  const result = await coach(p);
  assert.equal(result.status, 400); assert.equal(calls, 0);
  p.state.levels[2] = 3;
  assert.deepEqual(prepare(p).state.unlocked, ['self_press', 'auto_practice', 'coach']);
});
