import { renewMediaUrl } from '../../utils/mediaAccess';
import { FullscreenSegmentVideo } from './FullscreenSegmentVideo';

@Component
export struct RenewableVideo {
  @Prop @Watch('onSourceChanged') source: string = '';
  @Prop @Watch('seekToRequestedPosition') initialSeconds: number = 0;
  @Prop @Watch('seekToRequestedPosition') seekRevision: number = 0;
  @Prop autoPlay: boolean = true;
  onPosition: (seconds: number) => void = (_seconds: number): void => {};
  controller: VideoController = new VideoController();
  @State playbackUrl: string = '';
  @State errorText: string = '';
  @State private fullscreen: boolean = false;
  private playbackSeconds: number = 0;
  private retryCount: number = 0;
  private refreshing: boolean = false;
  private active: boolean = false;
  private refreshTimer: number = 0;
  private prepared: boolean = false;
  private addressEpoch: number = 0;
  private seekTimer: number = 0;
  private fullscreenReturnSeconds: number = -1;

  private onSourceChanged(): void {
    clearTimeout(this.seekTimer);
    this.addressEpoch++;
    this.refreshing = false;
    this.prepared = false;
    this.retryCount = 0;
    this.playbackSeconds = Math.max(0, this.initialSeconds);
    this.playbackUrl = '';
    this.errorText = '';
    this.refreshAddress();
  }

  private seekToRequestedPosition(): void {
    this.playbackSeconds = Number.isFinite(this.initialSeconds) ? Math.max(0, this.initialSeconds) : 0;
    this.scheduleSeek(this.seekRevision > 0);
  }

  private scheduleSeek(resume: boolean): void {
    clearTimeout(this.seekTimer);
    const epoch = this.addressEpoch;
    const seconds = this.playbackSeconds;
    // Prop watchers and onPrepared run before the native Video update completes.
    // Issue controller commands after that update, including repeated same-time seeks.
    this.seekTimer = setTimeout((): void => {
      this.seekTimer = 0;
      if (!this.active || !this.prepared || this.fullscreen || epoch !== this.addressEpoch) return;
      this.controller.setCurrentTime(seconds, SeekMode.Accurate);
      if (resume) this.controller.start();
    }, 32);
  }

  aboutToAppear(): void {
    this.active = true;
    this.playbackSeconds = this.initialSeconds;
    this.refreshAddress();
    // Long-running playback must also renew before the two-hour token deadline.
    this.refreshTimer = setInterval((): void => { this.refreshAddress(); }, 3600000);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.addressEpoch++;
    this.prepared = false;
    clearInterval(this.refreshTimer);
    clearTimeout(this.seekTimer);
  }

  async refreshAddress(): Promise<void> {
    if (this.refreshing || !this.active) return;
    this.refreshing = true;
    const epoch = ++this.addressEpoch;
    const source = this.source;
    try {
      const url = await renewMediaUrl(source);
      if (!this.active || epoch !== this.addressEpoch) return;
      this.prepared = false;
      this.playbackUrl = url;
      this.errorText = '';
    } catch (error) {
      if (this.active && epoch === this.addressEpoch) this.errorText = '视频加载失败，请检查网络或登录状态后重试';
    } finally {
      if (epoch === this.addressEpoch) this.refreshing = false;
    }
  }

  recover(): void {
    if (this.refreshing) return;
    if (this.retryCount >= 1) {
      this.errorText = '视频加载失败，请检查网络或登录状态后重试';
      return;
    }
    this.retryCount += 1;
    this.refreshAddress();
  }

  @Builder fullscreenPlayer() {
    FullscreenSegmentVideo({
      source: this.playbackUrl,
      initialSeconds: this.playbackSeconds,
      onPosition: (seconds: number): void => { this.playbackSeconds = seconds; this.onPosition(seconds); },
      onClose: (seconds: number): void => {
        this.playbackSeconds = seconds;
        this.fullscreenReturnSeconds = seconds;
        this.onPosition(seconds);
        this.fullscreen = false;
      }
    })
  }

  build() {
    Stack() {
      if (this.playbackUrl) {
        Video({ src: this.playbackUrl, controller: this.controller })
          .width('100%').height('100%').autoPlay(this.autoPlay && !this.fullscreen).controls(true)
          .objectFit(ImageFit.Contain)
          .onFullscreenChange((event): void => {
            if (event.fullscreen) {
              this.controller.exitFullscreen();
              this.controller.pause();
              this.fullscreen = true;
            }
          })
          .onPrepared((): void => {
            if (!this.active) return;
            this.prepared = true;
            this.scheduleSeek(this.autoPlay);
          })
          .onStart((): void => { if (this.fullscreen) this.controller.pause(); })
          .onUpdate((event): void => {
            if (this.active && this.prepared && !this.fullscreen) {
              this.playbackSeconds = event.time;
              this.onPosition(event.time);
            }
          })
          .onError((): void => { this.recover(); })
      }
      if (this.errorText) {
        Column({ space: 8 }) {
          Text(this.errorText).fontColor(Color.White).fontSize(12)
          Button('重试').onClick((): void => {
            this.retryCount = 0;
            this.refreshAddress();
          })
        }.padding(12).width('100%').height('100%')
          .justifyContent(FlexAlign.Center).backgroundColor(Color.Black)
      }
    }.width('100%').height('100%').backgroundColor(Color.Black)
      .bindContentCover($$this.fullscreen, this.fullscreenPlayer(), {
        modalTransition: ModalTransition.NONE,
        onDisappear: (): void => {
          if (this.active) {
            if (this.fullscreenReturnSeconds >= 0) {
              this.playbackSeconds = this.fullscreenReturnSeconds;
              this.fullscreenReturnSeconds = -1;
            }
            this.scheduleSeek(true);
          }
        }
      })
  }
}
