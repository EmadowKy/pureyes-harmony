let storage = new LocalStorage();

@Entry(storage)
@Component
struct InvestigationCard {
  @LocalStorageProp('status') status: string = 'idle';
  @LocalStorageProp('stage') stage: string = '等待调查';
  @LocalStorageProp('steps') steps: string = '0';
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('workspaceId') workspaceId: string = '0';
  @LocalStorageProp('conversationId') conversationId: string = '';

  private statusLabel(): string {
    if (this.status === 'processing') return '调查中';
    if (this.status === 'completed') return '调查已完成';
    if (this.status === 'failed') return '调查未完成';
    if (this.status === 'stopped') return '调查已停止';
    return '继续视频调查';
  }

  private detailLabel(): string {
    if (this.status === 'idle') return '打开工作区，查看调查记录';
    return this.stage || '查看调查记录';
  }

  private stepLabel(): string {
    if (this.status === 'idle' || this.steps === '0') return '多视频工作区';
    return `${this.steps} 步工具记录`;
  }

  build() {
    FormLink({
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        fromInvestigationCard: 'true',
        workspaceId: this.workspaceId,
        conversationId: this.conversationId
      }
    }) {
      Column() {
        Row({ space: 7 }) {
          Row() {
            Text('清')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
          .width(25)
          .height(25)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#2459B8')
          .borderRadius(8)

          Text('清眸')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0C2942')
            .layoutWeight(1)

          Text('视频调查')
            .fontSize(10)
            .fontColor('#6B82A0')
        }
        .width('100%')

        Text(this.statusLabel())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0C2942')
          .maxLines(1)
          .margin({ top: 13 })

        Text(this.detailLabel())
          .fontSize(11)
          .fontColor('#667A91')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })

        Blank()

        Row() {
          Text(this.stepLabel())
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#2459B8')
            .layoutWeight(1)
            .maxLines(1)
          Text('↗')
            .fontSize(15)
            .fontColor('#2459B8')
        }
        .width('100%')
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor('#EDF4FF')
        .borderRadius(9)

        Text(this.updatedAt ? `最近同步 ${this.updatedAt}` : '点击打开清眸')
          .fontSize(10)
          .fontColor('#8798AC')
          .margin({ top: 6 })
      }
      .width('100%')
      .height('100%')
      .padding(13)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#DFE8F4' })
      .borderRadius(20)
    }
  }
}
