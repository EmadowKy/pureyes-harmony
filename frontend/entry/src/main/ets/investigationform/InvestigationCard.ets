let storage = new LocalStorage();

@Entry(storage)
@Component
struct InvestigationCard {
  @LocalStorageProp('status') @Watch('onTaskChanged') status: string = 'idle';
  @LocalStorageProp('stage') stage: string = '等待调查';
  @LocalStorageProp('steps') steps: string = '0';
  @LocalStorageProp('title') title: string = '视频调查';
  @LocalStorageProp('elapsed') elapsed: string = '00:00';
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('workspaceId') workspaceId: string = '0';
  @LocalStorageProp('groupId') groupId: string = '0';
  @LocalStorageProp('conversationId') @Watch('onTaskChanged') conversationId: string = '';
  @LocalStorageProp('reduceMotion') @Watch('motionPreferenceChanged') reduceMotion: boolean = true;
  @State petLift: number = 0;
  @State petTilt: number = 0;
  private visible: boolean = false;
  private animationGeneration: number = 0;
  @LocalStorageProp('activeCount') runningCount: string = '0';
  @LocalStorageProp('completedCount') completedCount: string = '0';
  @LocalStorageProp('conversationCount') conversationCount: string = '0';
  @LocalStorageProp('taskPosition') taskPosition: string = '0';
  @LocalStorageProp('taskCount') taskCount: string = '0';

  aboutToAppear(): void { this.visible = true; }

  aboutToDisappear(): void { this.visible = false; this.animationGeneration++; }

  onTaskChanged(): void { this.greet(); }

  motionPreferenceChanged(): void {
    if (!this.reduceMotion) return;
    this.animationGeneration++;
    this.petLift = 0;
    this.petTilt = 0;
  }

  private greet(): void {
    if (!this.visible || this.reduceMotion) return;
    const generation = ++this.animationGeneration;
    animateTo({ duration: 320, curve: Curve.Friction, onFinish: (): void => {
      if (!this.visible || generation !== this.animationGeneration) return;
      animateTo({ duration: 260, curve: Curve.Friction }, (): void => {
        this.petLift = 0; this.petTilt = 0;
      });
    } }, (): void => {
      this.petLift = -3;
      this.petTilt = this.status === 'completed' ? 8 : -6;
    });
  }

  private interact(): void {
    this.greet();
    postCardAction(this, { action: 'message', params: { command: 'interact' } });
  }

  private command(value: string): void {
    postCardAction(this, { action: 'message', params: { command: value } });
  }

  private open(): void {
    postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: {
      fromInvestigationCard: 'true', workspaceId: this.workspaceId,
      groupId: this.groupId, conversationId: this.conversationId
    } });
  }

  private pet(): Resource {
    if (this.status === 'processing') return $r('app.media.investigation_owl_working');
    if (this.status === 'completed') return $r('app.media.investigation_owl_done');
    return $r('app.media.investigation_owl_idle');
  }

  private statusLabel(): string {
    if (this.status === 'processing') return `${this.runningCount} 项调查中`;
    if (this.status === 'failed') return '有调查未完成';
    if (this.status === 'stopped' || this.status === 'cancelled') return '调查已停止';
    if (this.status === 'completed') return '调查已完成';
    return '小鸮待命';
  }

  private statusAccent(): ResourceColor {
    if (this.status === 'processing') return $r('app.color.app_primary');
    if (this.status === 'failed') return $r('app.color.app_danger');
    if (this.status === 'completed') return $r('app.color.app_success');
    return $r('app.color.app_text_secondary');
  }

  private statusSoftBg(): ResourceColor {
    if (this.status === 'processing') return $r('app.color.app_primary_soft');
    if (this.status === 'failed') return $r('app.color.app_danger_soft');
    if (this.status === 'completed') return $r('app.color.app_success_soft');
    return $r('app.color.app_card_bg');
  }

  build() {
    Column({ space: 5 }) {
      // 1. 顶部品牌栏与胶囊刷新键
      Row({ space: 5 }) {
        Text('')
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.statusAccent())
        Text('清眸 · 小鸮')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .onClick((): void => this.interact())
          .accessibilityText('清眸小鸮，点击互动')
        Row() {
          Row() {
            Text('刷新')
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_primary'))
              .textAlign(TextAlign.Center)
          }
          .height(24)
          .padding({ left: 7, right: 7 })
          .borderRadius(9)
          .backgroundColor($r('app.color.app_primary_soft'))
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .onClick((): void => this.command('refresh'))
      }
      .width('100%')
      .height(24)
      .alignItems(VerticalAlign.Center)

      // 2. 中部 Bento 核心信息卡（点击进入对应工作区调查）
      Column() {
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Image(this.pet())
              .width(38)
              .height(38)
              .objectFit(ImageFit.Contain)
              .translate({ y: this.petLift })
              .rotate({ angle: this.petTilt })
              .onClick((): void => this.interact())
              .accessibilityText('小鸮，点击互动')
            Column({ space: 2 }) {
              Text(this.statusLabel())
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.statusAccent())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.taskCount !== '0' ? this.stage : `已完成 ${this.completedCount} 项`)
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.app_text_primary'))
                .maxLines(1)
                .width('100%')
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.taskCount !== '0' ? `${this.elapsed} · ${this.steps} 步` : `共 ${this.conversationCount} 场调查`)
                .fontSize(9)
                .fontFamily(this.runningCount !== '0' ? 'monospace' : '')
                .fontColor($r('app.color.app_text_secondary'))
                .width('100%')
                .maxLines(1)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .onClick((): void => this.open())
          }
          .width('100%')

          Row({ space: 5 }) {
            Text('')
              .width(3)
              .height(10)
              .borderRadius(1.5)
              .backgroundColor(this.statusAccent())
            Text(this.taskCount !== '0' ? this.title : '选择视频，让小鸮帮你找线索')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .onClick((): void => this.open())
        }
        .width('100%')
        .height('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .backgroundColor(this.statusSoftBg())
        .border({ width: 0.5, color: $r('app.color.app_border') })
        .borderRadius(14)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .layoutWeight(1)

      // 3. 底部胶囊控制栏
      Row({ space: 4 }) {
        if (Number(this.taskCount) > 1) {
          Row() {
            Row() {
              Text('‹')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_primary'))
                .textAlign(TextAlign.Center)
            }
            .width(28)
            .height(26)
            .borderRadius(9)
            .backgroundColor($r('app.color.app_card_subtle_bg'))
            .border({ width: 0.5, color: $r('app.color.app_border') })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
          .onClick((): void => this.command('previous'))
          Text(`${this.taskPosition} / ${this.taskCount}${this.updatedAt ? ' · ' + this.updatedAt : ''}`)
            .fontSize(9)
            .fontColor($r('app.color.app_text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
          Row() {
            Row() {
              Text('›')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_primary'))
                .textAlign(TextAlign.Center)
            }
            .width(28)
            .height(26)
            .borderRadius(9)
            .backgroundColor($r('app.color.app_card_subtle_bg'))
            .border({ width: 0.5, color: $r('app.color.app_border') })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
          .onClick((): void => this.command('next'))
        } else {
          Text(this.updatedAt ? `同步 ${this.updatedAt}` : '打开清眸开始调查')
            .fontSize(9)
            .fontColor($r('app.color.app_text_muted'))
            .layoutWeight(1)
            .maxLines(1)
          Row() {
            Row() {
              Text('查看 ↗')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_primary'))
            }
            .height(26)
            .padding({ left: 7, right: 7 })
            .borderRadius(9)
            .backgroundColor($r('app.color.app_primary_soft'))
          }
          .onClick((): void => this.open())
        }
      }
      .width('100%')
      .height(26)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.app_card_bg'))
    .border({ width: 1, color: $r('app.color.app_border') })
    .borderRadius(22)
  }
}
