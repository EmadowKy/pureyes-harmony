import { AppMotion } from '../../utils/appMotion';

@Component
export struct MotionStage {
  @Prop @Watch('reveal') sceneKey: string = '';
  @StorageLink('reduce_motion') @Watch('onMotionPreference') reduceMotion: boolean = false;
  @BuilderParam content: () => void = this.empty;
  @State private contentOpacity: number = 1;
  @State private contentOffset: number = 0;
  private frameTimer: number = 0;
  private visible: boolean = false;

  @Builder empty() {}

  aboutToAppear(): void {
    this.visible = true;
    this.reveal();
  }

  aboutToDisappear(): void {
    this.visible = false;
    if (this.frameTimer) clearTimeout(this.frameTimer);
    this.frameTimer = 0;
  }

  onMotionPreference(): void {
    if (this.reduceMotion) this.reveal();
  }

  reveal(): void {
    if (this.frameTimer) clearTimeout(this.frameTimer);
    this.frameTimer = 0;
    if (!this.visible || this.reduceMotion) {
      this.contentOpacity = 1;
      this.contentOffset = 0;
      return;
    }
    this.contentOpacity = 0.4;
    this.contentOffset = 12;
    this.frameTimer = setTimeout((): void => {
      this.frameTimer = 0;
      if (!this.visible) return;
      this.getUIContext().animateTo(AppMotion.options(280), (): void => {
        this.contentOpacity = 1;
        this.contentOffset = 0;
      });
    }, 16);
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .layoutWeight(1)
    .opacity(this.contentOpacity)
    .translate({ y: this.contentOffset })
  }
}
