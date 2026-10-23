// node frontend/tests/investigationFloat.test.cjs <DevEco TypeScript module path>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets/utils');
const compile = name => ts.transpileModule(fs.readFileSync(path.join(root, name), 'utf8')
  .replace(/^import[\s\S]*?from\s+['"][^'"]+['"];\r?\n/gm, '').replace(/export /g, ''),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
let now = 100000, api26 = true, grant = true, stateCallback, ballCallback, stopCount = 0, createCount = 0;
let restores = [], ballUpdates = [], authCalls = 0, settingsCalls = 0, permissionPending;
let startError, asyncStop = false, nativeStopped = true, nativeBallStopped = true, unbindCount = 0;
let systemGrant = true;
const host = { applicationInfo: { accessTokenId: 123 } };
const limits = { minSize: { width: 400, height: 300 }, maxSize: { width: 900, height: 800 },
  ratioLimits: [{ minRatio: 0.8, maxRatio: 1.5 }] };
const values = new Map([['access_token', 'session']]);
const storageValues = new Map();
let nextTimer = 1;
const timers = new Map();
const controller = {
  onStateChange(callback) { stateCallback = callback; },
  offStateChange() { stateCallback = undefined; },
  setUIContext: async (page) => assert.equal(page, 'pages/InvestigationFloatWindow'),
  setWindowSize: async size => {
    assert.ok(size.width >= 400 && size.width <= 900 && size.height >= 300 && size.height <= 800);
    assert.ok(size.width / size.height >= 0.8 && size.width / size.height <= 1.5);
  },
  start: async () => {
    if (startError) throw startError;
    nativeStopped = false; nativeBallStopped = false;
    ballCallback?.(1); stateCallback?.({ state: 1 });
  },
  stop: async () => {
    stopCount++;
    const complete = () => { nativeStopped = true; stateCallback?.({ state: 3, stopReason: 'APP_STOP' }); };
    if (asyncStop) setImmediate(complete); else complete();
  },
  restoreMainWindow: async params => restores.push(params)
};
const context = vm.createContext({
  console, Date: class extends Date { static now() { return now; } },
  setInterval: callback => { const id = nextTimer++; timers.set(id, callback); return id; },
  clearInterval: id => timers.delete(id), setTimeout, clearTimeout,
  canIUse: () => api26, deviceInfo: { apiAvailable: () => api26 },
  window: { getLastWindow: async () => ({ getUIContext: () => ({ vp2px: value => value * 2 }) }) },
  AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
  LocalStorage: class {
    constructor(initial = {}) { Object.entries(initial).forEach(([key, value]) => storageValues.set(key, value)); }
    setOrCreate(key, value) { storageValues.set(key, value); }
  },
  abilityAccessCtrl: { GrantStatus: { PERMISSION_GRANTED: 0 }, createAtManager: () => ({
    checkAccessTokenSync: (token, permission) => {
      assert.equal(token, 123); assert.equal(permission, 'ohos.permission.USE_FLOAT_BALL');
      return systemGrant ? 0 : -1;
    },
    requestPermissionsFromUser: async () => {
      authCalls++; if (permissionPending) return permissionPending;
      return { authResults: [grant ? 0 : -1] };
    },
    requestPermissionOnSetting: async () => { settingsCalls++; return [grant ? 0 : -1]; }
  }) },
  floatingBall: { isFloatingBallEnabled: () => true, FloatingBallTemplate: { NORMAL: 2 }, FloatingBallState: { STARTED: 1, STOPPED: 2 },
    create: async () => ({
      on: (_type, callback) => { ballCallback = callback; }, off: () => { ballCallback = undefined; },
      updateFloatingBall: async params => ballUpdates.push(params),
      stopFloatingBall: async () => {
        const complete = () => { nativeBallStopped = true; ballCallback?.(2); };
        if (asyncStop) setImmediate(complete); else complete();
      }
    }) },
  floatView: {
    isFloatViewEnabled: () => true, FloatViewTemplateType: { ROUNDED_RECTANGLE: 0 },
    FloatViewState: { STARTED: 1, HIDDEN: 2, STOPPED: 3, IN_SIDEBAR: 4, IN_FLOATING_BALL: 5, ERROR: 6 },
    create: async () => { createCount++; return controller; }, bind: async () => {},
    unbind: async () => { assert.ok(nativeStopped && nativeBallStopped, 'unbind waits for both STOPPED events'); unbindCount++; },
    getFloatViewLimits: () => limits
  }
});
vm.runInContext(`${compile('investigationTaskState.ets')}\n${compile('investigationFloatState.ets')}\n${compile('investigationFloat.ets')}
globalThis.api = { InvestigationFloat, parseInvestigationDashboard, floatTaskPool, selectFloatTask,
  nextFloatTask, floatSnapshot, floatStatusLabel, floatErrorHint, floatWindowSize };`, context);
const { InvestigationFloat: float, parseInvestigationDashboard: parse, floatTaskPool: pool,
  selectFloatTask: select, nextFloatTask: next, floatSnapshot: snapshot, floatErrorHint: errorHint } = context.api;
const task = (id, status = 'processing') => ({ task_id: id, conversation_id: `conv-${id}`, workspace_id: 1,
  group_id: 4, title: 'PRIVATE TITLE', status, stage: '正在核验画面', steps: 7, elapsed_seconds: 45 });
const dashboard = tasks => parse({ tasks });
const flush = () => new Promise(resolve => setImmediate(resolve));
async function settle() { await flush(); await flush(); }
(async () => {
  const data = dashboard([task('done', 'completed'), task('a'), task('b'), task('a'), { ...task('bad'), group_id: 0 }]);
  assert.equal(pool(data).length, 3, 'ignore invalid targets and duplicates');
  assert.equal(select(data, ''), 'a', 'running task takes precedence');
  assert.equal(select(data, 'a', 'conv-b', 1), 'b', 'opening from a conversation selects its own task');
  assert.equal(select(data, 'a', 'conv-b', 999), 'a', 'workspace boundary enforced');
  assert.equal(next(data, 'a', -1), 'done', 'previous wraps');
  assert.equal(next(dashboard([]), '', 1), '');
  assert.equal(snapshot(data, 'a', now, now + 4000, false).duration, '00:49');
  assert.equal(snapshot(data, 'done', now, now + 4000, false).duration, '00:45', 'completed time never increases');
  assert.equal(snapshot(data, 'a', now, now + 25000, false).stale, true, 'missed polling tick marks stale');
  assert.equal(snapshot(data, 'a', now, now + 25000, false).duration, '01:05', 'stale clock freezes rather than rewinds');
  assert.equal(snapshot(data, 'a', now, now + 15000, true, now + 4000).duration, '00:49', 'failure freezes at its first observation');
  assert.equal(snapshot(data, 'done', now, now + 25000, false).stale, false, 'terminal tasks do not need background polling');
  assert.equal(snapshot(data, 'a', now, now, true).stale, true);
  assert.equal(snapshot(dashboard([]), '', now, now, false).stage, '暂无调查');
  assert.equal(snapshot(dashboard([]), '', 0, now, false).stage, '正在同步');
  assert.ok(!JSON.stringify(snapshot(data, 'a', now, now, false)).includes('PRIVATE TITLE'), 'no title leakage');
  assert.ok(errorHint(201).includes('签名'));
  assert.ok(errorHint(1300034).includes('画中画'));
  const size = context.api.floatWindowSize(limits, 2);
  assert.equal(size.width, 560); assert.equal(size.height, 440, 'density-aware readable initial size');
  for (const density of [0, 1, 1.5, 3, 8, NaN]) {
    const sized = context.api.floatWindowSize(limits, density);
    assert.ok(sized.width >= 400 && sized.width <= 900 && sized.height >= 300 && sized.height <= 800);
    assert.ok(sized.width / sized.height >= 0.8 && sized.width / sized.height <= 1.5);
  }
  float.update(data);
  api26 = false;
  await float.open(host, 'conv-a', 1);
  assert.equal(createCount, 0, 'older systems never create a native window');
  api26 = true; systemGrant = false;
  await float.open(host, 'conv-a', 1);
  assert.equal(authCalls, 0, 'missing system entitlement must not ask the user for an unusable runtime permission');
  assert.ok(values.get('investigation_float_hint').includes('更新签名'));
  systemGrant = true; grant = false;
  await float.open(host, 'conv-a', 1);
  assert.equal(createCount, 0, 'denied permission cannot create a window');
  grant = true;
  await float.open(host, 'conv-b', 1); await settle();
  assert.equal(settingsCalls, 1, 'only a second explicit click opens permission settings');
  assert.equal(values.get('investigation_float_active'), true);
  assert.equal(storageValues.get('floatTask').taskId, 'b');
  const count = createCount;
  await float.open(host, 'conv-b', 1);
  assert.equal(createCount, count, 'duplicate click does not create another window');
  float.cycle(1); await settle();
  assert.equal(storageValues.get('floatTask').taskId, 'done');
  await float.returnToInvestigation(); await settle();
  assert.equal(restores[0].conversationId, 'conv-done');
  assert.equal(restores[0].groupId, '4');
  assert.equal(values.get('investigation_float_active'), false);
  assert.equal(timers.size, 0, 'return releases the local display clock');
  assert.ok(unbindCount > 0);
  await float.open(host, 'conv-arriving', 1); await settle();
  float.update(dashboard([task('a'), task('arriving')])); await settle();
  assert.equal(storageValues.get('floatTask').taskId, 'arriving', 'a pending initial refresh selects the requested conversation when it arrives');
  await float.close();
  float.update(data);
  startError = { code: 1300034 };
  await float.open(host, 'conv-a', 1);
  assert.ok(values.get('investigation_float_hint').includes('画中画'), 'native failure retains an actionable error');
  assert.equal(values.get('investigation_float_active'), false);
  startError = undefined;
  await float.open(host, 'conv-a', 1); await settle();
  stateCallback({ state: 5 }); await settle();
  assert.equal(values.get('investigation_float_active'), true, 'minimize-to-ball does not stop the task display');
  const userClose = stateCallback;
  userClose({ state: 3, stopReason: 'TITLE_BAR_STOP_CLICK' }); await settle();
  float.update(data); await settle();
  assert.equal(values.get('investigation_float_active'), false, 'polling never reopens a closed window');
  await float.open(host, 'conv-a', 1); await settle();
  float.update(dashboard([task('a', 'completed'), task('b')])); await settle();
  assert.equal(storageValues.get('floatTask').taskId, 'a', 'completion keeps the selected task visible');
  assert.ok(ballUpdates.some(item => item.title === '调查已完成'), 'completion updates ball immediately');
  float.syncFailed();
  assert.equal(storageValues.get('floatTask').stale, true);
  float.backgroundCancelled();
  const followup = { ...task('a-next'), conversation_id: 'conv-a' };
  float.update(dashboard([task('b'), followup])); await settle();
  assert.equal(storageValues.get('floatTask').taskId, 'a-next', 'follow-up stays with the selected conversation');
  assert.equal(storageValues.get('floatTask').hint, '', 'fresh data clears the background interruption hint');
  now += 4000;
  for (const tick of timers.values()) tick();
  float.syncFailed();
  assert.equal(storageValues.get('floatTask').duration, '00:49');
  now += 10000;
  float.syncFailed();
  assert.equal(storageValues.get('floatTask').duration, '00:49', 'repeated failures cannot restart the frozen clock');
  float.update(dashboard([task('b')])); await settle();
  assert.equal(storageValues.get('floatTask').taskId, 'b', 'deleted target is removed');
  asyncStop = true;
  await float.clear(); await settle();
  asyncStop = false;
  assert.equal(storageValues.get('floatTask').taskId, '');
  assert.equal(timers.size, 0);
  let resolvePermission;
  permissionPending = new Promise(resolve => { resolvePermission = resolve; });
  const pending = float.open(host, 'conv-a', 1); await settle();
  values.set('access_token', '');
  const clearing = float.clear();
  resolvePermission({ authResults: [0] });
  await pending; await clearing; await settle();
  assert.equal(values.get('investigation_float_active'), false, 'late permission result cannot reopen after logout');
  assert.equal(values.get('investigation_float_busy'), false);
  assert.equal(storageValues.get('floatTask').taskId, '');
  assert.ok(stopCount > 0 && authCalls > 0);
  console.log('PASS: float selection, privacy, permissions, task transitions, routing, close lifecycle, logout races');
})().catch(error => { console.error(error); process.exitCode = 1; });
