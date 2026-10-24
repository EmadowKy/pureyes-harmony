import { common } from '@kit.AbilityKit';

@Entry({ useSharedStorage: true })
@Component
struct InvestigationLiveCard {
  @LocalStorageProp('status') status: string = 'idle';
  @LocalStorageProp('stage') stage: string = '等待调查';
  @LocalStorageProp('title') title: string = '视频调查';
  @LocalStorageProp('elapsed') elapsed: string = '00:00';
  @LocalStorageProp('steps') steps: string = '0';
  @LocalStorageProp('workspaceId') workspaceId: string = '0';
  @LocalStorageProp('groupId') groupId: string = '0';
  @LocalStorageProp('conversationId') conversationId: string = '';
  @LocalStorageProp('reduceMotion') reduceMotion: boolean = true;
  @State lift: number = 0;
  @State tilt: number = 0;
  @State petScale: number = 1;
  @State hint: string = '';
  private timer: number = 0;
  private visible: boolean = false;

  aboutToAppear(): void {
    this.visible = true;
    if (this.reduceMotion) return;
    this.timer = setTimeout((): void => {
      this.timer = 0;
      this.bounce();
    }, 32);
  }

  aboutToDisappear(): void {
    this.visible = false;
    if (this.timer) clearTimeout(this.timer);
    this.timer = 0;
  }

  private bounce(): void {
    if (!this.visible || this.reduceMotion) return;
    this.getUIContext().animateTo({ duration: 420, curve: Curve.Friction, onFinish: (): void => {
      if (!this.visible) return;
      this.getUIContext().animateTo({ duration: 360, curve: Curve.Friction }, (): void => {
        this.lift = 0; this.tilt = 0; this.petScale = 1;
      });
    } }, (): void => {
      this.lift = -8;
      this.tilt = this.status === 'completed' ? 8 : -6;
      this.petScale = 1.08;
    });
  }

  private pet(): Resource {
    if (this.status === 'processing') return $r('app.media.investigation_owl_working');
    if (this.status === 'completed') return $r('app.media.investigation_owl_done');
    return $r('app.media.investigation_owl_idle');
  }

  private open(): void {
    const context = this.getUIContext().getHostContext() as common.LiveFormExtensionContext;
    context.startAbilityByLiveForm({ bundleName: context.applicationInfo.name, abilityName: 'EntryAbility',
      parameters: { fromInvestigationCard: 'true', workspaceId: this.workspaceId,
        groupId: this.groupId, conversationId: this.conversationId } }).catch((): void => {
      this.hint = '请从卡片查看调查';
    });
  }

  build() {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Image(this.pet())
          .width(64).height(64).objectFit(ImageFit.Contain)
          .translate({ y: this.lift }).rotate({ angle: this.tilt })
          .scale({ x: this.petScale, y: this.petScale })
          .onClick((): void => this.bounce())
          .accessibilityText('小鸮，点击互动')
        Column({ space: 4 }) {
          Text(this.status === 'completed' ? '线索已整理' : (this.status === 'processing' ? '正在帮你找线索' : '小鸮在这里'))
            .fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_primary')).maxLines(1)
          Text(this.stage).fontSize(10).fontColor($r('app.color.app_text_primary')).maxLines(1)
          Text(`${this.elapsed} · ${this.steps} 步`).fontSize(10).fontColor($r('app.color.app_text_secondary')).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Text(this.title).fontSize(10).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('app.color.app_text_primary')).width('100%')
      Row() {
        Text(this.hint || '点击小鸮互动').fontSize(9).fontColor($r('app.color.app_text_muted')).layoutWeight(1)
        Button('查看调查').fontSize(10).height(28).onClick((): void => this.open())
      }.width('100%')
    }
    .width('100%').height('100%').padding(12)
    .justifyContent(FlexAlign.SpaceAround)
    .borderRadius(22).backgroundColor($r('app.color.app_card_bg'))
    .border({ width: 1, color: $r('app.color.app_border') })
  }
}
