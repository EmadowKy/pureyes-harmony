let storage = new LocalStorage();

@Entry(storage)
@Component
struct InvestigationCard {
  @LocalStorageProp('status') status: string = 'idle';
  @LocalStorageProp('stage') stage: string = '等待调查';
  @LocalStorageProp('steps') steps: string = '0';
  @LocalStorageProp('title') title: string = '视频调查';
  @LocalStorageProp('elapsed') elapsed: string = '00:00';
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('workspaceId') workspaceId: string = '0';
  @LocalStorageProp('groupId') groupId: string = '0';
  @LocalStorageProp('conversationId') conversationId: string = '';
  @LocalStorageProp('activeCount') runningCount: string = '0';
  @LocalStorageProp('completedCount') completedCount: string = '0';
  @LocalStorageProp('conversationCount') conversationCount: string = '0';
  @LocalStorageProp('taskPosition') taskPosition: string = '0';
  @LocalStorageProp('taskCount') taskCount: string = '0';

  private pet(): Resource {
    if (this.runningCount !== '0') return $r('app.media.investigation_owl_working');
    if (this.status === 'completed') return $r('app.media.investigation_owl_done');
    return $r('app.media.investigation_owl_idle');
  }
  private statusLabel(): string {
    if (this.runningCount !== '0') return `${this.runningCount} 项调查中`;
    if (this.status === 'failed') return '有调查未完成';
    if (this.status === 'completed') return '调查已完成';
    return '小鸮待命';
  }
  build() {
    Column({ space: 4 }) {
      Row() {
        Text('清眸 · 小鸮').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#203D54').layoutWeight(1)
        FormLink({ action: 'message', params: { command: 'refresh' } }) {
          Text('↻').fontSize(18).fontColor('#7392AD').width(28).height(28).textAlign(TextAlign.Center)
        }
      }.width('100%')
      FormLink({ action: 'router', abilityName: 'EntryAbility', params: {
        fromInvestigationCard: 'true', workspaceId: this.workspaceId, groupId: this.groupId, conversationId: this.conversationId
      } }) {
        Column({ space: 3 }) {
          Row({ space: 8 }) {
            Image(this.pet()).width(64).height(64).objectFit(ImageFit.Contain)
            Column({ space: 5 }) {
              Text(this.statusLabel()).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#203D54').maxLines(1)
              Text(this.runningCount !== '0' ? this.stage : `已完成 ${this.completedCount} 项`)
                .fontSize(11).fontColor('#667A91').maxLines(2)
              Text(this.runningCount !== '0' ? `${this.elapsed} · ${this.steps} 步` : `共 ${this.conversationCount} 场调查`)
                .fontSize(10).fontColor('#2D9A8D').maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
          Text(this.taskCount !== '0' ? this.title : '选择视频，让小鸮帮你找线索')
            .fontSize(11).fontColor('#203D54').width('100%').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%')
      }
      Blank()
      Row() {
        if (Number(this.taskCount) > 1) {
          FormLink({ action: 'message', params: { command: 'previous' } }) {
            Text('‹').fontSize(20).width(30).height(28).textAlign(TextAlign.Center).fontColor('#203D54')
          }
          Text(`${this.taskPosition} / ${this.taskCount} · ${this.updatedAt}`).fontSize(10).fontColor('#667A91').layoutWeight(1).textAlign(TextAlign.Center)
          FormLink({ action: 'message', params: { command: 'next' } }) {
            Text('›').fontSize(20).width(30).height(28).textAlign(TextAlign.Center).fontColor('#203D54')
          }
        } else {
          Text(this.updatedAt ? `同步 ${this.updatedAt}` : '打开清眸开始调查').fontSize(10).fontColor('#7392AD').layoutWeight(1)
          Text('查看 ↗').fontSize(10).fontColor('#203D54')
        }
      }.width('100%').height(28)
    }.width('100%').height('100%').padding(12)
      .alignItems(HorizontalAlign.Start).backgroundColor('#F2F7FA').borderRadius(20)
  }
}
