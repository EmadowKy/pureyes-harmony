const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/pages/components/AgentConversationPanel.ets'), 'utf8');
const classes = source.slice(source.indexOf('class ConfigSelectItem'), source.indexOf('@Component'));
const methods = source.slice(source.indexOf('  evidenceScopeLabel('), source.indexOf('  activeConversationTitle('));
const context = vm.createContext({});
vm.runInContext(ts.transpileModule(`${classes}
class Harness {
  segments = [{id: 7, title: '门口', videoName: 'camera.mp4', durationText: '0s – 20s', status: 'completed'}];
  segmentLoadError = '';
  conversationReady = false;
  ${methods}
}
globalThis.panel = new Harness();`, {
  compilerOptions: {target: ts.ScriptTarget.ES2020}
}).outputText, context);
const panel = context.panel;
assert.equal(panel.referenceSegment(7).title, '门口');
assert.equal(panel.referenceSegment(99).id, 99);
assert.equal(panel.referenceSegment(99).status, 'unavailable');
panel.segmentLoadError = 'offline';
assert.match(panel.referenceSegment(99).videoName, /重试/);
assert.match(panel.evidenceScopeLabel(), /加载/);
panel.conversationReady = true;
assert.match(panel.evidenceScopeLabel(), /范围保持一致/);
assert.match(source, /@State referenceSegmentsExpanded: boolean = false/);
assert.match(source, /this\.evidenceSegmentIds = \[\.\.\.mapped\[0\]\.segmentIds\]/);
assert.match(source, /Math\.min\(180, this\.evidenceSegmentIds\.length \* 60\)/);
assert.match(source, /this\.onTimestampClick\(segmentId, '00:00'\)/);
assert.match(source, /Text\(`视频 \$\{index \+ 1\}`\)/);
console.log('Reference segment metadata and layout guards passed.');
