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
  @State private playerGeneration: number = 0;
  @State private fullscreen: boolean = false;
  private playbackSeconds: number = 0;
  private retryCount: number = 0;
  private refreshing: boolean = false;
  private active: boolean = false;
  private refreshTimer: number = 0;
  private prepared: boolean = false;
  private addressEpoch: number = 0;
  private seekTimer: number = 0;
  private inlinePlaying: boolean = false;
  private inlineCompleted: boolean = false;
  private fullscreenSeconds: number = 0;
  private fullscreenPlaying: boolean = false;
  private fullscreenOpen: boolean = false;
  private resumeOnPrepare: boolean | undefined;

  private onSourceChanged(): void {
    clearTimeout(this.seekTimer);
    this.addressEpoch++;
    this.refreshing = false;
    this.prepared = false;
    this.inlinePlaying = false;
    this.inlineCompleted = false;
    this.resumeOnPrepare = undefined;
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
      if (this.inlineCompleted) {
        // A completed native player can seek to a frame without leaving the completed state.
        this.prepared = false;
        this.inlineCompleted = false;
        this.playbackSeconds = seconds;
        this.resumeOnPrepare = resume;
        this.playerGeneration++;
        return;
      }
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
      if (this.playbackUrl !== url) {
        if (this.prepared) this.resumeOnPrepare = this.inlinePlaying;
        this.prepared = false;
        this.inlineCompleted = false;
        this.playbackUrl = url;
      }
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

  private restoreInlinePlayback(): void {
    if (!this.active || !this.fullscreenOpen) return;
    this.fullscreenOpen = false;
    this.fullscreen = false;
    this.playbackSeconds = this.fullscreenSeconds;
    this.onPosition(this.playbackSeconds);
    if (this.prepared) this.scheduleSeek(this.fullscreenPlaying);
    else this.resumeOnPrepare = this.fullscreenPlaying;
  }

  @Builder fullscreenPlayer() {
    FullscreenSegmentVideo({
      source: this.playbackUrl,
      initialSeconds: this.fullscreenSeconds,
      initialPlaying: this.fullscreenPlaying,
      onPosition: (seconds: number): void => { this.fullscreenSeconds = seconds; this.onPosition(seconds); },
      onPlayingChange: (playing: boolean): void => { this.fullscreenPlaying = playing; },
      onClose: (seconds: number): void => {
        this.fullscreenSeconds = seconds;
        this.fullscreen = false;
      }
    })
  }

  build() {
    Stack() {
      if (this.playbackUrl) {
        ForEach([this.playerGeneration], (generation: number): void => {
          Video({ src: this.playbackUrl, controller: this.controller })
            .width('100%').height('100%').autoPlay(false).controls(true)
            .objectFit(ImageFit.Contain)
            .onFullscreenChange((event): void => {
              if (generation === this.playerGeneration && event.fullscreen && !this.fullscreenOpen) {
                this.fullscreenSeconds = this.playbackSeconds;
                this.fullscreenPlaying = this.inlinePlaying;
                this.fullscreenOpen = true;
                this.controller.exitFullscreen();
                this.controller.pause();
                this.fullscreen = true;
              }
            })
            .onPrepared((): void => {
              if (!this.active || generation !== this.playerGeneration) return;
              this.prepared = true;
              if (!this.fullscreenOpen) {
                this.scheduleSeek(this.resumeOnPrepare ?? this.autoPlay);
                this.resumeOnPrepare = undefined;
              }
            })
            .onStart((): void => {
              if (generation !== this.playerGeneration) return;
              if (this.fullscreenOpen) this.controller.pause();
              else {
                this.inlinePlaying = true;
                this.inlineCompleted = false;
              }
            })
            .onPause((): void => {
              if (generation === this.playerGeneration) this.inlinePlaying = false;
            })
            .onFinish((): void => {
              if (generation !== this.playerGeneration) return;
              this.inlinePlaying = false;
              this.inlineCompleted = true;
            })
            .onUpdate((event): void => {
              if (generation === this.playerGeneration && this.active && this.prepared && !this.fullscreenOpen) {
                this.playbackSeconds = event.time;
                this.onPosition(event.time);
              }
            })
            .onError((): void => {
              if (generation === this.playerGeneration) this.recover();
            })
        }, (generation: number): string => generation.toString())
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
        onDisappear: (): void => { this.restoreInlinePlayback(); }
      })
  }
}
