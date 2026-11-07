const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const values = new Map([['access_token', 'local-session']]);
const registrations = new Map(), shared = [], removed = [], removedDirectories = [], written = [];
class SharedData {
  constructor(record) { this.records = [record]; }
  getRecords() { return this.records; }
}
let available = true;
class FileRecord { constructor(uri) { this.uri = uri; } getEntry() { return undefined; } }
class VideoRecord extends FileRecord { constructor(uri) { super(uri); this.videoUri = uri; } }
const sandbox = vm.createContext({ Date, console, setTimeout, clearTimeout,
  AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
  canIUse: () => available, deviceInfo: { apiAvailable: () => available },
  utd: { UniformDataType: { TEXT: 'general.text', VIDEO: 'general.video', MARKDOWN: 'general.markdown', FILE_URI: 'general.file-uri' } },
  udmf: { File: FileRecord, Video: VideoRecord },
  fileUri: { getUriFromPath: p => 'file://app' + p,
    FileUri: class { constructor(uri) { this.name = decodeURIComponent(uri.split('/').at(-1)); this.path = uri.replace('file://app', ''); } } },
  videoContentType: name => /\.(mp4|mov|avi|mkv|webm)$/i.test(name) ? 'video/test' : '',
  fs: { mkdirSync() {}, rmdirSync: p => removedDirectories.push(p), unlinkSync: p => removed.push(p),
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    openSync: path => ({ fd: path }), writeSync: (path, text) => written.push({ path, text }), closeSync() {} },
  systemShare: { SharedData,
    getSharedData: async want => want.data,
    ShareController: class { constructor(data) { this.data = data; } async show() { shared.push(this.data); } },
    SelectionMode: { SINGLE: 0 }, SharePreviewMode: { DETAIL: 1 } },
  harmonyShare: {
    SharableErrorCode: { NO_CONTENT_ERROR: 1 }, ReceivableErrorCode: { NO_RECEIVABLE_ERROR: 1 },
    ShareResultCode: { SHARE_SUCCESS: 0 },
    on: (event, _registry, callback) => registrations.set(event, callback),
    off: event => registrations.delete(event)
  }
});
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/videoShare.ets'), 'utf8');
vm.runInContext(ts.transpileModule(source.replace(/^import .*;\r?\n/gm, '').replace(/export /g, ''),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText +
  '\nglobalThis.api = { VideoShare, sharedVideoUris, droppedVideoRecords };', sandbox);
const { VideoShare: share, sharedVideoUris: uris, droppedVideoRecords: dropped } = sandbox.api;
const record = uri => ({ utd: 'general.video', uri });
assert.deepEqual(Array.from(uris([record('https://example/video.mp4'), record('file://app/a.txt'),
  record('file://app/a.mp4'), record('file://app/a.mp4')])), ['file://app/a.mp4']);
assert.deepEqual(Array.from(uris(dropped([new FileRecord('file://app/a.mp4'), new VideoRecord('file://app/b.mov'),
  { getEntry: () => 'file://app/c.webm' }, new FileRecord('file://app/not-video.pdf')]))),
  ['file://app/a.mp4', 'file://app/b.mov', 'file://app/c.webm']);
(async () => {
  share.bind({ cacheDir: '/cache' }, 3); share.setReceiving(true);
  assert.ok(registrations.has('dataReceive'));
  share.enqueue([record('file://app/original.mp4')]);
  assert.equal(shared.length, 0, 'receiving never uploads or sends a video');
  assert.equal(share.pending().length, 1);
  share.remove('file://app/original.mp4'); assert.equal(removed.length, 0, 'external files must remain untouched');
  share.enqueue([record('file://app/cache/received-video-lookalike/a.mp4')]);
  share.remove('file://app/cache/received-video-lookalike/a.mp4'); assert.equal(removed.length, 0);
  let receiveArgs;
  registrations.get('dataReceive')({ receive: () => { throw new Error('native receive unavailable'); } });
  assert.match(values.get('share_hint'), /无法接收/);
  assert.equal(removedDirectories.length, 1, 'synchronous native failure releases the temporary directory');
  registrations.get('dataReceive')({ receive: async (directory, callbacks) => { receiveArgs = { directory, callbacks }; } });
  receiveArgs.callbacks.onDataReceived({ getRecords() { throw new Error('malformed transfer'); } });
  assert.match(values.get('share_hint'), /无法读取/);
  assert.equal(removedDirectories.length, 2, 'invalid transfer releases the receiver for another attempt');
  registrations.get('dataReceive')({ receive: async (directory, callbacks) => { receiveArgs = { directory, callbacks }; } });
  const received = receiveArgs.directory + '/a.mp4';
  receiveArgs.callbacks.onDataReceived(new SharedData(record(received)));
  receiveArgs.callbacks.onDataReceived(new SharedData(record(received)));
  assert.equal(removedDirectories.length, 2, 'duplicate completion cannot delete the queued video');
  assert.equal(share.pendingName(), 'a.mp4');
  share.remove(received); assert.equal(removed.length, 1);
  share.setConclusion('结论内容'); assert.ok(registrations.has('knockShare'));
  let rejected = false, data;
  const target = { share: async value => { data = value; }, reject: async () => { rejected = true; } };
  await registrations.get('knockShare')(target); assert.equal(data.getRecords()[0].content, '结论内容');
  values.set('anti_peep_state', 'shielded'); await registrations.get('knockShare')(target); assert.ok(rejected);
  await assert.rejects(share.shareReport({ cacheDir: '/cache' }, '问题', '答案'));
  values.delete('anti_peep_state');
  await share.shareReport({ cacheDir: '/cache' }, '问题', '见视频 1 的 00:24');
  assert.equal(shared.at(-1).getRecords()[0].utd, 'general.markdown');
  assert.match(written[0].text, /见视频 1 的 00:24/);
  assert.ok(!written[0].text.includes('local-session'));
  share.setForeground(false); assert.equal(registrations.size, 0);
  share.setForeground(true); assert.ok(registrations.has('dataReceive'));
  share.enqueue(Array.from({ length: 8 }, (_, i) => record(`file://app/${i}.mp4`)));
  assert.equal(share.pending().length, 5);
  share.clear(); assert.equal(share.pending().length, 0); assert.equal(registrations.size, 0);
  assert.ok(removed.includes(written[0].path), 'reports are removed from cache on logout');
  values.delete('access_token'); share.setReceiving(true); assert.equal(registrations.size, 0);
  values.set('access_token', 'local-session'); available = false; share.setForeground(true);
  assert.equal(registrations.size, 0);
  console.log('video receiving and knock share boundaries passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
