import { HttpUtil, BASE_HOST } from '../../utils/http'
import promptAction from '@ohos.promptAction'

export class MonitorInfo {
  id: number = 0;
  name: string = '';
  stream_url: string = '';
  raw_stream_url: string = '';
  cover_url: string = '';
  status: string = '';
}

export class MonitorRecordInfo {
  start_time: string = '';
  end_time: string = '';
  filename: string = '';
  url: string = '';
  isSelected: boolean = false;
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
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)

        Button('提交')
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
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
  @State timelineLabel: string = '';
  @State timelineRecords: Array<MonitorRecordInfo> = [];
  @State selectedRecordIndex: number = -1;
  @State timelineOffsetValue: number = 0;
  @State isTimelineShifting: boolean = false;
  @State jumpTimeText: string = '';
  @State playbackOffsetSeconds: number = 0;
  @State editingMonitorId: number = 0;
  @State editingMonitorName: string = '';
  @State editingMonitorUrl: string = '';
  videoController: VideoController = new VideoController();
  coverRefreshTimer: number = 0;
  isLoadingMonitors: boolean = false;

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
  }

  aboutToDisappear(): void {
    if (this.coverRefreshTimer) {
      clearInterval(this.coverRefreshTimer);
      this.coverRefreshTimer = 0;
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
    this.timelineLabel = '';
    this.timelineRecords = [];
    this.selectedRecordIndex = -1;
    this.timelineOffsetValue = 0;
    this.isTimelineShifting = false;
    this.jumpTimeText = '';
    this.playbackOffsetSeconds = 0;
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

  granularityLabel(): string {
    for (let i = 0; i < GRANULARITIES.length; i++) {
      if (GRANULARITIES[i].key === this.granularity) {
        return GRANULARITIES[i].label;
      }
    }
    return '分';
  }

  granularityStepSeconds(): number {
    for (let i = 0; i < GRANULARITIES.length; i++) {
      if (GRANULARITIES[i].key === this.granularity) {
        return GRANULARITIES[i].stepSeconds;
      }
    }
    return 60;
  }

  timelineSliderLimit(): number {
    if (this.granularity === 'second') {
      return 90;
    }
    if (this.granularity === 'minute') {
      return 60;
    }
    if (this.granularity === 'hour') {
      return 24;
    }
    return 30;
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

  calculatePlaybackOffsetSeconds(targetTime: string, startTime: string, endTime: string): number {
    const targetMs = this.timestampFromText(targetTime);
    const startMs = this.timestampFromText(startTime);
    const endMs = this.timestampFromText(endTime);
    if (isNaN(targetMs) || isNaN(startMs)) {
      return 0;
    }

    let offset = Math.floor((targetMs - startMs) / 1000);
    if (offset < 0) {
      offset = 0;
    }
    if (!isNaN(endMs)) {
      const maxOffset = Math.max(0, Math.floor((endMs - startMs) / 1000) - 1);
      if (offset > maxOffset) {
        offset = maxOffset;
      }
    }
    return offset;
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

          const rawUrl = ((item['stream_url'] as string) || '').trim();
          monitor.raw_stream_url = rawUrl;
          const coverUrl = ((item['cover_url'] as string) || '').trim();
          monitor.cover_url = coverUrl ? this.buildHttpUrl(coverUrl) : this.buildHttpUrl(`/api/monitors/${monitor.id}/cover`);
          if (!rawUrl) {
            monitor.stream_url = '';
          } else if (rawUrl.startsWith('rtsp://') || rawUrl.startsWith('rtmp://')) {
            monitor.stream_url = `${BASE_HOST}/api/video/live/${monitor.id}/index.m3u8`;
          } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
            monitor.stream_url = rawUrl;
          } else {
            monitor.stream_url = `${BASE_HOST}/api/video/${rawUrl}`;
          }
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
      promptAction.showToast({ message: '请填写监控名称', duration: 2000 });
      return;
    }
    const payload = new EditMonitorPayload();
    payload.name = nextName;
    payload.stream_url = nextUrl;
    const res = await HttpUtil.put(`/monitors/${monitorId}`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '监控已更新', duration: 2000 });
      this.cancelEditMonitor();
      this.loadMonitors();
      if (this.selectedMonitorId === monitorId) {
        this.resetSelection();
      }
    } else {
      promptAction.showToast({ message: res.message || '更新失败', duration: 2000 });
    }
  }

  confirmDeleteMonitor(monitor: MonitorInfo): void {
    AlertDialog.show({
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
    .width(38)
    .height(38)
    .padding(0)
    .backgroundColor(background)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.app_border') })
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
    .borderRadius({ topLeft: 8, topRight: 8 })
    .clip(true)
    .backgroundColor(Color.Gray)
    .onClick((): void => {
      this.openMonitor(monitor);
    })
  }

  async deleteMonitor(monitor: MonitorInfo): Promise<void> {
    const res = await HttpUtil.del(`/monitors/${monitor.id}`);
    if (res.code === 0) {
      promptAction.showToast({ message: '监控已删除', duration: 2000 });
      if (this.selectedMonitorId === monitor.id) {
        this.resetSelection();
      }
      if (this.editingMonitorId === monitor.id) {
        this.cancelEditMonitor();
      }
      this.loadMonitors();
    } else {
      promptAction.showToast({ message: res.message || '删除失败', duration: 2000 });
    }
  }

  async submitAddMonitor(name: string, streamUrl: string): Promise<void> {
    const nextName = name.trim();
    const nextUrl = streamUrl.trim();
    if (!nextName || !nextUrl) {
      promptAction.showToast({ message: '请填写完整信息', duration: 2000 });
      return;
    }
    const payload = new AddMonitorPayload();
    payload.name = nextName;
    payload.stream_url = nextUrl;
    const res = await HttpUtil.post(`/monitors/${this.groupId}`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '监控添加成功', duration: 2000 });
      this.loadMonitors();
    } else {
      promptAction.showToast({ message: res.message || '添加失败', duration: 2000 });
    }
  }

  async openMonitor(monitor: MonitorInfo): Promise<void> {
    if (!monitor.stream_url) {
      promptAction.showToast({ message: '该监控设备未配置有效的视频源地址！', duration: 2000 });
      return;
    }

    this.selectedMonitorId = monitor.id;
    this.selectedMonitorName = monitor.name;
    this.isLiveStream = monitor.stream_url.includes('/live/');
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
      this.timelineRecords = [];
      this.timelineLabel = '';
      this.selectedRecordIndex = -1;
      return;
    }

    const dataObj = JSON.parse(res.data) as Record<string, Object>;
    const recordsObj = (dataObj['records'] as Array<Record<string, Object>>) || [];
    const selectedRecord = (dataObj['selected_record'] as Record<string, Object>) || null;
    const selectedTime = (dataObj['selected_time'] as string) || anchorIso;

    this.selectedTimeText = selectedTime;
    this.jumpTimeText = this.formatDateTime(new Date(selectedTime));
    this.timelineLabel = `${this.granularityLabel()}级回放窗口`;
    this.timelineOffsetValue = 0;
    this.selectedRecordIndex = -1;
    this.timelineRecords = recordsObj.map((item: Record<string, Object>, index: number): MonitorRecordInfo => {
      const record = new MonitorRecordInfo();
      record.start_time = item['start_time'] as string;
      record.end_time = item['end_time'] as string;
      record.filename = item['filename'] as string;
      record.url = this.buildHttpUrl(item['url'] as string);
      record.isSelected = selectedRecord !== null && (item['filename'] as string) === (selectedRecord['filename'] as string);
      if (record.isSelected) {
        this.selectedRecordIndex = index;
      }
      return record;
    });

    if (selectedRecord && activatePlayback) {
      this.playbackOffsetSeconds = this.calculatePlaybackOffsetSeconds(
        selectedTime,
        selectedRecord['start_time'] as string,
        selectedRecord['end_time'] as string
      );
      this.playbackMode = 'history';
      this.isLiveStream = false;
      this.selectedMonitorUrl = this.buildHttpUrl(selectedRecord['url'] as string);
    } else if (!selectedRecord && activatePlayback) {
      promptAction.showToast({ message: '该时间点没有对应录制片段', duration: 2000 });
    }
  }

  async switchGranularity(key: string): Promise<void> {
    this.granularity = key;
    if (this.selectedMonitorId) {
      const anchor = this.selectedTimeText || this.formatDateTime(new Date());
      await this.loadTimeline(anchor, this.playbackMode === 'history');
    }
  }

  async jumpToTime(): Promise<void> {
    const isoTime = this.parseDateTime(this.jumpTimeText);
    if (!isoTime) {
      promptAction.showToast({ message: '请输入有效时间，例如 2026-07-12 12:30:00', duration: 2000 });
      return;
    }
    const targetDate = new Date(isoTime);
    const now = new Date();
    if (!isNaN(targetDate.getTime()) && targetDate.getTime() > now.getTime()) {
      const nowText = this.formatDateTime(now);
      this.selectedTimeText = nowText;
      this.jumpTimeText = nowText;
      promptAction.showToast({ message: '不能跳转到未来时间', duration: 2000 });
      await this.loadTimeline(nowText, this.playbackMode === 'history');
      return;
    }
    await this.loadTimeline(isoTime, true);
  }

  async goLive(): Promise<void> {
    const monitor = this.monitors.find((item: MonitorInfo): boolean => item.id === this.selectedMonitorId);
    if (!monitor) {
      return;
    }
    this.playbackMode = 'live';
    this.isLiveStream = monitor.stream_url.includes('/live/');
    this.playbackOffsetSeconds = 0;
    this.selectedMonitorUrl = this.buildSourceUrl(monitor.stream_url);
    const nowText = this.formatDateTime(new Date());
    this.selectedTimeText = nowText;
    this.jumpTimeText = nowText;
    await this.loadTimeline(nowText, false);
  }

  async shiftTimeline(offsetSteps: number): Promise<void> {
    if (!this.selectedTimeText || this.isTimelineShifting) {
      return;
    }
    const date = new Date(this.selectedTimeText.replace(' ', 'T'));
    if (isNaN(date.getTime())) {
      this.timelineOffsetValue = 0;
      return;
    }

    this.isTimelineShifting = true;
    try {
      let shifted = new Date(date.getTime() + offsetSteps * this.granularityStepSeconds() * 1000);
      const now = new Date();
      if (shifted.getTime() > now.getTime()) {
        shifted = now;
        promptAction.showToast({ message: '不能移动到未来时间', duration: 1600 });
      }
      await this.loadTimeline(this.formatDateTime(shifted), this.playbackMode === 'history');
    } finally {
      this.timelineOffsetValue = 0;
      this.isTimelineShifting = false;
    }
  }

  build() {
    Column() {
      if (this.selectedMonitorId !== 0) {
        Row() {
          this.MonitorIconButton('back', Color.White, $r('app.color.app_primary'), (): void => {
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
        .padding(15)

        Stack({ alignContent: Alignment.TopStart }) {
          Video({ src: this.selectedMonitorUrl, controller: this.videoController })
            .width('100%')
            .height(250)
            .autoPlay(true)
            .controls(false)
            .objectFit(ImageFit.Contain)
            .onPrepared((): void => {
              if (this.playbackMode === 'history' && this.playbackOffsetSeconds > 0) {
                this.seekPlaybackOffset();
              }
            })
            .onError((): void => {
              promptAction.showToast({ message: '视频流加载失败，监控无画面！', duration: 2000 });
            })

          Row() {
            Circle({ width: 8, height: 8 })
              .fill(this.playbackMode === 'live' ? Color.Red : Color.Orange)
              .margin({ right: 6 })
            Text(this.playbackMode === 'live' ? 'LIVE 实时直播' : '历史回放')
              .fontSize(12)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .backgroundColor('rgba(0, 0, 0, 0.6)')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(12)
          .margin({ left: 15, top: 15 })
        }
        .width('100%')
        .height(250)
        .backgroundColor(Color.Black)

        Row({ space: 8 }) {
          Button('实时')
            .backgroundColor(this.playbackMode === 'live' ? $r('app.color.app_primary') : $r('app.color.app_card_bg'))
            .fontColor(this.playbackMode === 'live' ? Color.White : $r('app.color.app_text_primary'))
            .onClick((): void => {
              this.goLive();
            })
          Button('回放')
            .backgroundColor(this.playbackMode === 'history' ? $r('app.color.app_primary') : $r('app.color.app_card_bg'))
            .fontColor(this.playbackMode === 'history' ? Color.White : $r('app.color.app_text_primary'))
            .onClick((): void => {
              if (this.selectedTimeText) {
                this.loadTimeline(this.selectedTimeText, true);
              }
            })
          ForEach(GRANULARITIES, (item: GranularityOption): void => {
            Button(item.label)
              .backgroundColor(this.granularity === item.key ? $r('app.color.app_primary') : $r('app.color.app_card_bg'))
              .fontColor(this.granularity === item.key ? Color.White : $r('app.color.app_text_primary'))
              .onClick((): void => {
                this.switchGranularity(item.key);
              })
          }, (item: GranularityOption, idx: number): string => idx.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 })

        Row({ space: 10 }) {
          TextInput({ placeholder: 'YYYY-MM-DD HH:mm:ss', text: this.jumpTimeText })
            .layoutWeight(1)
            .height(42)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((value: string): void => {
              this.jumpTimeText = value;
            })
          this.MonitorIconButton('jump', Color.White, $r('app.color.app_primary'), (): void => {
            this.jumpToTime();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })

        Row() {
          Text(this.timelineLabel || '历史回放时间轴')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
            .layoutWeight(1)
          Text(this.selectedTimeText)
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 18, bottom: 8 })

        Column({ space: 4 }) {
          Row() {
            Text('前移')
              .fontSize(11)
              .fontColor($r('app.color.app_text_secondary'))
            Blank()
            Text('中央指针')
              .fontSize(11)
              .fontColor($r('app.color.app_text_secondary'))
            Blank()
            Text('后移')
              .fontSize(11)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .width('100%')

          Slider({ value: this.timelineOffsetValue, min: -this.timelineSliderLimit(), max: this.timelineSliderLimit(), step: 1 })
            .blockColor($r('app.color.app_primary'))
            .trackColor($r('app.color.app_text_muted'))
            .selectedColor($r('app.color.app_primary'))
            .width('100%')
            .onChange((value: number, mode: SliderChangeMode): void => {
              if (this.isTimelineShifting) {
                return;
              }
              const rounded = Math.round(value);
              this.timelineOffsetValue = rounded;
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                if (rounded !== 0) {
                  this.shiftTimeline(rounded);
                } else {
                  this.timelineOffsetValue = 0;
                }
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        if (this.timelineRecords.length === 0) {
          Column() {
            Text('当前时间附近没有找到可回放的录制片段')
              .fontSize(15)
              .fontColor($r('app.color.app_text_secondary'))
              .margin({ top: 18 })
          }
          .width('100%')
          .padding(16)
        } else {
          Scroll() {
            Row({ space: 10 }) {
              ForEach(this.timelineRecords, (record: MonitorRecordInfo, index: number): void => {
                Column({ space: 4 }) {
                  Text(record.start_time.slice(11, 19))
                    .fontSize(13)
                    .fontColor(record.isSelected ? Color.White : $r('app.color.app_text_primary'))
                    .fontWeight(FontWeight.Medium)
                  Text(record.end_time.slice(11, 19))
                    .fontSize(11)
                    .fontColor(record.isSelected ? Color.White : $r('app.color.app_text_secondary'))
                }
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .backgroundColor(record.isSelected ? $r('app.color.app_primary') : $r('app.color.app_card_bg'))
                .borderRadius(12)
                .shadow({ radius: 4, color: $r('app.color.app_shadow') })
                .onClick((): void => {
                  this.selectedRecordIndex = index;
                  this.playbackMode = 'history';
                  this.isLiveStream = false;
                  this.selectedMonitorUrl = this.buildHttpUrl(record.url.replace(BASE_HOST, '').split('?')[0]);
                  this.playbackOffsetSeconds = 0;
                  this.selectedTimeText = record.start_time;
                  this.jumpTimeText = this.formatDateTime(new Date(record.start_time));
                  for (let i = 0; i < this.timelineRecords.length; i++) {
                    this.timelineRecords[i].isSelected = i === index;
                  }
                })
              })
            }
            .padding({ left: 16, right: 16, bottom: 16 })
          }
          .width('100%')
          .height(86)
        }

      } else {
        Row() {
          Text('监控列表')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
            .layoutWeight(1)
          this.MonitorIconButton('add', Color.White, $r('app.color.app_primary'), (): void => {
            this.addMonitorDialogController.open();
          })
        }
        .width('90%')
        .padding({ top: 20, bottom: 10 })

        if (this.monitors.length === 0) {
          Column() {
            Text('暂无监控，请点击右上角添加')
              .fontSize(16)
              .fontColor($r('app.color.app_text_secondary'))
              .margin({ top: 80 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Center)
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
                      this.MonitorIconButton('save', Color.White, $r('app.color.app_primary'), (): void => {
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
                    Text(monitor.raw_stream_url || '未配置地址')
                      .fontSize(10)
                      .fontColor($r('app.color.app_text_secondary'))
                      .padding({ left: 8, right: 8 })
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row({ space: 10 }) {
                      Blank()
                      this.MonitorIconButton('open', Color.White, $r('app.color.app_primary'), (): void => {
                        this.openMonitor(monitor);
                      })
                      this.MonitorIconButton('edit', $r('app.color.app_text_primary'), $r('app.color.app_card_subtle_bg'), (): void => {
                        this.openEditMonitor(monitor);
                      })
                      this.MonitorIconButton('delete', Color.White, '#C00000', (): void => {
                        this.confirmDeleteMonitor(monitor);
                      })
                      Blank()
                    }
                    .width('100%')
                    .padding({ left: 8, right: 8, bottom: 8 })
                  }
                }
                .padding({ bottom: 8 })
                .backgroundColor($r('app.color.app_card_bg'))
                .borderRadius(10)
                .shadow({ radius: 5, color: $r('app.color.app_shadow') })
              }
            })
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .padding(10)
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
