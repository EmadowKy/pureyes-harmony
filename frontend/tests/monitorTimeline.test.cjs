const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'pages/tabs/MonitorTab.ets'), 'utf8');
const utility = fs.readFileSync(path.join(root, 'utils/monitorTimeline.ets'), 'utf8').replace(/export /g, '');
function method(name) {
  const start = source.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert.ok(start >= 0, name);
  const tail = source.slice(start + 1);
  const end = tail.search(/^  (?:async )?\w+\(|^  @Builder/m);
  return source.slice(start, end < 0 ? undefined : start + 1 + end);
}
const names = ['formatDateTime', 'timestampFromText', 'formatEpochSeconds', 'timelineTickLabel',
  'clampTimelinePosition', 'buildTimelineRanges', 'isReplayableAt', 'updatePlaybackPosition',
  'loadTimeline', 'startHistoricalPlayback'];
const requests = [];
const context = vm.createContext({
  HttpUtil: { get: url => new Promise(resolve => requests.push({ url, resolve })) }
});
const code = `${utility}
class TimelineRange { constructor(start, end) { this.startEpoch = start; this.endEpoch = end; } }
class Harness {
  constructor() {
    this.selectedMonitorId = 1; this.playbackMode = 'history'; this.granularity = 'second';
    this.timelineRequestEpoch = 0; this.playbackRequestEpoch = 0; this.selectionEpoch = 0;
    this.playbackSegmentStartEpoch = 1700000000; this.playbackSegmentEndEpoch = 1700000600;
    this.timelineStartEpoch = 1699999900; this.timelineEndEpoch = 1700000500;
    this.playbackOffsetSeconds = 0; this.selectedTimeText = ''; this.jumpTimeText = '';
    this.timelineRanges = []; this.hasReplayAtSelectedTime = true;
    this.isTimelineDragging = false; this.awaitingPlaybackSeek = false;
    this.jumpTimeEditing = false; this.refreshingReplayWindow = false; this.toasts = [];
  }
  showToast(options) { this.toasts.push(options.message); }
  buildHttpUrl(url) { return url; }
  ${names.map(method).join('\n')}
}
globalThis.api = { Harness, timelineTick, replayClock };`;
vm.runInContext(ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context);
const { Harness, timelineTick, replayClock } = context.api;
(async () => {
  const p = new Harness();
  p.updatePlaybackPosition(31.7);
  assert.equal(p.selectedTimeText, p.formatEpochSeconds(1700000031));
  assert.equal(p.timelinePositionSeconds, 131);
  p.isTimelineDragging = true;
  p.updatePlaybackPosition(35);
  assert.equal(p.timelinePositionSeconds, 131, 'playback must not fight a drag');
  p.isTimelineDragging = false; p.jumpTimeEditing = true; p.jumpTimeText = 'editing';
  p.updatePlaybackPosition(36);
  assert.equal(p.jumpTimeText, 'editing', 'typing a time must not be overwritten');
  p.awaitingPlaybackSeek = true; p.playbackOffsetSeconds = 90;
  p.updatePlaybackPosition(0);
  assert.equal(p.playbackOffsetSeconds, 90, 'initial zero must not cancel the requested seek');
  p.updatePlaybackPosition(90);
  assert.equal(p.awaitingPlaybackSeek, false);
  assert.equal(p.selectedTimeText, p.formatEpochSeconds(1700000090));
  assert.equal(replayClock(0, 2, 10), 0);
  assert.equal(replayClock(1700000000, NaN, 1700000600), 0);
  assert.equal(replayClock(1700000000, 999, 1700000600), 1700000600);
  assert.match(timelineTick(1700000000, 'second'), /^\d{2}:\d{2}:\d{2}$/);
  assert.match(timelineTick(1700000000, 'hour'), /^\d{2}:\d{2}$/);
  assert.match(timelineTick(1700000000, 'day'), /^\d{4}-\d{2}-\d{2}$/);
  assert.equal(timelineTick(0, 'day'), '');
  const missing = new Harness();
  const noRecording = missing.startHistoricalPlayback('2026-10-24 10:00:00');
  requests.shift().resolve({ code: 4044, message: 'recording not found for selected time' });
  await noRecording;
  assert.equal(missing.timelineErrorText, '');
  assert.equal(missing.hasReplayAtSelectedTime, false);
  assert.equal(missing.toasts.length, 0);
  const unauthorized = missing.startHistoricalPlayback('2026-10-24 10:00:00');
  requests.shift().resolve({ code: 401, message: '请重新登录' });
  await unauthorized;
  assert.equal(missing.timelineErrorText, '请重新登录');
  const stale = new Harness();
  const pending = stale.startHistoricalPlayback('2026-10-24 10:00:00');
  stale.playbackMode = 'live'; stale.playbackRequestEpoch++; stale.selectedMonitorUrl = 'live';
  requests.shift().resolve({ code: 0, data: JSON.stringify({ playback_url: 'old', seek_offset_seconds: 30,
    segment_end_time: '2026-10-24T10:01:00' }) });
  await pending;
  assert.equal(stale.selectedMonitorUrl, 'live', 'late replay response must not replace live');
  const race = new Harness(); race.hasReplayAtSelectedTime = false;
  const older = race.loadTimeline('2026-10-24 09:00:00');
  const newer = race.loadTimeline('2026-10-24 10:00:00');
  const first = requests.shift(), second = requests.shift();
  second.resolve({ code: 0, data: JSON.stringify({ selected_time: '2026-10-24T10:00:00',
    window_start: '2026-10-24T09:59:54', window_end: '2026-10-24T10:00:06', available_ranges: [] }) });
  await newer;
  first.resolve({ code: 0, data: JSON.stringify({ selected_time: '2026-10-24T09:00:00',
    window_start: '2026-10-24T08:59:54', window_end: '2026-10-24T09:00:06', available_ranges: [] }) });
  await older;
  assert.equal(race.selectedTimeText, '2026-10-24 10:00:00', 'latest selection wins and ISO T is not shown');
  console.log('Replay clock, seek/drag guards, compact ticks, empty recording and response races passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
