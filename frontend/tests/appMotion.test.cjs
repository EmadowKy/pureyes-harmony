// Run with Node and the TypeScript path bundled with DevEco Studio.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'utils/appMotion.ets'), 'utf8');
const storage = new Map();
let supported = false;
let reduce = false;
let listener;
let removed;
let subscriptions = 0;
let materialAccesses = 0;
const context = vm.createContext({
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  Curve: { Friction: 'friction' }, Color: { Transparent: 'transparent' },
  accessibility: {
    isAnimationReduceEnabledSync: () => reduce,
    onAnimationReduceStateChange: callback => { listener = callback; subscriptions++; },
    offAnimationReduceStateChange: callback => { removed = callback; }
  },
  deviceInfo: { apiAvailable: version => { assert.equal(version, '26.0.0'); return supported; } },
  uiMaterial: new Proxy({}, { get: (_target, key) => {
    materialAccesses++;
    assert.equal(supported, true, 'old runtimes must not access API 26 material symbols');
    return { Material: { empty: 'empty' }, ImmersiveStyle: { THIN: 'thin' },
      ImmersiveMaterial: class { constructor(options) { this.options = options; } } }[key];
  } })
});
const script = source.replace(/^import .*;\r?\n/gm, '').replace(/export (class|function) /g, '$1 ');
vm.runInContext(ts.transpileModule(`${script}\nglobalThis.api = { AppMotion, NativeMaterial, FloatingTabsStyle };`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const { AppMotion, NativeMaterial, FloatingTabsStyle } = context.api;
AppMotion.start();
AppMotion.start();
assert.equal(subscriptions, 1, 'ability restarts must not duplicate listeners');
assert.equal(AppMotion.duration(280), 280);
listener(true);
assert.equal(AppMotion.duration(280), 0);
assert.equal(AppMotion.options().duration, 0);
listener(false);
assert.equal(AppMotion.options(220).duration, 220);
AppMotion.stop();
assert.equal(removed, listener, 'unsubscribe must use the same callback');
assert.equal(NativeMaterial.available(), false);
assert.equal(NativeMaterial.none(), undefined);
new FloatingTabsStyle().applyNormalAttribute({});
assert.equal(materialAccesses, 0);
supported = true;
assert.equal(NativeMaterial.none(), 'empty');
let floating;
const tabs = { barFloatingStyle: style => { floating = style; } };
new FloatingTabsStyle().applyNormalAttribute(tabs);
assert.equal(floating.barSideMargin, 16);
assert.equal(floating.systemMaterial.options.style, 'thin');
new FloatingTabsStyle(true).applyNormalAttribute(tabs);
assert.equal(floating, undefined, 'nested pages must remove the floating tab bar');
const stage = fs.readFileSync(path.join(root, 'pages/components/MotionStage.ets'), 'utf8');
assert.match(stage, /aboutToDisappear\(\)[\s\S]*clearTimeout\(this\.frameTimer\)/);
assert.match(stage, /if \(!this\.visible \|\| this\.reduceMotion\)/);
const workspace = fs.readFileSync(path.join(root, 'pages/WorkspaceDetail.ets'), 'utf8');
assert.match(workspace, /if \(!this\.isNestedView\(\)\) \{\s*Tabs\(/);
assert.match(workspace, /item\.id === rec\.segment_id/);
assert.doesNotMatch(workspace, /s\.duration = rec\.end_time_offset \+ 5/);
const panel = fs.readFileSync(path.join(root, 'pages/components/AgentConversationPanel.ets'), 'utf8');
assert.match(panel, /\.rotate\(\{ angle: this\.isProcessExpanded\(turn\) \? 90 : 0 \}\)/);
assert.match(panel, /turn\.traceRevision > 0 \? TransitionEffect\.IDENTITY/);
console.log('Motion preferences, API 23 fallback, native tab material and navigation guards passed.');
