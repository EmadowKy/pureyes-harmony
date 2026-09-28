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
const processMethods = source.slice(source.indexOf('  isProcessExpanded('), source.indexOf('  @Builder ToolStep('));
const harness = `${classes}\nclass Harness {
  messages: Array<AgentTurnItem> = [];
  messageSource: AgentMessageDataSource = new AgentMessageDataSource();
  expandedProcessTurns: Array<string> = [];
  collapsedRunningProcessTurns: Array<string> = [];
  messageScroller = { isAtEnd: (): boolean => false };
  scheduleScrollToEnd(_delay: number): void {}
  ${methods}
  ${processMethods}
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
assert.equal(panel.messages[0].toolCalls[0].parameters[0].label, '画面 1');
assert.equal(panel.messages[0].toolCalls[0].parameters[0].value, '00:03');
assert.equal(panel.messages[0].toolCalls[0].parameters[0].videoId, 'a.mp4');
const fields = panel.mapToolParameters({ video_id: 'b.mp4', timestamp_sec: 0,
  track_id: 0, query_type: 'identity', query_text: '红色背包',
  queries: ['门口', '走廊'], frames: [{ video_id: 'a.mp4', timestamp_sec: 5.25 }] });
assert.deepEqual(Array.from(fields, field => field.label),
  ['视频', '时间点', '检索内容', '目标编号', '检索方式', '检索内容 1', '检索内容 2', '画面 1']);
assert.equal(fields[1].value, '00:00');
assert.equal(fields[3].value, '0');
assert.equal(fields[4].value, '查找同一目标');
assert.equal(fields[7].value, '00:05.25');
assert.equal(panel.mapToolParameters({ timestamp_sec: null }).length, 0);
assert.equal(panel.mapToolParameters({ timestamp_sec: -1 }).length, 0);
assert.equal(panel.mapToolParameters({ frames: [{ video_id: 'a.mp4' }] })[0].value, '未指定时间点');
panel.toolVideoLabel = (_turn, videoId) => videoId === 'a.mp4' ? '视频1 · 门口' : '视频2 · 走廊';
assert.equal(panel.toolParameterValue({}, fields[7]), '视频1 · 门口 · 00:05.25');
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
const trace = source.slice(source.indexOf('  @Builder ToolStep('), source.indexOf('  @Builder ConversationRail('));
assert.ok(trace.indexOf('if (this.isCallExpanded') < trace.indexOf('Text(call.summary'),
  'Tool results must only be shown in the expanded section');
assert.ok(!trace.includes('.backgroundColor('), 'Tool rows must not have separate colored cards');
assert.ok(!trace.includes('Text(call.parameters)'), 'Raw JSON must never be rendered');
progress.push({ stage: 'reasoning', data: { phase: 'commentary', text: '两处画面已核验，继续比较。' } });
panel.updateLiveTurn('active', progress);
assert.equal(changes, 4, 'Commentary without a new tool must refresh the timeline');
assert.equal(panel.messages[0].processEntries.at(-1).text, '两处画面已核验，继续比较。');
assert.deepEqual(Array.from(panel.messages[0].processEntries, entry => entry.kind), ['tool', 'tool', 'commentary']);
const turn = panel.messages[0];
turn.status = 'processing';
assert.equal(panel.isProcessExpanded(turn), true);
panel.toggleProcess(turn);
assert.equal(panel.isProcessExpanded(turn), false);
panel.toggleProcess(turn);
turn.status = 'completed';
assert.equal(panel.isProcessExpanded(turn), false, 'Completion must automatically collapse the process');
panel.toggleProcess(turn);
assert.equal(panel.isProcessExpanded(turn), true, 'A finished process can be reopened');
assert.equal(panel.isProcessExpanded({ id: 'follow-up', status: 'processing' }), true);
console.log('PASS: running steps, result matching, row invalidation, unchanged polls, stale tasks, collapsed layout');
