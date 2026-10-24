// Exercise the real event and lifecycle methods without rendering ArkUI in Node.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'investigationform/InvestigationCard.ets'), 'utf8');
const behavior = source.slice(source.indexOf('struct InvestigationCard'), source.indexOf('  build()'))
  .replace('struct InvestigationCard', 'class Card')
  .replace(/@(?:LocalStorageProp|Watch)\('[^']*'\)\s*/g, '').replace(/@State\s*/g, '') + '}';
const provider = fs.readFileSync(path.join(root, 'investigationform/InvestigationFormAbility.ets'), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace('export default ', '');
const events = [], animations = [], finishes = [], requests = [], routes = [];
let reduced = false, unsupported = false;
const sandbox = vm.createContext({ console, Curve: { Friction: 1 }, $r: value => value,
  postCardAction: (_card, action) => events.push(action),
  animateTo: (options, callback) => { animations.push(options); callback(); if (options.onFinish) finishes.push(options.onFinish); },
  FormExtensionAbility: class {},
  accessibility: { isAnimationReduceEnabledSync: () => reduced },
  InvestigationCard: { attach: async () => {}, cycle: async (_ctx, id, direction) => routes.push({ id, direction }) },
  formProvider: { getFormRect: async () => ({ left: 100, top: 100, width: 150, height: 150 }),
    requestOverflow: async (id, data) => { if (unsupported) throw Error('unsupported'); requests.push({ id, data }); } }
});
vm.runInContext(ts.transpileModule(behavior + '\n' + provider +
  '\nglobalThis.api = { Card, InvestigationFormAbility };',
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, sandbox);
(async () => {
  const card = new sandbox.api.Card();
  card.workspaceId = '1'; card.groupId = '3'; card.conversationId = 'case-a';
  card.open(); assert.equal(events.at(-1).action, 'router');
  assert.equal(events.at(-1).params.conversationId, 'case-a');
  card.command('next'); assert.equal(events.at(-1).params.command, 'next');
  card.aboutToAppear(); card.reduceMotion = false; card.interact();
  assert.equal(events.at(-1).params.command, 'interact'); assert.equal(card.petLift, -3);
  finishes.shift()(); assert.equal(card.petLift, 0);
  const count = animations.length;
  card.reduceMotion = true; card.interact(); assert.equal(animations.length, count, 'reduced motion leaves actions available');
  card.motionPreferenceChanged(); assert.equal(card.petLift, 0);
  card.reduceMotion = false; card.onTaskChanged(); card.aboutToDisappear();
  const before = animations.length; finishes.shift()(); assert.equal(animations.length, before, 'a destroyed card cannot start the return animation');
  const form = new sandbox.api.InvestigationFormAbility();
  await form.handleEvent('form-a', JSON.stringify({ params: { command: 'next' } }));
  assert.equal(routes[0].direction, 1);
  await form.handleEvent('form-a', JSON.stringify({ command: 'previous' })); assert.equal(routes[1].direction, -1);
  await form.interact('form-a'); assert.equal(requests.length, 1); assert.equal(requests[0].data.duration, 2200);
  reduced = true; await form.interact('form-a'); assert.equal(requests.length, 1);
  reduced = false; unsupported = true; await form.interact('form-a'); assert.equal(requests.length, 1, 'unsupported host is handled without breaking the card');
  console.log('Interactive card event routing, reduced motion, lifecycle and unsupported-host fallback passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
