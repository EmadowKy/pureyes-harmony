const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const state = fs.readFileSync(path.join(root, 'utils/investigationFloatState.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
const card = fs.readFileSync(path.join(root, 'investigationform/InvestigationCard.ets'), 'utf8');
const presentation = card.slice(card.indexOf('  private pet()'), card.indexOf('  build()'));
const context = vm.createContext({ $r: value => value });
vm.runInContext(ts.transpileModule(`${state}
class Card { status = 'idle'; runningCount = '0'; ${presentation} }
globalThis.api = { floatMotionKey, InvestigationFloatSnapshot, Card };`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const { floatMotionKey, InvestigationFloatSnapshot, Card } = context.api;
const task = new InvestigationFloatSnapshot();
task.taskId = 'task-a'; task.status = 'processing'; task.stage = '核验画面';
const first = floatMotionKey(task);
task.duration = '00:21'; task.steps = 3;
assert.equal(floatMotionKey(task), first, 'clock updates must not replay entry motion');
task.taskId = 'task-b';
assert.notEqual(floatMotionKey(task), first);
task.taskId = 'task-a'; task.status = 'completed';
assert.notEqual(floatMotionKey(task), first);
const completed = floatMotionKey(task); task.stale = true;
assert.notEqual(floatMotionKey(task), completed);
const panel = new Card(); panel.status = 'stopped';
assert.equal(panel.statusLabel(), '调查已停止');
panel.status = 'completed'; panel.runningCount = '2';
assert.equal(panel.pet(), 'app.media.investigation_owl_done', 'selection and overall running count are distinct');
assert.equal(panel.statusAccent(), 'app.color.app_success');
assert.ok(!card.includes('setInterval'), 'a dynamic card must not start an idle animation loop');
console.log('Task motion keys and stopped/completed presentation passed.');
