import { renewMediaUrl } from '../../utils/mediaAccess';
import { FullscreenSegmentVideo } from './FullscreenSegmentVideo';

@Component
export struct RenewableVideo {
  source: string = '';
  initialSeconds: number = 0;
  controller: VideoController = new VideoController();
  @State playbackUrl: string = '';
  @State errorText: string = '';
  @State private fullscreen: boolean = false;
  private playbackSeconds: number = 0;
  private retryCount: number = 0;
  private refreshing: boolean = false;
  private active: boolean = false;
  private refreshTimer: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.playbackSeconds = this.initialSeconds;
    this.refreshAddress();
    // Long-running playback must also renew before the two-hour token deadline.
    this.refreshTimer = setInterval((): void => { this.refreshAddress(); }, 3600000);
  }

  aboutToDisappear(): void {
    this.active = false;
    clearInterval(this.refreshTimer);
  }

  async refreshAddress(): Promise<void> {
    if (this.refreshing || !this.active) return;
    this.refreshing = true;
    try {
      const url = await renewMediaUrl(this.source);
      if (!this.active) return;
      this.playbackUrl = url;
      this.errorText = '';
    } catch (error) {
      if (this.active) this.errorText = '视频加载失败，请检查网络或登录状态后重试';
    } finally {
      this.refreshing = false;
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
      onPosition: (seconds: number): void => { this.playbackSeconds = seconds; },
      onClose: (seconds: number): void => {
        this.playbackSeconds = seconds;
        this.fullscreen = false;
      }
    })
  }

  build() {
    Stack() {
      if (this.playbackUrl) {
        Video({ src: this.playbackUrl, controller: this.controller })
          .width('100%').height('100%').autoPlay(!this.fullscreen).controls(true)
          .objectFit(ImageFit.Contain)
          .onFullscreenChange((event): void => {
            if (event.fullscreen) {
              this.controller.exitFullscreen();
              this.controller.pause();
              this.fullscreen = true;
            }
          })
          .onPrepared((): void => {
            if (this.playbackSeconds > 0) this.controller.setCurrentTime(this.playbackSeconds);
          })
          .onStart((): void => { if (this.fullscreen) this.controller.pause(); })
          .onUpdate((event): void => {
            if (!this.fullscreen) this.playbackSeconds = event.time;
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
            this.controller.setCurrentTime(this.playbackSeconds);
            this.controller.start();
          }
        }
      })
  }
}
