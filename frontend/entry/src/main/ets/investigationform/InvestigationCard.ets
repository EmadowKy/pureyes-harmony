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
    if (this.status === 'processing') return '调查进行中';
    if (this.status === 'completed') return '调查已完成';
    if (this.status === 'failed') return '调查未完成';
    if (this.status === 'stopped') return '调查已停止';
    return '打开清眸开始调查';
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
      Column({ space: 11 }) {
        Row({ space: 8 }) {
          Text('✦').fontSize(18).fontColor('#D7E7FF')
          Text('清眸 · 多视频调查')
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
            .layoutWeight(1)
        }
        .width('100%')

        Text(this.statusLabel())
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
        Text(this.status === 'idle' ? '查看工作区和调查记录' :
          `${this.stage} · ${this.steps} 个步骤`)
          .fontSize(12)
          .fontColor('#DFECFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(this.updatedAt ? `上次同步 ${this.updatedAt}` : '等待首次同步')
            .fontSize(10).fontColor('#BED6FA')
            .layoutWeight(1)
          Text('打开 ↗').fontSize(11).fontColor('#FFFFFF')
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#17458B')
      .borderRadius(18)
    }
  }
}
