import { InvestigationFloat } from '../utils/investigationFloat';
import { InvestigationFloatSnapshot, floatStatusLabel, floatMotionKey } from '../utils/investigationFloatState';
import { MotionStage } from './components/MotionStage';
import { AppMotion } from '../utils/appMotion';

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

  private accentSoft(): ResourceColor {
    if (this.task.stale) return $r('app.color.app_card_subtle_bg');
    if (this.task.status === 'completed') return $r('app.color.app_success_soft');
    if (this.task.status === 'failed') return $r('app.color.app_danger_soft');
    return $r('app.color.app_primary_soft');
  }

  private pet(): Resource {
    if (this.task.stale) return $r('app.media.investigation_owl_idle');
    if (this.task.status === 'processing') return $r('app.media.investigation_owl_working');
    if (this.task.status === 'completed') return $r('app.media.investigation_owl_done');
    return $r('app.media.investigation_owl_idle');
  }

  build() {
    Scroll() {
      Column({ space: 7 }) {
        // 1. 顶部 HUD 状态头栏
        Row({ space: 7 }) {
          Image(this.pet())
            .width(26)
            .height(26)
            .objectFit(ImageFit.Contain)
          Column({ space: 1 }) {
            Text('清眸调查')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
              .maxLines(1)
            if (this.token) {
              Row({ space: 4 }) {
                Text('')
                  .width(5)
                  .height(5)
                  .borderRadius(2.5)
                  .backgroundColor(this.accent())
                Text(this.task.stale ? '等待同步' : this.task.taskId ? floatStatusLabel(this.task.status) : this.task.stage)
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.accent())
                  .maxLines(1)
              }
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.token && this.task.position) {
            Row() {
              Text(this.task.position)
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.app_text_secondary'))
            }
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(9)
            .backgroundColor($r('app.color.app_card_subtle_bg'))
            .border({ width: 0.5, color: $r('app.color.app_border') })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.token) {
          // 2. 核心调查仪表盘卡片
          if (this.task.taskId) {
            MotionStage({ sceneKey: floatMotionKey(this.task), fillAvailable: false, distance: 6 }) {
            Column({ space: 6 }) {
              Text(this.task.stage)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_text_primary'))
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text('工具进度')
                    .fontSize(10)
                    .fontColor($r('app.color.app_text_muted'))
                  Text(`工具 ${this.task.steps} 步`)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                    .maxLines(1)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                .backgroundColor($r('app.color.app_card_bg'))
                .border({ width: 0.5, color: $r('app.color.app_border') })
                .borderRadius(10)

                Column({ space: 2 }) {
                  Text('调查用时')
                    .fontSize(10)
                    .fontColor($r('app.color.app_text_muted'))
                  Text(this.task.duration)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                    .fontColor(this.accent())
                    .maxLines(1)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                .backgroundColor($r('app.color.app_card_bg'))
                .border({ width: 0.5, color: $r('app.color.app_border') })
                .borderRadius(10)
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 9, right: 9, top: 7, bottom: 7 })
            .backgroundColor(this.accentSoft())
            .border({ width: 0.5, color: $r('app.color.app_border') })
            .borderRadius(13)
            }
          } else {
            Column({ space: 4 }) {
              Text(this.task.hasSnapshot ? '发起视频调查后，在这里查看进度。' : '正在获取最近的调查任务。')
                .fontSize(12)
                .fontColor($r('app.color.app_text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding(10)
            .backgroundColor($r('app.color.app_card_subtle_bg'))
            .border({ width: 0.5, color: $r('app.color.app_border') })
            .borderRadius(12)
          }

          // 3. 同步中断与异常提示条
          if (this.task.stale) {
            Row() {
              Text(this.task.hasSnapshot ? '同步中断 · 显示上次进度' : '等待任务同步')
                .fontSize(11)
                .fontColor($r('app.color.app_warning'))
                .width('100%')
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.app_warning_soft'))
            .borderRadius(8)
            .transition(AppMotion.reveal(4))
          }
          if (this.task.hint) {
            Row() {
              Text(this.task.hint)
                .fontSize(11)
                .fontColor($r('app.color.app_danger'))
                .width('100%')
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.app_danger_soft'))
            .borderRadius(8)
            .transition(AppMotion.reveal(4))
          }

          // 4. 底部操作控制栏
          Row({ space: 6 }) {
            if (this.task.taskCount > 1) {
              Button('上一项')
                .fontSize(11)
                .height(32)
                .padding({ left: 10, right: 10 })
                .borderRadius(10)
                .backgroundColor($r('app.color.app_card_subtle_bg'))
                .border({ width: 0.5, color: $r('app.color.app_border') })
                .fontColor($r('app.color.app_text_primary'))
                .accessibilityText('切换到上一项调查')
                .onClick((): void => InvestigationFloat.cycle(-1))
              Button('下一项')
                .fontSize(11)
                .height(32)
                .padding({ left: 10, right: 10 })
                .borderRadius(10)
                .backgroundColor($r('app.color.app_card_subtle_bg'))
                .border({ width: 0.5, color: $r('app.color.app_border') })
                .fontColor($r('app.color.app_text_primary'))
                .accessibilityText('切换到下一项调查')
                .onClick((): void => InvestigationFloat.cycle(1))
            }
            Button(this.task.taskId ? '查看' : '打开应用')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .height(32)
              .borderRadius(10)
              .layoutWeight(1)
              .backgroundColor($r('app.color.app_primary'))
              .fontColor(Color.White)
              .accessibilityText('返回清眸查看调查详情')
              .onClick((): void => { InvestigationFloat.returnToInvestigation(); })
          }
          .width('100%')
        } else {
          Row() {
            Text('请返回清眸登录')
              .fontSize(13)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .borderRadius(12)
        }
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 10 })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_card_bg'))
    .scrollBar(BarState.Auto)
  }
}
