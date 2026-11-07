const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/utils/investigationLayout.ets'), 'utf8');
const context = vm.createContext({ exports: {} });
vm.runInContext(ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS
} }).outputText, context);
const { investigationLayout: layout, evidenceFocus: focus, evidenceMarks: marks,
  faceRecordsForClip: faceRecords } = context.exports;

// Window width, rather than the product/model name, determines the layout.
for (const width of [0, 360, 600, 839, NaN, Infinity]) assert.equal(layout(width, 700).mode, 'compact');
for (const width of [840, 960, 1179]) assert.equal(layout(width, 700).mode, 'split');
for (const width of [1180, 1280, 1920]) assert.equal(layout(width, 700).mode, 'expanded');
for (const width of [840, 960, 1180, 1280, 1600, 1920]) {
  const result = layout(width, 700);
  assert.ok(width - result.evidenceWidth >= 400, 'composer and model selector retain usable width');
  assert.ok(result.evidenceWidth - result.resourceWidth - 32 >= 320, 'video has its own minimum width');
  assert.ok(result.playerHeight <= 336, 'evidence list remains reachable below the player');
}
assert.ok(layout(1280, 350).playerHeight < layout(1280, 800).playerHeight,
  'short windows/keyboard reduce video height');

const clips = [{ id: 2, mediaUrl: '/api/video/test.mp4', duration: 30 },
  { id: 4, mediaUrl: '', duration: 20 }];
assert.equal(focus(clips, 99, 3, 0), undefined, 'out-of-scope evidence must never open another clip');
assert.equal(focus(clips, 4, 3, 0), undefined, 'unavailable media is not playable');
assert.equal(focus(clips, 2, NaN, 0), undefined);
assert.equal(focus(clips, 2, -1, 0), undefined);
assert.equal(focus(clips, 2, 90, 0).seconds, 30);
const first = focus(clips, 2, 0, 1);
const again = focus(clips, 2, 0, first.revision);
assert.equal(first.seconds, 0, 'seeking to video start is valid');
assert.ok(again.revision > first.revision, 'repeated same-time clicks still request a seek');
const raw = [
  { segmentId: 2, seconds: 1, label: 'first' }, { segmentId: 2, seconds: 1.0001, label: 'duplicate' },
  { segmentId: 99, seconds: 1 }, { segmentId: 2, seconds: -1 }, { segmentId: 2, seconds: NaN }
];
assert.equal(marks(raw, clips).length, 1, 'deduplicate while enforcing investigation scope');
assert.equal(marks(Array.from({ length: 500 }, (_, seconds) => ({ segmentId: 2, seconds })), clips).length, 200);
const records = faceRecords([
  { id: 3, segment_id: 2, start_time_offset: 5, crop_url: '/face.jpg' },
  { id: 4, segment_id: 99, start_time_offset: 7 },
  { id: 5, segment_id: 2, start_time_offset: -1 }
], 2);
assert.equal(records.length, 2, 'face navigation stays within the selected clip');
assert.equal(records[0].seconds, 5);
assert.equal(records[1].seconds, 0);
console.log('Adaptive layout, evidence scoping, repeated seeking and face filtering passed.');

const video = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/pages/components/RenewableVideo.ets'), 'utf8');
const seekMethod = video.slice(video.indexOf('  private seekToRequestedPosition()'),
  video.indexOf('  aboutToAppear()'));
let timerId = 0;
const pendingSeeks = new Map();
const flushSeeks = () => {
  const callbacks = Array.from(pendingSeeks.values());
  pendingSeeks.clear();
  callbacks.forEach(callback => callback());
};
const playbackContext = vm.createContext({ SeekMode: { Accurate: 3 },
  setTimeout: callback => { pendingSeeks.set(++timerId, callback); return timerId; },
  clearTimeout: id => pendingSeeks.delete(id)
});
vm.runInContext(ts.transpileModule(`class PlayerHarness {
  initialSeconds = 0; playbackSeconds = 12; seekRevision = 1;
  active = true; prepared = false; fullscreen = false;
  addressEpoch = 1; seekTimer = 0;
  seeks: number[] = []; starts = 0;
  controller = {setCurrentTime: (seconds: number) => this.seeks.push(seconds), start: () => this.starts++};
  ${seekMethod}
  seek() { this.seekToRequestedPosition(); }
}
globalThis.player = new PlayerHarness();`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText,
playbackContext);
const player = playbackContext.player;
player.seek();
assert.equal(player.playbackSeconds, 0);
flushSeeks();
assert.equal(player.seeks.length, 0, 'wait for prepared before seeking');
player.prepared = true;
player.seek();
assert.equal(player.seeks.length, 0, 'native commands wait until the prop/render update completes');
flushSeeks();
player.seek(); flushSeeks();
assert.deepEqual(Array.from(player.seeks), [0, 0], 'repeated zero-second requests reach the existing player');
assert.equal(player.starts, 2);
player.fullscreen = true; player.initialSeconds = 9; player.seek();
flushSeeks();
assert.equal(player.seeks.length, 2, 'hidden inline player cannot interrupt fullscreen');
player.fullscreen = false; player.active = false; player.seek();
flushSeeks();
assert.equal(player.seeks.length, 2, 'detached player ignores controller requests');
player.active = true; player.seek(); player.addressEpoch++;
flushSeeks();
assert.equal(player.seeks.length, 2, 'a pending seek cannot reach a different source');
player.initialSeconds = 7; player.seek();
player.initialSeconds = 24; player.seek();
flushSeeks();
assert.deepEqual(Array.from(player.seeks), [0, 0, 24], 'rapid clicks apply only the newest requested position');
console.log('Inline player preparation, repeated seeking, fullscreen and teardown guards passed.');

const restoreInlineMethod = video.slice(video.indexOf('  private restoreInlinePlayback()'),
  video.indexOf('  @Builder fullscreenPlayer()'));
const fullscreenContext = vm.createContext({});
vm.runInContext(ts.transpileModule(`class FullscreenReturnHarness {
  active = true; prepared = true; fullscreen = false; fullscreenOpen = true;
  playbackSeconds = 8; fullscreenSeconds = 23; fullscreenPlaying = false;
  positions: number[] = []; seeks: boolean[] = []; resumeOnPrepare: boolean | undefined;
  onPosition(seconds: number) { this.positions.push(seconds); }
  scheduleSeek(resume: boolean) { this.seeks.push(resume); }
  ${restoreInlineMethod}
  restore() { this.restoreInlinePlayback(); }
}
globalThis.player = new FullscreenReturnHarness();`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, fullscreenContext);
const fullscreenReturn = fullscreenContext.player;
fullscreenReturn.restore();
fullscreenReturn.restore();
assert.deepEqual(Array.from(fullscreenReturn.positions), [23], 'modal dismissal restores the last fullscreen position once');
assert.deepEqual(Array.from(fullscreenReturn.seeks), [false], 'returning from a paused fullscreen keeps playback paused');
fullscreenReturn.fullscreenOpen = true;
fullscreenReturn.prepared = false;
fullscreenReturn.fullscreenPlaying = true;
fullscreenReturn.restore();
assert.equal(fullscreenReturn.resumeOnPrepare, true, 'the fullscreen play state survives a pending source reload');

async function checkMediaRaces() {
  const requests = [];
  const mediaContext = vm.createContext({
    renewMediaUrl: source => new Promise((resolve, reject) => requests.push({ source, resolve, reject })),
    clearInterval: () => {}, clearTimeout: () => {}
  });
  const lifecycle = video.slice(video.indexOf('  private onSourceChanged()'), video.indexOf('  @Builder fullscreenPlayer()'));
  vm.runInContext(ts.transpileModule(`class MediaHarness {
    source = 'first'; initialSeconds = 0; active = true; addressEpoch = 0; refreshing = false;
    prepared = false; retryCount = 0; playbackSeconds = 0; playbackUrl = ''; errorText = '';
    fullscreen = false; seekRevision = 0; refreshTimer = 0;
    controller = {setCurrentTime: () => {}, start: () => {}};
    ${lifecycle}
  }
  globalThis.media = new MediaHarness();`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText,
  mediaContext);
  const media = mediaContext.media;
  const oldRequest = media.refreshAddress();
  media.source = 'second'; media.initialSeconds = 9; media.onSourceChanged();
  assert.deepEqual(requests.map(r => r.source), ['first', 'second']);
  requests[0].resolve('stale-address'); await oldRequest;
  assert.equal(media.playbackUrl, '', 'old video response cannot replace the selected video');
  assert.equal(media.refreshing, true, 'old response cannot clear the newer pending request');
  requests[1].resolve('current-address'); await Promise.resolve(); await Promise.resolve();
  assert.equal(media.playbackUrl, 'current-address');
  assert.equal(media.playbackSeconds, 9);
  media.source = 'third'; media.onSourceChanged();
  media.aboutToDisappear(); requests[2].reject(new Error('late error'));
  await Promise.resolve(); await Promise.resolve();
  assert.equal(media.errorText, '', 'late media failure must not update a detached player');
  console.log('Video switching and late media response guards passed.');
}
checkMediaRaces().catch(error => { console.error(error); process.exitCode = 1; });
