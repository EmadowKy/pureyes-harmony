import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

@Component
export struct FullscreenSegmentVideo {
  source: string = '';
  initialSeconds: number = 0;
  onClose: (seconds: number) => void = (_seconds: number): void => {};
  onPosition: (seconds: number) => void = (_seconds: number): void => {};
  private controller: VideoController = new VideoController();
  @State private seconds: number = 0;
  @State private duration: number = 0;
  @State private playing: boolean = true;
  @State private scaleValue: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private errorText: string = '';
  private baseScale: number = 1;
  private baseX: number = 0;
  private baseY: number = 0;
  private widthValue: number = 0;
  private heightValue: number = 0;
  private active: boolean = false;
  private orientationTask: Promise<void> = Promise.resolve();
  private playerWindow: window.Window | undefined = undefined;
  private previousOrientation: window.Orientation = window.Orientation.PORTRAIT;

  aboutToAppear(): void {
    this.active = true;
    this.seconds = this.initialSeconds;
    this.orientationTask = this.enterLandscape();
  }

  private async enterLandscape(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      if (!this.active) return;
      this.playerWindow = win;
      this.previousOrientation = win.getPreferredOrientation();
      await win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
    } catch (_error) {
      this.errorText = '无法自动旋转，请检查设备方向设置';
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.orientationTask.then(async (): Promise<void> => {
      if (this.playerWindow) await this.playerWindow.setPreferredOrientation(this.previousOrientation);
    }).catch((): void => {});
  }

  private resetView(): void {
    this.scaleValue = 1;
    this.offsetX = 0;
    this.offsetY = 0;
  }

  private constrainOffset(): void {
    const maxX = this.widthValue * (this.scaleValue - 1) / 2;
    const maxY = this.heightValue * (this.scaleValue - 1) / 2;
    this.offsetX = Math.max(-maxX, Math.min(maxX, this.offsetX));
    this.offsetY = Math.max(-maxY, Math.min(maxY, this.offsetY));
  }

  private timeText(value: number): string {
    const total = Math.max(0, Math.floor(value));
    return `${Math.floor(total / 60)}:${(total % 60).toString().padStart(2, '0')}`;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack() {
        Video({ src: this.source, controller: this.controller })
          .width('100%').height('100%').objectFit(ImageFit.Contain)
          .autoPlay(true).controls(false)
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
          .onPrepared((event): void => {
            this.duration = event.duration;
            if (this.initialSeconds > 0) this.controller.setCurrentTime(this.initialSeconds);
          })
          .onStart((): void => { this.playing = true; this.errorText = ''; })
          .onPause((): void => { this.playing = false; })
          .onFinish((): void => { this.playing = false; })
          .onUpdate((event): void => {
            this.seconds = event.time; this.onPosition(this.seconds); this.errorText = '';
          })
          .onError((): void => { this.errorText = '视频暂时无法播放，请返回后重试'; })
      }.width('100%').height('100%').clip(true)
        .onAreaChange((_oldArea: Area, area: Area): void => {
          this.widthValue = Number(area.width); this.heightValue = Number(area.height);
          this.constrainOffset();
        })
        .gesture(GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart((): void => { this.baseScale = this.scaleValue; })
            .onActionUpdate((event: GestureEvent): void => {
              this.scaleValue = Math.max(1, Math.min(5, this.baseScale * event.scale));
              this.constrainOffset();
            }),
          PanGesture({ fingers: 2 })
            .onActionStart((): void => { this.baseX = this.offsetX; this.baseY = this.offsetY; })
            .onActionUpdate((event: GestureEvent): void => {
              this.offsetX = this.baseX + event.offsetX;
              this.offsetY = this.baseY + event.offsetY;
              this.constrainOffset();
            })
        ))
      Column({ space: 6 }) {
        Row({ space: 12 }) {
          Button('返回').onClick((): void => { this.onClose(this.seconds); })
          Text('双指缩放 / 移动').fontColor(Color.White).fontSize(12).layoutWeight(1)
          Button('复位').onClick((): void => { this.resetView(); })
        }.width('100%')
        Blank()
        if (this.errorText) {
          Text(this.errorText).fontColor(Color.White).fontSize(12)
        }
        Row({ space: 10 }) {
          Button(this.playing ? '暂停' : '播放').onClick((): void => {
            if (this.playing) this.controller.pause(); else this.controller.start();
          })
          Text(this.timeText(this.seconds)).fontColor(Color.White).fontSize(12)
          Slider({ value: this.seconds, min: 0, max: Math.max(1, this.duration), step: 1 })
            .layoutWeight(1).onChange((value: number, mode: SliderChangeMode): void => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.controller.setCurrentTime(value); this.seconds = value;
              }
            })
          Text(this.timeText(this.duration)).fontColor(Color.White).fontSize(12)
        }.width('100%').padding(8).backgroundColor('#99000000')
      }.width('100%').height('100%').padding(16)
    }.width('100%').height('100%').backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
