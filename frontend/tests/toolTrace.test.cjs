// Run with Node and a TypeScript module path (the DevEco SDK bundles one):
// node tests/toolTrace.test.cjs <path-to-typescript>
// Exercise the production polling parser without requiring an ArkUI runtime.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/pages/components/AgentConversationPanel.ets'), 'utf8');
const classes = source.slice(source.indexOf('class ConfigSelectItem'), source.indexOf('@Component'));
const methods = source.slice(source.indexOf('  mapToolCall('), source.indexOf('  toolVideoLabel('));
const harness = `${classes}\nclass Harness {
  messages: Array<AgentTurnItem> = [];
  messageSource: AgentMessageDataSource = new AgentMessageDataSource();
  ${methods}
}\nglobalThis.harness = new Harness();`;
const context = vm.createContext({});
vm.runInContext(ts.transpileModule(harness, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const panel = context.harness;
panel.messages = [{ id: 'active', traceRevision: 0, toolCalls: [] }];
let changes = 0;
panel.messageSource.registerDataChangeListener({ onDataChange: () => changes++ });
const action = (name) => ({ stage: 'reasoning', data: {
  phase: 'action', iteration: 1, tool_name: name,
  tool_params: { frames: [{ video_id: 'a.mp4', timestamp_sec: 3 }] }
}});
const observation = (name, summary) => ({ stage: 'reasoning', status: 'completed', data: {
  phase: 'observation', iteration: 1, tool_name: name, summary,
  result_status: 'completed', evidence: [{ segment_id: 1, timestamp_sec: 3 }]
}});
const progress = [action('read_frames')];
panel.updateLiveTurn('active', progress);
assert.equal(panel.messages[0].toolCalls.length, 1);
assert.equal(panel.messages[0].toolCalls[0].status, 'running');
assert.equal(panel.messages[0].traceRevision, 1);
assert.equal(changes, 1);
assert.match(panel.messages[0].toolCalls[0].parameters, /timestamp_sec/);
panel.updateLiveTurn('active', progress);
assert.equal(changes, 1, 'An unchanged polling tick must not rebuild the row');
progress.push(action('search_objects'), observation('read_frames', '已读画面'));
panel.updateLiveTurn('active', progress);
assert.equal(panel.messages[0].toolCalls[0].summary, '已读画面');
assert.equal(panel.messages[0].toolCalls[1].status, 'running');
progress.push(observation('search_objects', '已找到目标'));
panel.updateLiveTurn('active', progress);
assert.equal(panel.messages[0].toolCalls[1].summary, '已找到目标');
assert.equal(panel.messages[0].traceRevision, 3);
assert.equal(changes, 3);
panel.updateLiveTurn('another-task', progress);
assert.equal(changes, 3, 'A stale task must not alter the active row');
assert.match(source, /\$\{turn\.id\}-\$\{turn\.traceRevision\}/,
  'LazyForEach key must invalidate cached rows on tool progress');
const trace = source.slice(source.indexOf('  @Builder ToolTrace('), source.indexOf('  @Builder ConversationRail('));
assert.ok(trace.indexOf('if (this.isCallExpanded') < trace.indexOf('Text(call.summary'),
  'Tool results must only be shown in the expanded section');
assert.ok(!trace.includes('.backgroundColor('), 'Tool rows must not have separate colored cards');
console.log('PASS: running steps, result matching, row invalidation, unchanged polls, stale tasks, collapsed layout');
