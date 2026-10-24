// node frontend/tests/investigationSkill.test.cjs <DevEco TypeScript module path>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets/utils');
const compile = file => ts.transpileModule(fs.readFileSync(file, 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export default /g, '').replace(/export /g, ''),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
let response, afterFetch, calls, opened, failOpen, api26 = true;
const values = new Map();
const reports = [];
const context = { applicationInfo: { name: 'cn.edu.nuaa.pureyes' },
  async startAbility(want) { if (failOpen) throw Error('denied'); opened.push(want); } };
const sandbox = vm.createContext({ console,
  AppStorage: { get: key => values.get(key) },
  SecurityUtil: { initSecureState: async () => {} },
  getBaseUrl: () => values.get('server'),
  HttpUtil: { get: async route => { assert.equal(route, '/workspaces/agent/tasks'); calls++; afterFetch?.(); return response; } },
  deviceInfo: { apiAvailable: () => api26 },
  scriptManager: { completeArkTSScriptInApp: async (ctx, requestCode, result) => reports.push({ ctx, requestCode, result }) }
});
vm.runInContext(compile(path.join(root, 'investigationTaskState.ets')) + '\n' +
  compile(path.join(root, 'investigationSkill.ets')) + '\n' +
  compile(path.join(__dirname, '../entry/skills/pureyes-investigation/scripts/InvestigationSkill.ets')) +
  '\nglobalThis.api = { InvestigationSkill, PureyesInvestigationSkill };', sandbox);
const { InvestigationSkill: skill, PureyesInvestigationSkill: Adapter } = sandbox.api;
const task = (id, title = '店内藏物', extra = {}) => ({ task_id: id, conversation_id: id,
  workspace_id: 1, group_id: 3, title, status: 'processing', stage: '正在核验画面',
  steps: 4, elapsed_seconds: 80, question: 'must not be exposed', api_key: 'never return', ...extra });
function reset(tasks = [task('case-one')]) {
  values.clear(); values.set('access_token', 'local-session'); values.set('server', 'https://example.test/api');
  values.set('session_server_url', 'https://example.test/api');
  response = { code: 0, httpStatus: 200, data: JSON.stringify({ tasks, active_count: 1, completed_count: 2, conversation_count: 3 }) };
  afterFetch = undefined; calls = 0; opened = []; failOpen = false;
}
const execute = (action, args = []) => skill.execute(context, action, args);
const error = async (code, action = 'progress', args = []) => {
  const result = await execute(action, args); assert.equal(result.code, -1); assert.equal(result.result.errCode, code);
  assert.equal(opened.length, 0); return result;
};
(async () => {
  reset();
  let result = await execute('progress');
  assert.equal(result.result.data.activeCount, 1); assert.equal(result.result.data.tasks[0].elapsed, '01:20');
  assert.ok(!JSON.stringify(result).includes('must not be exposed'));
  assert.ok(!JSON.stringify(result).includes('never return'));
  assert.equal(opened.length, 0, 'status reads never open or submit a conversation');
  reset(); result = await execute('progress', ['店内']); assert.equal(result.result.data.task.conversationId, 'case-one');
  reset(); result = await execute('open', ['case-one']);
  assert.equal(result.result.data.opened, true); assert.equal(opened.length, 1);
  assert.equal(opened[0].parameters.groupId, '3'); assert.equal(opened[0].parameters.conversationId, 'case-one');
  assert.equal(opened[0].abilityName, 'EntryAbility');
  reset(); await execute('open'); assert.equal(opened.length, 1, 'unique task can open without a title');
  reset([task('a'), task('b')]); result = await error('ERR_AMBIGUOUS', 'open', ['店内']);
  assert.equal(result.result.data.candidates.length, 2);
  await error('ERR_AMBIGUOUS', 'open');
  reset([task('a', '案件'), task('b', '案件补充')]);
  result = await execute('open', ['案件']); assert.equal(result.result.data.task.conversationId, 'a', 'exact title wins over partial');
  reset(); await error('ERR_NOT_FOUND', 'open', ['missing']);
  reset([]); await error('ERR_NOT_FOUND', 'open');
  reset([]); result = await execute('progress'); assert.equal(result.result.data.tasks.length, 0);
  reset(); values.delete('access_token'); await error('ERR_LOGIN_REQUIRED'); assert.equal(calls, 0);
  reset(); values.set('session_server_url', 'https://old.test/api'); await error('ERR_LOGIN_REQUIRED'); assert.equal(calls, 0);
  reset(); response.httpStatus = 401; await error('ERR_LOGIN_REQUIRED');
  reset(); response.httpStatus = 403; await error('ERR_LOGIN_REQUIRED', 'open');
  reset(); response = { code: -1, httpStatus: 0, message: 'secret backend detail' }; result = await error('ERR_UNAVAILABLE');
  assert.ok(!JSON.stringify(result).includes('secret backend detail'));
  reset(); response.data = '{broken'; await error('ERR_UNAVAILABLE');
  reset(); response.data = '{}'; await error('ERR_UNAVAILABLE');
  reset(); afterFetch = () => values.delete('access_token'); await error('ERR_LOGIN_REQUIRED', 'open');
  reset(); afterFetch = () => values.set('server', 'https://new.test/api'); await error('ERR_LOGIN_REQUIRED', 'open');
  reset(); afterFetch = () => values.set('access_token', 'different-account'); await error('ERR_LOGIN_REQUIRED');
  reset(); await error('ERR_INVALID_PARAMS', 'delete'); assert.equal(calls, 0);
  reset(); await error('ERR_INVALID_PARAMS', 'progress', ['a', 'b']); assert.equal(calls, 0);
  reset(); await error('ERR_INVALID_PARAMS', 'progress', ['x'.repeat(161)]); assert.equal(calls, 0);
  reset([task('long-title', '名'.repeat(160))]);
  result = await execute('progress', ['名'.repeat(160)]); assert.equal(result.code, 0);
  reset(); await error('ERR_INVALID_PARAMS', 'open', ['bad\nname']); assert.equal(calls, 0);
  reset([task('a', 'hidden', { workspace_id: 0 }), task('../unsafe', 'hidden')]);
  await error('ERR_NOT_FOUND', 'open', ['hidden']);
  reset(); failOpen = true; await error('ERR_OPEN_FAILED', 'open');
  reset(); const adapter = new Adapter();
  await adapter.getInvestigationProgress({ context, requestCode: 'request-a' });
  await adapter.openInvestigation({ context, requestCode: 'request-b' }, 'case-one');
  assert.equal(reports.length, 2); assert.equal(reports[0].requestCode, 'request-a');
  assert.equal(reports[1].result.result.data.opened, true);
  reset(); await adapter.openInvestigation({ context, requestCode: 'request-c' }, 'missing');
  assert.equal(reports.length, 3); assert.equal(reports[2].result.result.errCode, 'ERR_NOT_FOUND');
  api26 = false; const previousCalls = calls;
  await adapter.getInvestigationProgress({ context, requestCode: 'api23' });
  assert.equal(calls, previousCalls); assert.equal(reports.length, 3, 'API 23 does not invoke API 26 result delivery');
  console.log('Investigation Skill: permissions, lookup, ambiguity, race handling and system result adapter passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
