import { harmonyShare, systemShare } from '@kit.ShareKit';
import { common, Want } from '@kit.AbilityKit';
import { unifiedDataChannel as udmf, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { videoContentType } from './localVideoUpload';
import { deviceInfo } from '@kit.BasicServicesKit';

export function sharedVideoUris(records: Array<systemShare.SharedRecord>): Array<string> {
  const result: Array<string> = [];
  for (const record of records.slice(0, 20)) {
    const uri = record.uri || '';
    if (!uri.startsWith('file://') || uri.length > 4096 || /[\r\n\u0000]/.test(uri)) continue;
    let name = '';
    try { name = new fileUri.FileUri(uri).name; } catch (_error) { continue; }
    if (!videoContentType(name) || result.indexOf(uri) >= 0) continue;
    result.push(uri);
    if (result.length === 5) break;
  }
  return result;
}

export function droppedVideoRecords(records: Array<udmf.UnifiedRecord>): Array<systemShare.SharedRecord> {
  const result: Array<systemShare.SharedRecord> = [];
  for (const record of records.slice(0, 20)) {
    let uri = '';
    try {
      const value = record.getEntry(utd.UniformDataType.FILE_URI);
      if (typeof value === 'string') uri = value;
    } catch (_error) {}
    if (!uri) {
      try {
        if (record instanceof udmf.Video) uri = record.videoUri;
        else if (record instanceof udmf.File) uri = record.uri;
      } catch (_error) {}
    }
    if (uri) result.push({ utd: utd.UniformDataType.VIDEO, uri: uri });
  }
  return result;
}

// The inbox never uploads on receipt. A workspace and an explicit user action are required.
export class VideoShare {
  private static context: common.UIAbilityContext | undefined;
  private static receiver: harmonyShare.RecvCapabilityRegistry | undefined;
  private static sender: harmonyShare.SendCapabilityRegistry | undefined;
  private static foreground: boolean = true;
  private static windowId: number = 0;
  private static receiveEnabled: boolean = false;
  private static conclusion: string = '';
  private static receiveDirectory: string = '';
  private static generation: number = 0;
  private static sequence: number = 0;
  private static receiveDirectories: Set<string> = new Set<string>();
  private static reportPaths: Map<string, number> = new Map<string, number>();
  private static sendCallback = (target: harmonyShare.SharableTarget): void => {
    if (!VideoShare.foreground || !AppStorage.get<string>('access_token') || !VideoShare.conclusion ||
      AppStorage.get<string>('anti_peep_state') === 'shielded') {
      target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch((): void => {});
      return;
    }
    const generation = VideoShare.generation;
    target.share(VideoShare.conclusionData(VideoShare.conclusion)).catch((): void => {
      if (generation === VideoShare.generation)
        AppStorage.setOrCreate('share_hint', '碰一碰分享未完成，请重试或使用分享按钮');
    });
  };
  private static receiveCallback = (target: harmonyShare.ReceivableTarget): void => {
    const context = VideoShare.context;
    if (!context || !VideoShare.foreground || !VideoShare.receiveEnabled ||
      !AppStorage.get<string>('access_token') || VideoShare.receiveDirectory || VideoShare.pending().length >= 5) {
      target.reject(harmonyShare.ReceivableErrorCode.NO_RECEIVABLE_ERROR).catch((): void => {});
      return;
    }
    const directory = context.cacheDir + '/received-video-' + Date.now() + '-' + (++VideoShare.sequence);
    try { fs.mkdirSync(directory); } catch (_error) {
      target.reject(harmonyShare.ReceivableErrorCode.NO_RECEIVABLE_ERROR).catch((): void => {});
      return;
    }
    VideoShare.receiveDirectories.add(directory);
    VideoShare.receiveDirectory = directory;
    const generation = VideoShare.generation;
    target.receive(fileUri.getUriFromPath(directory), {
      onDataReceived: (data: systemShare.SharedData): void => {
        if (generation === VideoShare.generation && VideoShare.receiveDirectory === directory &&
          AppStorage.get<string>('access_token')) {
          VideoShare.receiveDirectory = '';
          VideoShare.enqueue(data.getRecords());
          VideoShare.pruneReceiveDirectory(directory);
        } else VideoShare.cleanDirectory(directory);
      },
      onResult: (code: harmonyShare.ShareResultCode): void => {
        if (code !== harmonyShare.ShareResultCode.SHARE_SUCCESS)
          VideoShare.receiveFailed(directory, generation, '视频传输未完成，请重新发送');
      }
    }).catch((): void => {
      VideoShare.receiveFailed(directory, generation, '无法接收视频，请重试');
    });
  };

  static bind(context: common.UIAbilityContext, windowId: number): void {
    VideoShare.context = context;
    VideoShare.windowId = windowId;
    VideoShare.sync();
  }

  static setForeground(value: boolean): void { VideoShare.foreground = value; VideoShare.sync(); }
  static setReceiving(value: boolean): void { VideoShare.receiveEnabled = value; VideoShare.sync(); }
  static setConclusion(value: string): void {
    const text = value.slice(0, 30000);
    if (text === VideoShare.conclusion) return;
    VideoShare.conclusion = text;
    VideoShare.sync();
  }

  private static sync(): void {
    VideoShare.unregister();
    if (!VideoShare.context || !VideoShare.foreground || !AppStorage.get<string>('access_token') ||
      !deviceInfo.apiAvailable('26.0.0') ||
      !canIUse('SystemCapability.Collaboration.HarmonyShare')) return;
    if (VideoShare.receiveEnabled) {
      const receiver: harmonyShare.RecvCapabilityRegistry = { windowId: VideoShare.windowId,
        capabilities: [{ utd: utd.UniformDataType.VIDEO, maxSupportedCount: 5 }] };
      try {
        harmonyShare.on('dataReceive', receiver, VideoShare.receiveCallback);
        VideoShare.receiver = receiver;
        AppStorage.setOrCreate('share_receive_available', true);
      } catch (_error) { AppStorage.setOrCreate('share_receive_available', false); }
    }
    if (VideoShare.conclusion) {
      const sender: harmonyShare.SendCapabilityRegistry = { windowId: VideoShare.windowId, sendOnly: true };
      try {
        harmonyShare.on('knockShare', sender, VideoShare.sendCallback);
        VideoShare.sender = sender;
      } catch (_error) {}
    }
  }

  private static unregister(): void {
    if (VideoShare.receiver) {
      try { harmonyShare.off('dataReceive', VideoShare.receiver, VideoShare.receiveCallback); } catch (_error) {}
    }
    if (VideoShare.sender) {
      try { harmonyShare.off('knockShare', VideoShare.sender, VideoShare.sendCallback); } catch (_error) {}
    }
    VideoShare.receiver = undefined;
    VideoShare.sender = undefined;
    AppStorage.setOrCreate('share_receive_available', false);
  }

  static enqueue(records: Array<systemShare.SharedRecord>): number {
    const existing = VideoShare.pending();
    const incoming = sharedVideoUris(records);
    const combined = [...existing, ...incoming.filter((uri: string): boolean => existing.indexOf(uri) < 0)];
    if (incoming.length === 0) {
      AppStorage.setOrCreate('share_hint', '没有可导入的视频，请检查文件格式后重试');
      return 0;
    }
    AppStorage.setOrCreate('shared_video_uris', JSON.stringify(combined.slice(0, 5)));
    AppStorage.setOrCreate('share_hint', combined.length > 5 ? '一次最多接收 5 个视频，请处理后再发送' : '');
    return Math.min(5, combined.length) - existing.length;
  }

  static async receiveWant(want: Want): Promise<void> {
    if (want.action !== 'ohos.want.action.sendData') return;
    const generation = VideoShare.generation;
    try {
      const data = await systemShare.getSharedData(want);
      if (generation === VideoShare.generation) VideoShare.enqueue(data.getRecords());
    } catch (_error) {
      if (generation === VideoShare.generation)
        AppStorage.setOrCreate('share_hint', '无法读取分享的视频，请从相册或文件重新选择');
    }
  }

  static pending(raw: string = AppStorage.get<string>('shared_video_uris') || '[]'): Array<string> {
    try { return JSON.parse(raw) as Array<string>; }
    catch (_error) { return []; }
  }

  static pendingName(raw?: string): string {
    const first = VideoShare.pending(raw)[0];
    try { if (first) return new fileUri.FileUri(first).name || '收到的视频'; } catch (_error) {}
    return '收到的视频';
  }

  static remove(uri: string): void {
    AppStorage.setOrCreate('shared_video_uris', JSON.stringify(VideoShare.pending().filter((item: string): boolean => item !== uri)));
    const directory = VideoShare.ownedDirectory(uri);
    if (!directory) return;
    try { fs.unlinkSync(new fileUri.FileUri(uri).path); } catch (_error) {}
    VideoShare.pruneReceiveDirectory(directory);
  }

  private static ownedDirectory(uri: string): string {
    try {
      const path = new fileUri.FileUri(uri).path;
      if (path.split('/').some((part: string): boolean => part === '..' || part === '.')) return '';
      for (const directory of VideoShare.receiveDirectories) {
        if (path.startsWith(directory + '/')) return directory;
      }
    } catch (_error) {}
    return '';
  }

  private static pruneReceiveDirectory(directory: string): void {
    if (!VideoShare.pending().some((uri: string): boolean => VideoShare.ownedDirectory(uri) === directory))
      VideoShare.cleanDirectory(directory);
  }

  private static receiveFailed(directory: string, generation: number, hint: string): void {
    if (generation !== VideoShare.generation || VideoShare.receiveDirectory !== directory) return;
    VideoShare.receiveDirectory = '';
    VideoShare.cleanDirectory(directory);
    AppStorage.setOrCreate('share_hint', hint);
  }

  private static cleanDirectory(directory: string): void {
    if (!VideoShare.receiveDirectories.delete(directory)) return;
    try { fs.rmdirSync(directory); } catch (_error) {}
  }

  static conclusionData(text: string): systemShare.SharedData {
    return new systemShare.SharedData({ utd: utd.UniformDataType.TEXT, content: text, title: '清眸调查结论' });
  }

  static async shareText(context: common.UIAbilityContext, text: string): Promise<void> {
    VideoShare.checkShareAccess();
    await new systemShare.ShareController(VideoShare.conclusionData(text)).show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE, previewMode: systemShare.SharePreviewMode.DETAIL });
  }

  private static checkShareAccess(): void {
    if (!AppStorage.get<string>('access_token') || AppStorage.get<string>('anti_peep_state') === 'shielded')
      throw new Error('Sharing unavailable in current session');
  }

  static async shareReport(context: common.UIAbilityContext, question: string, answer: string): Promise<void> {
    VideoShare.checkShareAccess();
    const path = context.cacheDir + '/清眸调查报告-' + Date.now() + '-' + (++VideoShare.sequence) + '.md';
    const report = '# 清眸调查报告\n\n## 问题\n\n' + question.trim() +
      '\n\n## 调查结论\n\n' + answer.trim() + '\n';
    try {
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, report); } finally { fs.closeSync(file); }
      const timer = setTimeout((): void => { VideoShare.cleanReport(path); }, 15 * 60 * 1000);
      VideoShare.reportPaths.set(path, timer);
      const data = new systemShare.SharedData({ utd: utd.UniformDataType.MARKDOWN,
        uri: fileUri.getUriFromPath(path), title: '清眸调查报告', label: 'FILE' });
      await new systemShare.ShareController(data).show(context, { selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL });
    } catch (_error) {
      VideoShare.cleanReport(path);
      throw new Error('Unable to share investigation report');
    }
  }

  private static cleanReport(path: string): void {
    const timer = VideoShare.reportPaths.get(path);
    if (timer !== undefined) clearTimeout(timer);
    VideoShare.reportPaths.delete(path);
    try { fs.unlinkSync(path); } catch (_error) {}
  }

  static clear(): void {
    VideoShare.generation++;
    VideoShare.conclusion = '';
    VideoShare.receiveEnabled = false;
    VideoShare.unregister();
    for (const uri of VideoShare.pending()) VideoShare.remove(uri);
    for (const directory of VideoShare.receiveDirectories) VideoShare.cleanDirectory(directory);
    for (const path of VideoShare.reportPaths.keys()) VideoShare.cleanReport(path);
    VideoShare.receiveDirectory = '';
    AppStorage.setOrCreate('share_hint', '');
  }
}
