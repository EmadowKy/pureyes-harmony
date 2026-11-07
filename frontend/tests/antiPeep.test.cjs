const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
let supported = true, enabled = true, status = 0, permissionError, listener, pendingMask;
const values = new Map(), masks = [];
const api = {
  DlpAntiPeepStatus: { PASS: 0, HIDE: 1 },
  isDlpAntiPeepSwitchOn: async () => { if (permissionError) throw { code: permissionError }; return enabled; },
  on: (_event, cb) => { listener = cb; }, off: () => { listener = undefined; },
  getDlpAntiPeepInfo: () => status,
  requestAntiPeepOptions: async () => { enabled = true; },
  setAntiPeepMaskLayer: id => { masks.push(id); return pendingMask || Promise.resolve(); }
};
const sandbox = vm.createContext({ console, dlpAntiPeep: api, canIUse: () => supported,
  AppStorage: { setOrCreate: (key, value) => values.set(key, value) } });
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/antiPeep.ets'), 'utf8');
vm.runInContext(ts.transpileModule(source.replace(/^import .*;\r?\n/gm, '').replace(/export /g, ''),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText + '\nglobalThis.api = AntiPeep;', sandbox);
const protection = sandbox.api;
const win = { getWindowProperties: () => ({ id: 17 }) };
(async () => {
  protection.bind(win, {}); await protection.refresh();
  assert.equal(values.get('anti_peep_state'), 'active');
  listener(1); await Promise.resolve();
  assert.equal(masks.at(-1), 17, 'native mask covers the actual main window');
  assert.equal(values.get('anti_peep_state'), 'shielded');
  listener(0); assert.equal(values.get('anti_peep_state'), 'active');
  let rejectMask;
  pendingMask = new Promise((_ok, reject) => { rejectMask = reject; });
  listener(1); listener(0); rejectMask(Error('late')); await Promise.resolve();
  assert.equal(values.get('anti_peep_state'), 'active', 'late mask errors cannot override a newer PASS');
  pendingMask = undefined;
  protection.setForeground(false); assert.equal(listener, undefined);
  enabled = false; protection.setForeground(true); await protection.refresh();
  assert.equal(values.get('anti_peep_state'), 'disabled');
  await protection.enable(); assert.equal(values.get('anti_peep_state'), 'active');
  permissionError = 201; await protection.refresh();
  assert.equal(values.get('anti_peep_state'), 'permission'); assert.equal(listener, undefined);
  supported = false; await protection.refresh();
  assert.equal(values.get('anti_peep_state'), 'unsupported');
  protection.clear(); assert.equal(listener, undefined);
  console.log('system anti-peep lifecycle passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
