const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/pages/tabs/MonitorTab.ets'), 'utf8');
function harness() {
  const methods = source.slice(source.indexOf('  markMediaPlaying(): void'),
    source.indexOf('  showToast(')).replace(/\): void/g, ')');
  const timers = new Map();
  let next = 1;
  const sandbox = {
    setTimeout(callback) { const id = next++; timers.set(id, callback); return id; },
    clearTimeout(id) { timers.delete(id); }
  };
  const Player = vm.runInNewContext(`(class {
    constructor() {
      this.mediaErrorTimer = 0; this.mediaErrorText = 'failed';
      this.timelineErrorText = 'timeline failed';
      this.selectedMonitorUrl = 'live-a'; this.selectedMonitorId = 1;
      this.retries = 0;
    }
    recoverMedia() { this.retries++; }
    ${methods}
  })`, sandbox);
  return { player: new Player(), timers };
}

test('successful playback clears media error and cancels transient recovery only', () => {
  const { player, timers } = harness();
  player.scheduleMediaRecovery();
  player.markMediaPlaying();
  assert.equal(player.mediaErrorText, '');
  assert.equal(player.timelineErrorText, 'timeline failed');
  assert.equal(timers.size, 0);
});
test('persistent errors schedule only one recovery', () => {
  const { player, timers } = harness();
  player.scheduleMediaRecovery(); player.scheduleMediaRecovery();
  assert.equal(timers.size, 1);
  [...timers.values()][0]();
  assert.equal(player.retries, 1);
});
test('late error from previous source does not retry current video', () => {
  const { player, timers } = harness();
  player.scheduleMediaRecovery();
  player.selectedMonitorUrl = 'history-b';
  [...timers.values()][0]();
  assert.equal(player.retries, 0);
});
