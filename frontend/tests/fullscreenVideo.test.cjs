const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/pages/components/FullscreenSegmentVideo.ets'), 'utf8');
const methods = source.slice(source.indexOf('  private resetView()'),
  source.indexOf('  private timeText(')).replace(/private /g, '').replace(/\): void/g, ')');
const Player = vm.runInNewContext(`(class { ${methods} })`);
test('default/reset shows the full frame without pan or magnification', () => {
  const p = new Player(); p.scaleValue = 5; p.offsetX = 100; p.offsetY = 60;
  p.resetView();
  assert.deepEqual([p.scaleValue, p.offsetX, p.offsetY], [1, 0, 0]);
  assert.match(source, /objectFit\(ImageFit.Contain\)/);
});
test('two-finger pan cannot move the enlarged frame completely off-screen', () => {
  const p = new Player();
  Object.assign(p, { widthValue: 800, heightValue: 400, scaleValue: 2, offsetX: 9999, offsetY: -9999 });
  p.constrainOffset();
  assert.deepEqual([p.offsetX, p.offsetY], [400, -200]);
  p.scaleValue = 1; p.constrainOffset();
  assert.equal(Math.abs(p.offsetX), 0); assert.equal(Math.abs(p.offsetY), 0);
});
test('uses two-finger gestures and restores the previous window orientation', () => {
  assert.match(source, /PinchGesture\(\{ fingers: 2 \}\)/);
  assert.match(source, /PanGesture\(\{ fingers: 2 \}\)/);
  assert.match(source, /setPreferredOrientation\(this.previousOrientation\)/);
  assert.match(source, /this.onPosition\(this.seconds\)/);
});
