const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const utils = path.join(__dirname, '../entry/src/main/ets/utils');
function load(name, dependencies, globals = {}) {
  const context = vm.createContext({ exports: {}, require: key => {
    assert.ok(key in dependencies, `Unexpected dependency: ${key}`);
    return dependencies[key];
  }, console, ...globals });
  vm.runInContext(ts.transpileModule(fs.readFileSync(path.join(utils, name), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText, context);
  return context.exports;
}
class HttpResult { code = -1; message = ''; }
async function main() {
  let size = 1024, copyFails = false, uploadFails = false;
  const events = [];
  const nativeFs = {
    OpenMode: { READ_ONLY: 0 },
    open: async uri => { events.push(['open', uri]); return { fd: 7 }; },
    stat: async () => ({ size }),
    copyFile: async (fd, dest) => { events.push(['copy', fd, dest]); if (copyFails) throw Error('disk'); },
    close: async fd => events.push(['close', fd]),
    unlink: async dest => events.push(['unlink', dest])
  };
  const local = load('localVideoUpload.ets', {
    '@ohos.file.fs': { default: nativeFs },
    '@ohos.file.fileuri': { default: { FileUri: class { constructor(uri) { this.name = uri.split('/').pop(); } } } },
    './http': { HttpResult, HttpUtil: { uploadFile: async (...args) => {
      events.push(['upload', ...args.slice(0, 4)]);
      if (uploadFails) throw Error('network');
      args[4](50);
      return { code: 0, data: '{}' };
    } } }
  });
  for (const [ext, mime] of [['MP4', 'video/mp4'], ['mov', 'video/quicktime'],
    ['avi', 'video/x-msvideo'], ['mkv', 'video/x-matroska'], ['webm', 'video/webm']]) {
    assert.equal(local.videoContentType(`a.${ext}`), mime);
  }
  const percentages = [];
  assert.equal((await local.uploadLocalVideo(12, 'file://media/test.MP4', '/cache', p => percentages.push(p))).code, 0);
  assert.deepEqual(percentages, [50]);
  assert.equal(events.find(e => e[0] === 'upload')[1], '/workspaces/12/upload-video');
  assert.equal(events.find(e => e[0] === 'upload')[3], 'test.mp4');
  assert.ok(events.find(e => e[0] === 'copy')[2].startsWith('/cache/video-upload-'));
  assert.deepEqual(events.find(e => e[0] === 'close'), ['close', 7]);
  assert.equal(events.find(e => e[0] === 'unlink')[1], events.find(e => e[0] === 'copy')[2]);
  for (const test of ['unsupported', 'empty', 'oversize', 'copyFailure', 'uploadFailure']) {
    events.length = 0; size = 1024; copyFails = false; uploadFails = false;
    let uri = 'file://media/a.mp4';
    if (test === 'unsupported') uri = 'file://media/a.txt';
    if (test === 'empty') size = 0;
    if (test === 'oversize') size = 2 * 1024 ** 3 + 1;
    if (test === 'copyFailure') copyFails = true;
    if (test === 'uploadFailure') uploadFails = true;
    const result = await local.uploadLocalVideo(12, uri, '/cache', () => {});
    assert.equal(result.code, -1, test);
    assert.ok(result.message, test);
    if (test !== 'unsupported') assert.ok(events.some(e => e[0] === 'close'), test);
    if (test.includes('Failure')) assert.ok(events.some(e => e[0] === 'unlink'), test);
    else assert.ok(!events.some(e => e[0] === 'upload'), test);
  }
  let response = { responseCode: 201, result: JSON.stringify({ code: 0, data: { id: 'upload_1' } }) };
  let throws = false, destroyed = 0, options, progress;
  const http = load('http.ets', { '@ohos.net.http': { default: {
    RequestMethod: { POST: 'POST' },
    createHttp: () => ({
      on: (_, cb) => { progress = cb; },
      request: async (url, opts) => {
        assert.equal(url, 'http://example/api/workspaces/12/upload-video');
        options = opts;
        progress({ sendSize: 15, totalSize: 10 });
        if (throws) throw Error('network');
        return response;
      }, destroy: () => destroyed++
    })
  } } }, {
    AppStorage: { get: key => ({ is_custom_server: true, custom_server_url: 'http://example', access_token: 'token' })[key] },
    PersistentStorage: { persistProp() {} }
  });
  const sent = [];
  const upload = () => http.HttpUtil.uploadFile('/workspaces/12/upload-video', '/cache/a', 'a.mp4', 'video/mp4', p => sent.push(p));
  assert.equal((await upload()).code, 0);
  assert.equal(options.header.Authorization, 'Bearer token');
  assert.equal(options.header['Content-Type'], 'multipart/form-data');
  assert.equal(options.multiFormDataList[0].name, 'file');
  assert.equal(options.multiFormDataList[0].filePath, '/cache/a');
  assert.ok(!('data' in options.multiFormDataList[0]));
  assert.equal(options.readTimeout, 600000);
  assert.deepEqual(sent, [100]);
  response = { responseCode: 413, result: 'too large' };
  assert.match((await upload()).message, /超过/);
  response = { responseCode: 502, result: '<html>' };
  assert.match((await upload()).message, /HTTP 502/);
  response = { responseCode: 403, result: JSON.stringify({ code: 5001, message: 'not a group member' }) };
  assert.equal((await upload()).code, 5001);
  throws = true;
  assert.match((await upload()).message, /上传失败/);
  assert.equal(destroyed, 5);
  // Exercise picker cancellation, success and late responses without native UI.
  const pageSource = fs.readFileSync(path.join(utils, '../pages/WorkspaceDetail.ets'), 'utf8');
  const selectMethod = pageSource.slice(pageSource.indexOf('  async selectLocalVideo('),
    pageSource.indexOf('  handleExampleVideoClick('));
  let picked = ['file://media/a.mp4'], selectedUploads = 0;
  let uploadResult = { code: 0, data: JSON.stringify({ id: 'u1', name: 'a.mp4', filepath: 'storage/uploads/12/a.mp4', duration: 20 }) };
  const pageContext = vm.createContext({
    photoAccessHelper: { PhotoSelectOptions: class {}, PhotoViewMIMETypes: { VIDEO_TYPE: 'video/*' },
      PhotoViewPicker: class { async select(options) { assert.equal(options.MIMEType, 'video/*'); return { photoUris: picked }; } } },
    picker: { DocumentSelectOptions: class {}, DocumentViewPicker: class { async select(options) { assert.equal(options.maxSelectNumber, 1); return picked; } } },
    uploadLocalVideo: async () => { selectedUploads++; return uploadResult; }
  });
  vm.runInContext(ts.transpileModule(`class Harness {
    workspaceId = 12; workspaceVisible = true; showSelectExampleVideo = true;
    isUploadingVideo = false; videoUploadProgress = -1; videoUploadError = '';
    exampleVideos = []; opened = [];
    getUIContext() { return { getHostContext: () => ({ cacheDir: '/cache' }) }; }
    showToast() {} handleExampleVideoClick(index) { this.opened.push(index); }
    ${selectMethod}
  } globalThis.page = new Harness();`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, pageContext);
  const page = pageContext.page;
  picked = [];
  await page.selectLocalVideo(false);
  assert.equal(selectedUploads, 0);
  assert.equal(page.isUploadingVideo, false);
  picked = ['file://media/a.mp4'];
  await page.selectLocalVideo(true);
  assert.equal(page.exampleVideos[0].endOffset, 20);
  assert.equal(page.opened.length, 1);
  page.showSelectExampleVideo = false;
  await page.selectLocalVideo(false);
  assert.equal(page.opened.length, 1, 'Do not open dialog after leaving upload page');
  assert.equal(page.exampleVideos.length, 1, 'Uploaded source must not duplicate');
  page.isUploadingVideo = true;
  await page.selectLocalVideo(false);
  assert.equal(selectedUploads, 2, 'No duplicate concurrent upload');
  page.isUploadingVideo = false;
  uploadResult = { code: -1, message: 'upload failed' };
  await page.selectLocalVideo(false);
  assert.equal(page.videoUploadError, 'upload failed');
  assert.equal(page.isUploadingVideo, false);
  assert.match(pageSource, /@State enablePreprocess: boolean = true/);
  assert.match(pageSource, /payload\.enable_preprocess = enablePreprocess/);
  console.log('Local video upload: format, size, cache cleanup, multipart auth, progress and failures passed.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
