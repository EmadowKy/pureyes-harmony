// Run with Node and the DevEco bundled TypeScript module path.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets/utils');
const compile = file => ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export /g, ''),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
let now = 100000, current, deferred, lastCard;
const notifications = [], cancellations = [];
let starts = 0, stops = 0;
const values = new Map([['access_token', 'test-token']]);
const prefs = new Map();
const context = vm.createContext({
  Date: class extends Date { static now() { return now; } },
  setInterval: () => 1, clearInterval() {},
  AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
  HttpUtil: { get: async () => deferred ? deferred : { code: 0, data: JSON.stringify(current) } },
  notificationManager: { SlotType: { SERVICE_INFORMATION: 1, OTHER_TYPES: 0 },
    isNotificationEnabled: async () => true, requestEnableNotification: async () => {},
    publish: async request => notifications.push(request), cancel: async id => cancellations.push(id) },
  wantAgent: { OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 },
    getWantAgent: async value => value },
  backgroundTaskManager: { BackgroundMode: { DATA_TRANSFER: 1 }, on() {},
    startBackgroundRunning: async () => { starts++; }, stopBackgroundRunning: async () => { stops++; } },
  preferences: { removePreferencesFromCache: async () => {}, getPreferences: async (_context, { name }) => {
    if (!prefs.has(name)) prefs.set(name, new Map());
    const file = prefs.get(name);
    return { get: async (key, fallback) => file.get(key) ?? fallback,
      put: async (key, value) => file.set(key, value), delete: async key => file.delete(key), flush: async () => {} };
  } },
  formBindingData: { createFormBindingData: value => value },
  formProvider: { updateForm: async (_id, binding) => { lastCard = binding; } }
});
vm.runInContext(`${compile('investigationTaskState.ets')}\n${compile('investigationCard.ets')}\n${compile('investigationTasks.ets')}
globalThis.api = { InvestigationTaskCenter, InvestigationCard, parseInvestigationDashboard, taskPool, taskDuration };`, context);
const { InvestigationTaskCenter: center, InvestigationCard: card, parseInvestigationDashboard: parse,
  taskPool: pool, taskDuration: duration } = context.api;
const task = (id, status = 'processing') => ({ task_id: id, conversation_id: `conversation-${id}`,
  workspace_id: 1, group_id: 4, title: `Title ${id}`, status, stage: '核验画面', steps: 2, elapsed_seconds: 45 });
const dashboard = tasks => ({ tasks, active_count: tasks.filter(t => t.status === 'processing').length,
  completed_count: tasks.filter(t => t.status === 'completed').length, conversation_count: tasks.length });
const flush = () => new Promise(resolve => setImmediate(resolve));
async function refresh(tasks) { now += 5000; current = dashboard(tasks); await center.refresh(); }
(async () => {
  assert.equal(duration(123.9), '02:03');
  assert.equal(duration(-1), '00:00');
  assert.equal(pool(parse(dashboard([task('a'), task('b', 'completed')]))).length, 1);
  assert.equal(pool(parse({})).length, 0);
  await card.attach({}, 'form-one');
  await card.attach({}, 'form-two');
  await card.publishDashboard({}, parse(dashboard([task('a'), task('b')])));
  await card.cycle({}, 'form-one', 1);
  assert.equal(lastCard.conversationId, 'conversation-b');
  assert.equal(lastCard.groupId, '4', 'widget carries the authorized task group');
  await card.refresh({}, 'form-two');
  assert.equal(lastCard.conversationId, 'conversation-a', 'each form has its own task selection');
  await card.cycle({}, 'form-one', 1);
  assert.equal(lastCard.conversationId, 'conversation-a', 'cycling wraps');
  await card.clear({});
  assert.equal(JSON.parse(prefs.get('investigation_card_registry').get('form_ids')).length, 2,
    'dashboard clearing cannot erase the form registry');
  current = dashboard([task('a'), task('b')]);
  center.start({});
  await flush(); await flush();
  assert.equal(notifications.length, 2);
  assert.equal(starts, 1);
  await refresh([task('a'), task('b')]);
  assert.equal(notifications.length, 2, 'progress throttled');
  await refresh([task('a', 'completed'), task('b')]);
  assert.equal(notifications.length, 3, 'completion immediately delivered');
  await refresh([task('a', 'completed'), task('b')]);
  assert.equal(notifications.filter(n => n.content.normal.title.includes('已完成')).length, 1);
  await refresh([task('a', 'completed'), task('b', 'completed')]);
  assert.equal(stops, 1, 'background task stops when all investigations finish');
  await refresh([task('b', 'completed')]);
  assert.ok(cancellations.includes(notifications[0].id), 'deleted task notification removed');
  now += 5000;
  current = dashboard([task('fast', 'completed')]);
  await center.submitted('fast', 'conversation-fast', 1);
  assert.ok(notifications.some(n => n.wantAgent.wants[0].parameters.conversationId === 'conversation-fast'
    && n.content.normal.title.includes('已完成')), 'fast tasks still notify completion');
  let resolve;
  deferred = new Promise(done => { resolve = done; });
  now += 5000;
  const pending = center.refresh();
  await flush();
  values.set('access_token', '');
  await center.clear({});
  const count = notifications.length;
  resolve({ code: 0, data: JSON.stringify(dashboard([task('stale')])) });
  await pending;
  assert.equal(notifications.length, count, 'late response after logout cannot notify');
  assert.equal((await card.dashboard({})).tasks.length, 0, 'logout clears card');
  console.log('PASS: task selection, per-widget cycling, notification throttling/dedup, fast tasks, logout races');
})().catch(error => { console.error(error); process.exitCode = 1; });
