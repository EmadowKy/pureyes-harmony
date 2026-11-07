const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/investigationHandoff.ets'), 'utf8');
const values = new Map([['access_token', 'local-only']]);
const states = [];
let authorize = async () => ({ authResults: [0] });
const sandbox = vm.createContext({ Date, console,
  AppStorage: { get: k => values.get(k), setOrCreate: (k, v) => values.set(k, v) },
  getBaseUrl: () => 'https://example.test/api',
  AbilityConstant: { ContinueState: { ACTIVE: 0, INACTIVE: 1 } },
  abilityAccessCtrl: { createAtManager: () => ({ requestPermissionsFromUser: () => authorize() }) }
});
vm.runInContext(ts.transpileModule(source.replace(/^import .*;\r?\n/gm, '').replace(/export /g, ''),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText +
  '\nglobalThis.api = { parseHandoff, InvestigationHandoff, InvestigationHandoffState };', sandbox);
const { parseHandoff: parse, InvestigationHandoff: handoff, InvestigationHandoffState: State } = sandbox.api;
const now = Date.now(), server = 'https://example.test/api';
const good = { version: 1, server, groupId: 3, workspaceId: 1, conversationId: 'case-1',
  segmentId: 13, seconds: 9, draft: '继续核验', createdAt: now };
const read = patch => parse(JSON.stringify({ ...good, ...patch }), server, now);
assert.equal(read({}).seconds, 9);
for (const patch of [{ version: 2 }, { server: 'http://other/api' }, { groupId: 0 },
  { workspaceId: 1.1 }, { conversationId: '../secret' }, { createdAt: now - 600001 },
  { createdAt: now + 60001 }, { createdAt: 'now' }]) assert.equal(read(patch), undefined);
assert.equal(parse('{broken', server, now), undefined);
assert.equal(parse(' '.repeat(16001), server, now), undefined);
assert.equal(read({ seconds: -10 }).seconds, 0);
assert.equal(read({ segmentId: -1 }).segmentId, 0);
assert.equal(read({ draft: 'x'.repeat(10000) }).draft.length, 4000);
assert.ok(!JSON.stringify(read({ access_token: 'secret', mediaUrl: 'signed-secret', api_key: 'secret' })).includes('secret'));
(async () => {
  handoff.bind({ setMissionContinueState: async state => states.push(state) });
  const state = Object.assign(new State(), good);
  handoff.update(state);
  assert.equal(handoff.snapshot(), '', 'an investigation must be opted in before it can migrate');
  assert.equal(states.length, 0);
  await handoff.enable();
  await handoff.pending;
  assert.equal(states.at(-1), 0);
  for (let i = 0; i < 20; i++) handoff.update(Object.assign(new State(), good, { seconds: i }));
  await handoff.pending;
  assert.equal(states.length, 1, 'playback updates must not repeatedly advertise a mission');
  assert.equal(JSON.parse(handoff.snapshot()).seconds, 19);
  values.delete('access_token');
  assert.equal(handoff.snapshot(), '');
  handoff.clear(); await handoff.pending;
  assert.equal(states.at(-1), 1);
  assert.equal(values.get('handoff_incoming'), '');
  values.set('access_token', 'local-only');
  handoff.update(state);
  let finishAuthorization;
  authorize = () => new Promise(resolve => { finishAuthorization = resolve; });
  const enabling = handoff.enable();
  handoff.update(Object.assign(new State(), good, { conversationId: 'case-2' }));
  finishAuthorization({ authResults: [0] });
  await enabling;
  assert.equal(handoff.snapshot(), '', 'late permission must not enable a different investigation');
  handoff.update(Object.assign(new State(), good, { server: 'https://wrong/api' }));
  assert.equal(handoff.snapshot(), '');
  console.log('investigation handoff contracts passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
