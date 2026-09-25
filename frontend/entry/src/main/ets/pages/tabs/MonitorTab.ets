import { HttpUtil, BASE_HOST } from '../../utils/http'

interface ToastOptions {
  message: string;
  duration?: number;
}

export class MonitorInfo {
  id: number = 0;
  name: string = '';
  stream_url: string = '';
  raw_stream_url: string = '';
  cover_url: string = '';
  live_url: string = '';
  media_url: string = '';
  status: string = '';
  recording_state: string = '';
  source_configured: boolean = false;
  can_manage: boolean = false;
}

class AddMonitorPayload {
  name: string = '';
  stream_url: string = '';
}

class EditMonitorPayload {
  name: string = '';
  stream_url: string = '';
}

class GranularityOption {
  key: string = '';
  label: string = '';
  stepSeconds: number = 60;

  constructor(key: string, label: string, stepSeconds: number) {
    this.key = key;
    this.label = label;
    this.stepSeconds = stepSeconds;
  }
}

class TimelineRange {
  startEpoch: number = 0;
  endEpoch: number = 0;

  constructor(startEpoch: number, endEpoch: number) {
    this.startEpoch = startEpoch;
    this.endEpoch = endEpoch;
  }
}

const GRANULARITIES: Array<GranularityOption> = [
  new GranularityOption('day', '天', 86400),
  new GranularityOption('hour', '时', 3600),
  new GranularityOption('minute', '分', 60),
  new GranularityOption('second', '秒', 1)
];

@CustomDialog
struct AddMonitorDialog {
  controller: CustomDialogController
  @State monitorName: string = '';
  @State streamUrl: string = '';
  confirm: (name: string, streamUrl: string) => void = (_n: string, _u: string): void => {};

  build() {
    Column({ space: 15 }) {
      Text('添加监控').fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      TextInput({ placeholder: '监控名称', text: this.monitorName })
        .onChange((val: string): void => {
          this.monitorName = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      TextInput({ placeholder: '视频流地址 (stream_url)', text: this.streamUrl })
        .onChange((val: string): void => {
          this.streamUrl = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      Row({ space: 20 }) {
        Button('取消')
          .height(40)
          .fontColor($r('app.color.app_text_primary'))
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.app_border') })
          .borderRadius(8)

        Button('添加视频源')
          .height(40)
          .backgroundColor($r('app.color.app_surface_inverted'))
          .fontColor($r('app.color.app_text_on_inverted'))
          .borderRadius(8)
          .onClick((): void => {
            this.confirm(this.monitorName, this.streamUrl);
            this.controller.close();
          })
      }.margin({ top: 10 })
    }.padding(20).width('90%')
  }
}

@Component
export struct MonitorTab {
  @Prop @Watch('onGroupChange') groupId: number = 0;
  @State monitors: Array<MonitorInfo> = [];
  @State selectedMonitorId: number = 0;
  @State selectedMonitorName: string = '';
  @State selectedMonitorUrl: string = '';
  @State isLiveStream: boolean = false;
  @State playbackMode: string = 'live';
  @State granularity: string = 'minute';
  @State selectedTimeText: string = '';
  @State timelineStartEpoch: number = 0;
  @State timelineEndEpoch: number = 0;
  @State timelinePositionSeconds: number = 0;
  @State timelineRanges: Array<TimelineRange> = [];
  @State timelineErrorText: string = '';
  @State hasReplayAtSelectedTime: boolean = false;
  @State isLoadingPlayback: boolean = false;
  @State jumpTimeText: string = '';
  @State playbackOffsetSeconds: number = 0;
  @State playbackSegmentEndEpoch: number = 0;
  @State editingMonitorId: number = 0;
  @State editingMonitorName: string = '';
  @State editingMonitorUrl: string = '';
  videoController: VideoController = new VideoController();
  coverRefreshTimer: number = 0;
  liveTimelineTimer: number = 0;
  liveTimelineRefreshTicks: number = 0;
  isRefreshingLiveTimeline: boolean = false;
  isLoadingMonitors: boolean = false;

  showToast(options: ToastOptions): void {
    try {
      this.getUIContext().getPromptAction().showToast(options);
    } catch (error) {
      console.warn('[UI] Toast display failed:', JSON.stringify(error));
    }
  }

  addMonitorDialogController: CustomDialogController = new CustomDialogController({
    builder: AddMonitorDialog({
      confirm: (name: string, streamUrl: string): void => {
        this.submitAddMonitor(name, streamUrl);
      }
    }),
    autoCancel: true
  })

  aboutToAppear(): void {
    this.loadMonitors();
    this.startCoverRefreshTimer();
    this.startLiveTimelineTimer();
  }

  aboutToDisappear(): void {
    if (this.coverRefreshTimer) {
      clearInterval(this.coverRefreshTimer);
      this.coverRefreshTimer = 0;
    }
    if (this.liveTimelineTimer) {
      clearInterval(this.liveTimelineTimer);
      this.liveTimelineTimer = 0;
    }
  }

  startCoverRefreshTimer(): void {
    if (this.coverRefreshTimer) {
      clearInterval(this.coverRefreshTimer);
    }
    this.coverRefreshTimer = setInterval(async (): Promise<void> => {
      if (this.groupId && this.selectedMonitorId === 0) {
        await this.loadMonitors();
      }
    }, 60000);
  }

  startLiveTimelineTimer(): void {
    if (this.liveTimelineTimer) {
      clearInterval(this.liveTimelineTimer);
    }
    this.liveTimelineTimer = setInterval((): void => {
      if (!this.selectedMonitorId || this.playbackMode !== 'live') {
        this.liveTimelineRefreshTicks = 0;
        return;
      }
      this.followLiveEdge();
      this.liveTimelineRefreshTicks += 1;
      if (this.liveTimelineRefreshTicks >= 15) {
        this.liveTimelineRefreshTicks = 0;
        this.refreshLiveTimeline();
      }
    }, 1000);
  }

  followLiveEdge(): void {
    const nowEpoch = Math.floor(Date.now() / 1000);
    const duration = Math.max(1, this.timelineEndEpoch - this.timelineStartEpoch);
    this.timelineEndEpoch = nowEpoch;
    this.timelineStartEpoch = nowEpoch - duration;
    this.timelinePositionSeconds = duration;
    this.selectedTimeText = this.formatEpochSeconds(nowEpoch);
    this.jumpTimeText = this.selectedTimeText;
  }

  async refreshLiveTimeline(): Promise<void> {
    if (this.isRefreshingLiveTimeline || this.playbackMode !== 'live') {
      return;
    }
    this.isRefreshingLiveTimeline = true;
    try {
      await this.loadTimeline(this.formatDateTime(new Date()), false);
    } finally {
      this.isRefreshingLiveTimeline = false;
    }
  }

  onGroupChange(): void {
    this.resetSelection();
    this.loadMonitors();
  }

  resetSelection(): void {
    this.selectedMonitorId = 0;
    this.selectedMonitorName = '';
    this.selectedMonitorUrl = '';
    this.isLiveStream = false;
    this.playbackMode = 'live';
    this.granularity = 'minute';
    this.selectedTimeText = '';
    this.timelineStartEpoch = 0;
    this.timelineEndEpoch = 0;
    this.timelinePositionSeconds = 0;
    this.timelineRanges = [];
    this.timelineErrorText = '';
    this.hasReplayAtSelectedTime = false;
    this.isLoadingPlayback = false;
    this.jumpTimeText = '';
    this.playbackOffsetSeconds = 0;
    this.playbackSegmentEndEpoch = 0;
    this.editingMonitorId = 0;
    this.editingMonitorName = '';
    this.editingMonitorUrl = '';
  }

  buildSourceUrl(url: string): string {
    if (!url) {
      return '';
    }
    return url.includes('?') ? `${url}&t=${Date.now()}` : `${url}?t=${Date.now()}`;
  }

  buildHttpUrl(path: string): string {
    return `${BASE_HOST}${path}${path.includes('?') ? '&' : '?'}t=${Date.now()}`;
  }

  formatDateTime(date: Date): string {
    const pad = (value: number): string => value.toString().padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  }

  parseDateTime(text: string): string {
    const raw = text.trim();
    if (!raw) {
      return '';
    }
    const normalized = raw.includes('T') ? raw : raw.replace(' ', 'T');
    const date = new Date(normalized);
    if (isNaN(date.getTime())) {
      return '';
    }
    return this.formatDateTime(date).replace(' ', 'T');
  }

  granularityStepSeconds(): number {
    for (let i = 0; i < GRANULARITIES.length; i++) {
      if (GRANULARITIES[i].key === this.granularity) {
        return GRANULARITIES[i].stepSeconds;
      }
    }
    return 60;
  }

  timestampFromText(value: string): number {
    const match = value.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/);
    if (!match) {
      return NaN;
    }
    return new Date(
      Number(match[1]),
      Number(match[2]) - 1,
      Number(match[3]),
      Number(match[4]),
      Number(match[5]),
      Number(match[6])
    ).getTime();
  }

  formatEpochSeconds(epochSeconds: number): string {
    return this.formatDateTime(new Date(epochSeconds * 1000));
  }

  clampTimelinePosition(value: number): number {
    const duration = Math.max(0, this.timelineEndEpoch - this.timelineStartEpoch);
    return Math.max(0, Math.min(duration, value));
  }

  buildTimelineRanges(rawRanges: Array<Record<string, Object>>, startEpoch: number, endEpoch: number): Array<TimelineRange> {
    const ranges: Array<TimelineRange> = [];
    for (let i = 0; i < rawRanges.length; i++) {
      const item = rawRanges[i];
      const rangeStart = Math.floor(this.timestampFromText((item['start_time'] as string) || '') / 1000);
      const rangeEnd = Math.floor(this.timestampFromText((item['end_time'] as string) || '') / 1000);
      const clippedStart = Math.max(startEpoch, rangeStart);
      const clippedEnd = Math.min(endEpoch, rangeEnd);
      if (!isNaN(clippedStart) && !isNaN(clippedEnd) && clippedEnd > clippedStart) {
        ranges.push(new TimelineRange(clippedStart, clippedEnd));
      }
    }
    return ranges;
  }

  isReplayableAt(epoch: number): boolean {
    for (let i = 0; i < this.timelineRanges.length; i++) {
      const range = this.timelineRanges[i];
      if (epoch >= range.startEpoch && epoch < range.endEpoch) {
        return true;
      }
    }
    return false;
  }

  timelineRangeLeft(range: TimelineRange): string {
    const duration = Math.max(1, this.timelineEndEpoch - this.timelineStartEpoch);
    return `${Math.max(0, Math.min(100, (range.startEpoch - this.timelineStartEpoch) * 100 / duration))}%`;
  }

  timelineRangeWidth(range: TimelineRange): string {
    const duration = Math.max(1, this.timelineEndEpoch - this.timelineStartEpoch);
    return `${Math.max(1, Math.min(100, (range.endEpoch - range.startEpoch) * 100 / duration))}%`;
  }

  seekPlaybackOffset(): void {
    if (this.playbackMode !== 'history') {
      return;
    }
    this.videoController.pause();
    this.videoController.setCurrentTime(this.playbackOffsetSeconds, SeekMode.Accurate);
    this.videoController.start();
  }

  async loadMonitors(): Promise<void> {
    if (!this.groupId) {
      this.monitors = [];
      return;
    }
    if (this.isLoadingMonitors) {
      return;
    }

    this.isLoadingMonitors = true;
    try {
      const res = await HttpUtil.get(`/monitors/${this.groupId}`);
      if (res.code === 0 && res.data) {
        const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
        this.monitors = listObj.map((item: Record<string, Object>): MonitorInfo => {
          const monitor = new MonitorInfo();
          monitor.id = item['id'] as number;
          monitor.name = item['name'] as string;
          monitor.status = (item['status'] as string) || '';
          monitor.recording_state = (item['recording_state'] as string) || '';
          monitor.source_configured = Boolean(item['source_configured']);
          monitor.can_manage = Boolean(item['can_manage']);

          const rawUrl = ((item['stream_url'] as string) || '').trim();
          monitor.raw_stream_url = rawUrl;
          const coverUrl = ((item['cover_url'] as string) || '').trim();
          monitor.cover_url = coverUrl ? this.buildHttpUrl(coverUrl) : '';
          monitor.live_url = ((item['live_url'] as string) || '').trim();
          monitor.media_url = ((item['media_url'] as string) || '').trim();
          // All viewers use the server's signed HLS relay. Source addresses
          // (and their credentials) never become part of the viewing UI.
          monitor.stream_url = monitor.live_url ? `${BASE_HOST}${monitor.live_url}` : '';
          return monitor;
        });
      } else {
        this.monitors = [];
      }
    } finally {
      this.isLoadingMonitors = false;
    }
  }

  openEditMonitor(monitor: MonitorInfo): void {
    this.editingMonitorId = monitor.id;
    this.editingMonitorName = monitor.name;
    this.editingMonitorUrl = monitor.raw_stream_url;
  }

  cancelEditMonitor(): void {
    this.editingMonitorId = 0;
    this.editingMonitorName = '';
    this.editingMonitorUrl = '';
  }

  async submitEditMonitor(monitorId: number): Promise<void> {
    const nextName = this.editingMonitorName.trim();
    const nextUrl = this.editingMonitorUrl.trim();
    if (!nextName) {
      this.showToast({ message: '请填写监控名称', duration: 2000 });
      return;
    }
    const payload = new EditMonitorPayload();
    payload.name = nextName;
    payload.stream_url = nextUrl;
    const res = await HttpUtil.put(`/monitors/${monitorId}`, payload);
    if (res.code === 0) {
      this.showToast({ message: '监控已更新', duration: 2000 });
      this.cancelEditMonitor();
      this.loadMonitors();
      if (this.selectedMonitorId === monitorId) {
        this.resetSelection();
      }
    } else {
      this.showToast({ message: res.message || '更新失败', duration: 2000 });
    }
  }

  confirmDeleteMonitor(monitor: MonitorInfo): void {
    this.getUIContext().showAlertDialog({
      title: '删除监控',
      message: `确认删除“${monitor.name}”？录制文件和封面也会一起删除。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#C00000',
        action: (): void => {
          this.deleteMonitor(monitor);
        }
      }
    });
  }

  @Builder MonitorSymbol(name: string, color: ResourceColor, size: number) {
    if (name === 'back') {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(size)
        .fontColor([color])
    } else if (name === 'add') {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(size)
        .fontColor([color])
    } else if (name === 'open') {
      SymbolGlyph($r('sys.symbol.eye'))
        .fontSize(size)
        .fontColor([color])
    } else if (name === 'edit') {
      SymbolGlyph($r('sys.symbol.pencil_line'))
        .fontSize(size)
        .fontColor([color])
    } else if (name === 'delete') {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(size)
        .fontColor([color])
    } else if (name === 'save') {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(size)
        .fontColor([color])
    } else if (name === 'cancel') {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(size)
        .fontColor([color])
    } else if (name === 'jump') {
      SymbolGlyph($r('sys.symbol.arrowshape_right_fill'))
        .fontSize(size)
        .fontColor([color])
    } else {
      SymbolGlyph($r('sys.symbol.camera'))
        .fontSize(size)
        .fontColor([color])
    }
  }

  @Builder MonitorIconButton(name: string, color: ResourceColor, background: ResourceColor, action: () => void) {
    Button() {
      this.MonitorSymbol(name, color, 18)
    }
    .width(36)
    .height(36)
    .padding(0)
    .backgroundColor(background)
    .borderRadius(8)
    .border({ width: 1, color: $r('app.color.app_border') })
    .onClick(action)
  }

  @Builder MonitorFilterButton(label: string, isSelected: boolean, action: () => void) {
    Button(label)
      .height(36)
      .fontSize(12)
      .fontWeight(isSelected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(isSelected ? $r('app.color.app_text_primary') : $r('app.color.app_text_secondary'))
      .backgroundColor(Color.Transparent)
      .border({
        width: { bottom: isSelected ? 3 : 1 },
        color: isSelected ? $r('app.color.app_accent') : $r('app.color.app_border')
      })
      .borderRadius(0)
      .onClick(action)
  }

  @Builder MonitorCover(monitor: MonitorInfo) {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 6 }) {
        this.MonitorSymbol('camera', $r('app.color.app_text_secondary'), 28)
        Text('封面生成中')
          .fontSize(11)
          .fontColor($r('app.color.app_text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.app_card_subtle_bg'))

      Image(monitor.cover_url)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
    .width('100%')
    .height(100)
    .borderRadius({ topLeft: 11, topRight: 11 })
    .clip(true)
    .backgroundColor(Color.Gray)
    .onClick((): void => {
      this.openMonitor(monitor);
    })
  }

  async deleteMonitor(monitor: MonitorInfo): Promise<void> {
    const res = await HttpUtil.del(`/monitors/${monitor.id}`);
    if (res.code === 0) {
      this.showToast({ message: '监控已删除', duration: 2000 });
      if (this.selectedMonitorId === monitor.id) {
        this.resetSelection();
      }
      if (this.editingMonitorId === monitor.id) {
        this.cancelEditMonitor();
      }
      this.loadMonitors();
    } else {
      this.showToast({ message: res.message || '删除失败', duration: 2000 });
    }
  }

  async submitAddMonitor(name: string, streamUrl: string): Promise<void> {
    const nextName = name.trim();
    const nextUrl = streamUrl.trim();
    if (!nextName || !nextUrl) {
      this.showToast({ message: '请填写完整信息', duration: 2000 });
      return;
    }
    const payload = new AddMonitorPayload();
    payload.name = nextName;
    payload.stream_url = nextUrl;
    const res = await HttpUtil.post(`/monitors/${this.groupId}`, payload);
    if (res.code === 0) {
      this.showToast({ message: '监控添加成功', duration: 2000 });
      this.loadMonitors();
    } else {
      this.showToast({ message: res.message || '添加失败', duration: 2000 });
    }
  }

  async openMonitor(monitor: MonitorInfo): Promise<void> {
    if (!monitor.source_configured || !monitor.stream_url) {
      this.showToast({ message: '该监控设备未配置有效的视频源地址！', duration: 2000 });
      return;
    }

    this.selectedMonitorId = monitor.id;
    this.selectedMonitorName = monitor.name;
    this.isLiveStream = true;
    this.playbackMode = 'live';
    this.playbackOffsetSeconds = 0;
    this.selectedMonitorUrl = this.buildSourceUrl(monitor.stream_url);
    this.selectedTimeText = this.formatDateTime(new Date());
    this.jumpTimeText = this.selectedTimeText;
    await this.loadTimeline(this.selectedTimeText);
  }

  async loadTimeline(anchorIso: string, activatePlayback: boolean = false): Promise<void> {
    if (!this.selectedMonitorId) {
      return;
    }
    const res = await HttpUtil.get(`/monitors/${this.selectedMonitorId}/history?anchor=${encodeURIComponent(anchorIso)}&granularity=${this.granularity}&window=6`);
    if (res.code !== 0 || !res.data) {
      this.timelineErrorText = res.message || '无法读取录像可用时间，请稍后重试';
      this.timelineRanges = [];
      this.hasReplayAtSelectedTime = false;
      return;
    }

    const dataObj = JSON.parse(res.data) as Record<string, Object>;
    const selectedTime = (dataObj['selected_time'] as string) || anchorIso;
    const windowStart = (dataObj['window_start'] as string) || '';
    const windowEnd = (dataObj['window_end'] as string) || '';
    const availableRanges = (dataObj['available_ranges'] as Array<Record<string, Object>>) || [];

    this.selectedTimeText = selectedTime;
    this.jumpTimeText = this.formatDateTime(new Date(selectedTime));
    this.timelineErrorText = '';
    const responseStartEpoch = Math.floor(this.timestampFromText(windowStart) / 1000);
    const responseEndEpoch = Math.floor(this.timestampFromText(windowEnd) / 1000);
    const selectedEpoch = Math.floor(this.timestampFromText(selectedTime) / 1000);
    if (isNaN(responseStartEpoch) || isNaN(responseEndEpoch) || responseEndEpoch <= responseStartEpoch) {
      this.timelineStartEpoch = 0;
      this.timelineEndEpoch = 0;
      this.timelinePositionSeconds = 0;
      this.timelineRanges = [];
      this.hasReplayAtSelectedTime = false;
    } else {
      if (this.playbackMode === 'live' && !activatePlayback) {
        const duration = responseEndEpoch - responseStartEpoch;
        this.timelineEndEpoch = selectedEpoch;
        this.timelineStartEpoch = selectedEpoch - duration;
      } else {
        this.timelineStartEpoch = responseStartEpoch;
        this.timelineEndEpoch = responseEndEpoch;
      }
      this.timelinePositionSeconds = this.clampTimelinePosition(selectedEpoch - this.timelineStartEpoch);
      this.timelineRanges = this.buildTimelineRanges(availableRanges, this.timelineStartEpoch, this.timelineEndEpoch);
      this.hasReplayAtSelectedTime = this.isReplayableAt(selectedEpoch);
    }

    if (activatePlayback) {
      await this.startHistoricalPlayback(selectedTime);
    }
  }

  async startHistoricalPlayback(targetTime: string): Promise<void> {
    const res = await HttpUtil.get(`/monitors/${this.selectedMonitorId}/playback?time=${encodeURIComponent(targetTime)}`);
    if (res.code !== 0 || !res.data) {
      this.timelineErrorText = res.message || '该时间没有可回放录像';
      this.playbackMode = 'history';
      this.isLiveStream = false;
      this.selectedMonitorUrl = '';
      this.hasReplayAtSelectedTime = false;
      this.showToast({ message: this.timelineErrorText, duration: 2200 });
      return;
    }
    const dataObj = JSON.parse(res.data) as Record<string, Object>;
    const playbackUrl = (dataObj['playback_url'] as string) || '';
    const segmentEnd = (dataObj['segment_end_time'] as string) || '';
    if (!playbackUrl || !segmentEnd) {
      this.timelineErrorText = '回放地址无效，请重新选择时间';
      this.playbackMode = 'history';
      this.isLiveStream = false;
      this.selectedMonitorUrl = '';
      this.hasReplayAtSelectedTime = false;
      return;
    }
    this.playbackOffsetSeconds = Number(dataObj['seek_offset_seconds'] || 0);
    this.playbackSegmentEndEpoch = Math.floor(this.timestampFromText(segmentEnd) / 1000);
    this.playbackMode = 'history';
    this.isLiveStream = false;
    this.hasReplayAtSelectedTime = true;
    this.timelineErrorText = '';
    // Keep the signed media token intact; buildHttpUrl only adds a cache buster.
    this.selectedMonitorUrl = this.buildHttpUrl(playbackUrl);
  }

  async playNextContinuousSegment(): Promise<void> {
    if (this.playbackMode !== 'history' || this.playbackSegmentEndEpoch <= 0) {
      return;
    }
    const nextTime = this.formatEpochSeconds(this.playbackSegmentEndEpoch);
    if (this.shouldSwitchToLive(this.playbackSegmentEndEpoch)) {
      await this.goLive();
      return;
    }
    await this.loadTimeline(nextTime, true);
  }

  async goHistory(targetTime: string): Promise<void> {
    this.playbackMode = 'history';
    this.isLiveStream = false;
    this.isLoadingPlayback = true;
    this.timelineErrorText = '';
    this.hasReplayAtSelectedTime = false;
    this.selectedMonitorUrl = '';
    try {
      await this.loadTimeline(targetTime, true);
    } finally {
      this.isLoadingPlayback = false;
    }
  }

  async switchGranularity(key: string): Promise<void> {
    this.granularity = key;
    if (this.selectedMonitorId) {
      const anchor = this.playbackMode === 'live' ? this.formatDateTime(new Date()) : (this.selectedTimeText || this.formatDateTime(new Date()));
      await this.loadTimeline(anchor, false);
    }
  }

  shouldSwitchToLive(targetEpoch: number): boolean {
    const nowEpoch = Math.floor(Date.now() / 1000);
    const tolerance = Math.max(2, Math.min(30, Math.floor(this.granularityStepSeconds() / 2)));
    return targetEpoch >= nowEpoch - tolerance;
  }

  async jumpToTime(): Promise<void> {
    const isoTime = this.parseDateTime(this.jumpTimeText);
    if (!isoTime) {
      this.showToast({ message: '请输入有效时间格式 (YYYY-MM-DD HH:mm:ss)', duration: 2000 });
      return;
    }
    const targetDate = new Date(isoTime);
    const now = new Date();
    if (!isNaN(targetDate.getTime()) && targetDate.getTime() > now.getTime()) {
      this.showToast({ message: '已回到实时画面', duration: 1600 });
      await this.goLive();
      return;
    }
    const targetEpoch = Math.floor(targetDate.getTime() / 1000);
    if (this.shouldSwitchToLive(targetEpoch)) {
      await this.goLive();
      return;
    }
    await this.goHistory(isoTime);
  }

  async goLive(): Promise<void> {
    const monitor = this.monitors.find((item: MonitorInfo): boolean => item.id === this.selectedMonitorId);
    if (!monitor) {
      return;
    }
    this.playbackMode = 'live';
    this.isLiveStream = true;
    this.isLoadingPlayback = false;
    this.timelineErrorText = '';
    this.liveTimelineRefreshTicks = 0;
    this.playbackOffsetSeconds = 0;
    this.selectedMonitorUrl = this.buildSourceUrl(monitor.stream_url);
    const nowText = this.formatDateTime(new Date());
    this.selectedTimeText = nowText;
    this.jumpTimeText = nowText;
    await this.loadTimeline(nowText, false);
  }

  build() {
    Column() {
      if (this.selectedMonitorId !== 0) {
        Row() {
          this.MonitorIconButton('back', $r('app.color.app_text_primary'), $r('app.color.app_card_subtle_bg'), (): void => {
            this.resetSelection();
          })
          Column({ space: 2 }) {
            Text(this.selectedMonitorName)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.playbackMode === 'live' ? '实时查看' : '历史回放')
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .layoutWeight(1)
          .margin({ left: 10 })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 12 })

        Stack({ alignContent: Alignment.TopStart }) {
          if (this.playbackMode === 'live' || this.hasReplayAtSelectedTime) {
            Video({ src: this.selectedMonitorUrl, controller: this.videoController })
              .width('100%')
              .height(220)
              .autoPlay(true)
              .controls(false)
              .objectFit(ImageFit.Contain)
              .onPrepared((): void => {
                if (this.playbackMode === 'history' && this.playbackOffsetSeconds > 0) {
                  this.seekPlaybackOffset();
                }
              })
              .onError((): void => {
                this.timelineErrorText = this.playbackMode === 'history' ? '该时段录像加载失败，请重新选择时间' : '实时视频暂时不可用';
                if (this.playbackMode === 'history') {
                  this.hasReplayAtSelectedTime = false;
                  this.selectedMonitorUrl = '';
                }
                this.showToast({ message: this.timelineErrorText, duration: 2200 });
              })
              .onFinish((): void => {
                if (this.playbackMode === 'history') {
                  this.playNextContinuousSegment();
                }
              })
          }

          if (this.playbackMode === 'history' && !this.hasReplayAtSelectedTime) {
            Column({ space: 8 }) {
              Text(this.isLoadingPlayback ? '正在加载回放' : '无回放录像')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('rgba(255, 255, 255, 0.92)')
              Text(this.isLoadingPlayback ? '正在定位所选时间' : '请在时间轴中选择亮色录像段')
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.58)')
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(Color.Black)
          }

          Row() {
            Blank()
              .width(8)
              .height(8)
              .backgroundColor(this.playbackMode === 'live' ? Color.Red : Color.Orange)
              .borderRadius(4)
              .margin({ right: 6 })
            Text(this.playbackMode === 'live' ? 'LIVE 实时直播' : '历史回放')
              .fontSize(12)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .backgroundColor('rgba(0, 0, 0, 0.6)')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(5)
          .margin({ left: 15, top: 15 })
        }
        .width('90%')
        .height(220)
        .borderRadius(12)
        .clip(true)
        .backgroundColor(Color.Black)

        Row({ space: 10 }) {
          TextInput({ placeholder: 'YYYY-MM-DD HH:mm:ss', text: this.jumpTimeText })
            .layoutWeight(1)
            .height(42)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((value: string): void => {
              this.jumpTimeText = value;
            })
          this.MonitorIconButton('jump', $r('app.color.app_text_on_inverted'), $r('app.color.app_surface_inverted'), (): void => {
            this.jumpToTime();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })

        Row() {
          Text('录像时间轴')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
            .layoutWeight(1)
          if (this.playbackMode === 'history') {
            Button('回到实时')
              .height(32)
              .fontSize(12)
              .fontColor($r('app.color.app_text_on_inverted'))
              .backgroundColor($r('app.color.app_surface_inverted'))
              .borderRadius(16)
              .onClick((): void => {
                this.goLive();
              })
          } else {
            Row({ space: 6 }) {
              Row()
                .width(7)
                .height(7)
                .borderRadius(4)
                .backgroundColor(Color.Red)
              Text('跟随最新')
                .fontSize(12)
                .fontColor($r('app.color.app_text_secondary'))
            }
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 18, bottom: 8 })

        Column({ space: 9 }) {
          Row() {
            Text(this.timelineStartEpoch > 0 ? this.formatEpochSeconds(this.timelineStartEpoch) : '暂无录像')
              .fontSize(11)
              .fontColor($r('app.color.app_text_secondary'))
              .maxLines(1)
            Blank()
            Text(this.selectedTimeText || '选择回放时间')
              .fontSize(11)
              .fontColor(this.playbackMode === 'history' && !this.hasReplayAtSelectedTime ? $r('app.color.app_danger') : $r('app.color.app_text_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
            Blank()
            Text(this.timelineEndEpoch > 0 ? this.formatEpochSeconds(this.timelineEndEpoch) : '')
              .fontSize(11)
              .fontColor($r('app.color.app_text_secondary'))
              .maxLines(1)
          }
          .width('100%')

          Stack({ alignContent: Alignment.Center }) {
            Row()
              .width('100%')
              .height(8)
              .backgroundColor($r('app.color.app_card_subtle_bg'))
              .borderRadius(4)
            ForEach(this.timelineRanges, (range: TimelineRange): void => {
              Row()
                .width(this.timelineRangeWidth(range))
                .height(8)
                .backgroundColor($r('app.color.app_primary'))
                .borderRadius(4)
                .position({ x: this.timelineRangeLeft(range), y: 12 })
            }, (range: TimelineRange, idx: number): string => `${range.startEpoch}-${idx}`)
            Slider({
              value: this.timelinePositionSeconds,
              min: 0,
              max: Math.max(1, this.timelineEndEpoch - this.timelineStartEpoch),
              step: this.granularityStepSeconds()
            })
              .blockColor($r('app.color.app_surface_inverted'))
              .trackColor(Color.Transparent)
              .selectedColor(Color.Transparent)
              .width('100%')
              .onChange((value: number, mode: SliderChangeMode): void => {
                if (this.timelineStartEpoch <= 0) {
                  return;
                }
                const rounded = this.clampTimelinePosition(Math.round(value / this.granularityStepSeconds()) * this.granularityStepSeconds());
                this.timelinePositionSeconds = rounded;
                const target = this.formatEpochSeconds(this.timelineStartEpoch + rounded);
                this.selectedTimeText = target;
                this.jumpTimeText = target;
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  const targetEpoch = this.timelineStartEpoch + rounded;
                  if (this.shouldSwitchToLive(targetEpoch)) {
                    this.goLive();
                  } else {
                    this.goHistory(target);
                  }
                }
              })
          }
          .width('100%')
          .height(34)

          Row({ space: 8 }) {
            Text('时间精度')
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
              .margin({ right: 2 })
            ForEach(GRANULARITIES, (item: GranularityOption): void => {
              if (this.granularity === item.key) {
                this.MonitorFilterButton(item.label, true, (): void => {
                  this.switchGranularity(item.key);
                })
              } else {
                this.MonitorFilterButton(item.label, false, (): void => {
                  this.switchGranularity(item.key);
                })
              }
            }, (item: GranularityOption): string => item.key)
          }
          .width('100%')
          Row({ space: 6 }) {
            Row()
              .width(18)
              .height(5)
              .borderRadius(3)
              .backgroundColor($r('app.color.app_primary'))
            Text('可回放录像')
              .fontSize(11)
              .fontColor($r('app.color.app_text_secondary'))
          }
          if (this.timelineErrorText) {
            Text(this.timelineErrorText)
              .fontSize(12)
              .fontColor($r('app.color.app_danger'))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })

      } else {
        Row({ space: 12 }) {
          Column({ space: 3 }) {
            Text('实时监控')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
            Text(this.monitors.length > 0 ? `${this.monitors.length} 路视频源 · 封面自动刷新` : '接入实时视频或历史录像')
              .fontSize(13)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button() {
            Row({ space: 7 }) {
              Blank()
                .width(3)
                .height(18)
                .backgroundColor($r('app.color.app_accent'))
              this.MonitorSymbol('add', $r('app.color.app_text_on_inverted'), 15)
              Text('添加')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_text_on_inverted'))
            }
          }
          .height(40)
          .padding({ left: 13, right: 13 })
          .backgroundColor($r('app.color.app_surface_inverted'))
          .borderRadius(8)
          .onClick((): void => {
            this.addMonitorDialogController.open();
          })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 22, bottom: 16 })

        if (this.monitors.length === 0) {
          Column({ space: 10 }) {
            Stack() {
              Image($r('app.media.business_monitor'))
                .width(42)
                .height(42)
                .objectFit(ImageFit.Contain)
            }
            .width(64)
            .height(64)
            .borderRadius(14)
            .backgroundColor($r('app.color.app_card_subtle_bg'))
            .border({ width: 1, color: $r('app.color.app_border') })

            Text('还没有视频源')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))

            Text('添加摄像头或视频流，开始查看实时画面。')
              .fontSize(13)
              .fontColor($r('app.color.app_text_secondary'))
              .textAlign(TextAlign.Center)
              .width('78%')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 52 })
        } else {
          Grid() {
            ForEach(this.monitors, (monitor: MonitorInfo): void => {
              GridItem() {
                Column({ space: 8 }) {
                  this.MonitorCover(monitor)

                  if (this.editingMonitorId === monitor.id) {
                    TextInput({ placeholder: '监控名称', text: this.editingMonitorName })
                      .height(36)
                      .fontSize(13)
                      .fontColor($r('app.color.app_text_primary'))
                      .backgroundColor($r('app.color.app_input_bg'))
                      .onChange((val: string): void => {
                        this.editingMonitorName = val;
                      })
                    TextInput({ placeholder: '视频流地址', text: this.editingMonitorUrl })
                      .height(36)
                      .fontSize(13)
                      .fontColor($r('app.color.app_text_primary'))
                      .backgroundColor($r('app.color.app_input_bg'))
                      .onChange((val: string): void => {
                        this.editingMonitorUrl = val;
                      })
                    Row({ space: 10 }) {
                      Blank()
                      this.MonitorIconButton('save', $r('app.color.app_text_on_inverted'), $r('app.color.app_surface_inverted'), (): void => {
                        this.submitEditMonitor(monitor.id);
                      })
                      this.MonitorIconButton('cancel', $r('app.color.app_text_primary'), $r('app.color.app_card_subtle_bg'), (): void => {
                        this.cancelEditMonitor();
                      })
                      Blank()
                    }
                    .width('100%')
                    .padding({ left: 8, right: 8, bottom: 8 })
                  } else {
                    Text(monitor.name)
                      .fontSize(14)
                      .fontColor($r('app.color.app_text_primary'))
                      .padding({ left: 8, right: 8, top: 2 })
                      .width('100%')
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(!monitor.source_configured ? '未配置视频源' : monitor.recording_state === 'recording' ? '服务器正在连续保存录像' : '录像连接正在恢复')
                      .fontSize(10)
                      .fontColor($r('app.color.app_text_secondary'))
                      .padding({ left: 8, right: 8 })
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row({ space: 10 }) {
                      Blank()
                      this.MonitorIconButton('open', $r('app.color.app_text_on_inverted'), $r('app.color.app_surface_inverted'), (): void => {
                        this.openMonitor(monitor);
                      })
                      if (monitor.can_manage) {
                        this.MonitorIconButton('edit', $r('app.color.app_text_primary'), $r('app.color.app_card_subtle_bg'), (): void => {
                          this.openEditMonitor(monitor);
                        })
                        this.MonitorIconButton('delete', $r('app.color.app_danger'), $r('app.color.app_card_subtle_bg'), (): void => {
                          this.confirmDeleteMonitor(monitor);
                        })
                      }
                      Blank()
                    }
                    .width('100%')
                    .padding({ left: 8, right: 8, bottom: 8 })
                  }
                }
                .padding({ bottom: 8 })
                .backgroundColor($r('app.color.app_card_bg'))
                .border({ width: 1, color: $r('app.color.app_border') })
                .borderRadius(12)
              }
            })
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .padding({ left: 18, right: 18, bottom: 24 })
          .width('100%')
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
  }
}
