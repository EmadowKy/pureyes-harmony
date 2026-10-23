import { InvestigationFloat } from '../utils/investigationFloat';
import { InvestigationFloatSnapshot, floatStatusLabel } from '../utils/investigationFloatState';

@Entry({ useSharedStorage: true })
@Component
struct InvestigationFloatWindow {
  @LocalStorageLink('floatTask') task: InvestigationFloatSnapshot = new InvestigationFloatSnapshot();
  @StorageLink('access_token') token: string = '';

  private accent(): ResourceColor {
    if (this.task.stale) return $r('app.color.app_text_muted');
    if (this.task.status === 'completed') return $r('app.color.app_success');
    if (this.task.status === 'failed') return $r('app.color.app_danger');
    return $r('app.color.app_primary');
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Image($r('app.media.app_icon')).width(25).height(25).objectFit(ImageFit.Contain)
          Text('清眸调查').fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary')).layoutWeight(1)
          Text(this.token ? this.task.position : '').fontSize(11).fontColor($r('app.color.app_text_muted'))
        }.width('100%')
        if (this.token) {
          Row({ space: 6 }) {
            Text('').width(6).height(6).borderRadius(3).backgroundColor(this.accent())
            Text(this.task.taskId ? floatStatusLabel(this.task.status) : this.task.stage)
              .fontSize(12).fontColor(this.accent()).maxLines(1)
          }.width('100%')
          if (this.task.taskId) {
            Text(this.task.stage).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary')).width('100%').maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row() {
              Text(`工具 ${this.task.steps} 步`).fontSize(12).fontColor($r('app.color.app_text_secondary')).layoutWeight(1)
              Text(this.task.duration).fontSize(20).fontWeight(FontWeight.Medium)
                .fontFamily('monospace').fontColor($r('app.color.app_text_primary'))
            }.width('100%')
          } else {
            Text(this.task.hasSnapshot ? '发起视频调查后，在这里查看进度。' : '正在获取最近的调查任务。')
              .fontSize(12).fontColor($r('app.color.app_text_secondary')).width('100%')
          }
          if (this.task.stale) {
            Text(this.task.hasSnapshot ? '同步中断 · 显示上次进度' : '等待任务同步')
              .fontSize(11).fontColor($r('app.color.app_text_muted')).width('100%')
          }
          if (this.task.hint) {
            Text(this.task.hint).fontSize(11).fontColor($r('app.color.app_danger')).width('100%')
          }
          Row({ space: 6 }) {
            if (this.task.taskCount > 1) {
              Button('上一项').fontSize(11).height(34).padding({ left: 9, right: 9 })
                .backgroundColor($r('app.color.app_card_subtle_bg')).fontColor($r('app.color.app_text_secondary'))
                .accessibilityText('切换到上一项调查').onClick((): void => InvestigationFloat.cycle(-1))
              Button('下一项').fontSize(11).height(34).padding({ left: 9, right: 9 })
                .backgroundColor($r('app.color.app_card_subtle_bg')).fontColor($r('app.color.app_text_secondary'))
                .accessibilityText('切换到下一项调查').onClick((): void => InvestigationFloat.cycle(1))
            }
            Button(this.task.taskId ? '查看' : '打开应用').fontSize(12).height(34).layoutWeight(1)
              .backgroundColor($r('app.color.app_primary_soft')).fontColor($r('app.color.app_primary'))
              .accessibilityText('返回清眸查看调查详情')
              .onClick((): void => { InvestigationFloat.returnToInvestigation(); })
          }.width('100%')
        } else {
          Text('请返回清眸登录').fontSize(13).fontColor($r('app.color.app_text_secondary'))
        }
      }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.app_card_bg'))
      .scrollBar(BarState.Auto)
  }
}
