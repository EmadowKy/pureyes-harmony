import { HttpUtil } from '../../utils/http'

interface ToastOptions {
  message: string;
  duration?: number;
}

export class WorkspaceInfo {
  id: number = 0;
  name: string = '';
  qa_count: number = 0;
}

export class QARecordInfo {
  id: string = '';
  question: string = '';
  answer: string = '';
  status: string = '';
  created_at: string = '';
  error_msg: string = '';
  video_count: number = 0;
  video_paths: Array<string> = [];
}

export class SelectableVideo {
  name: string = '';
  url: string = '';
  duration: number = 0;
  isSelected: boolean = false;
  startOffset: number = 0;
  endOffset: number = 0;
}

@CustomDialog
struct CreateWorkspaceDialog {
  controller: CustomDialogController
  confirm: (name: string) => void = (_name: string): void => {};
  @State nameText: string = '';

  showToast(options: ToastOptions): void {
    try {
      this.getUIContext().getPromptAction().showToast(options);
    } catch (error) {
      console.warn('[UI] Toast display failed:', JSON.stringify(error));
    }
  }

  build() {
    Column({ space: 14 }) {
      Text('新建工作区')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      Text('用一个工作区整理相关视频、片段和问答。')
        .fontSize(13)
        .fontColor($r('app.color.app_text_secondary'))
        .width('100%')

      TextInput({ placeholder: '请输入工作区名称', text: this.nameText })
        .width('100%')
        .height(44)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .border({ width: 1, color: $r('app.color.app_border') })
        .borderRadius(8)
        .onChange((value: string): void => {
          this.nameText = value;
        })

      Row({ space: 10 }) {
        Button('取消')
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.app_text_primary'))
          .border({ width: 1, color: $r('app.color.app_border') })
          .layoutWeight(1)
          .height(40)
          .borderRadius(8)
          .onClick((): void => {
            this.controller.close();
          })

        Button('创建')
          .backgroundColor($r('app.color.app_surface_inverted'))
          .fontColor($r('app.color.app_text_on_inverted'))
          .layoutWeight(1)
          .height(40)
          .borderRadius(8)
          .onClick((): void => {
            if (!this.nameText.trim()) {
              this.showToast({ message: '请输入名称', duration: 1500 });
              return;
            }
            this.confirm(this.nameText);
            this.controller.close();
          })
      }
    }
    .padding(22)
    .width('90%')
    .backgroundColor($r('app.color.app_card_bg'))
    .border({ width: 1, color: $r('app.color.app_border') })
    .borderRadius(12)
  }
}

@Component
export struct WorkspaceTab {
  @Prop @Watch('onGroupChange') groupId: number = 0;
  @State workspaces: Array<WorkspaceInfo> = [];

  showToast(options: ToastOptions): void {
    try {
      this.getUIContext().getPromptAction().showToast(options);
    } catch (error) {
      console.warn('[UI] Toast display failed:', JSON.stringify(error));
    }
  }

  createDialogController: CustomDialogController = new CustomDialogController({
    builder: CreateWorkspaceDialog({
      confirm: (name: string): void => {
        this.submitCreateWorkspace(name);
      }
    }),
    autoCancel: true
  })

  aboutToAppear(): void {
    this.loadWorkspaces();
  }

  onGroupChange(): void {
    this.loadWorkspaces();
  }

  async loadWorkspaces(): Promise<void> {
    if (this.groupId === 0) {
      this.workspaces = [];
      return;
    }
    const res = await HttpUtil.get(`/workspaces/${this.groupId}`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<WorkspaceInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const info = new WorkspaceInfo();
        info.id = item['id'] as number;
        info.name = item['name'] as string;
        info.qa_count = (item['qa_count'] as number) || 0;
        mapped.push(info);
      }
      this.workspaces = mapped;
    } else {
      this.workspaces = [];
    }
  }

  async submitCreateWorkspace(name: string): Promise<void> {
    class CreatePayload {
      name: string = '';
      group_id: number = 0;
    }
    const payload = new CreatePayload();
    payload.name = name;
    payload.group_id = this.groupId;

    const res = await HttpUtil.post(`/workspaces/${this.groupId}`, payload);
    if (res.code === 0) {
      this.showToast({ message: '创建成功', duration: 1500 });
      this.loadWorkspaces();
    } else {
      this.showToast({ message: '创建失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('调查工作区')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))

          Text(this.workspaces.length > 0 ? `${this.workspaces.length} 个进行中的调查` : '把相关视频、片段和问答归入同一条调查线')
            .fontSize(13)
            .fontColor($r('app.color.app_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button() {
          Row({ space: 7 }) {
            Blank()
              .width(3)
              .height(18)
              .backgroundColor($r('app.color.app_accent'))
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(16)
              .fontColor([$r('app.color.app_text_on_inverted')])
            Text('新建')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_on_inverted'))
          }
        }
          .height(40)
          .padding({ left: 13, right: 13 })
          .borderRadius(8)
          .backgroundColor($r('app.color.app_surface_inverted'))
          .onClick((): void => {
            this.createDialogController.open();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 22, bottom: 16 })

      if (this.workspaces.length === 0) {
        Column({ space: 10 }) {
          Stack() {
            Image($r('app.media.business_workspace'))
              .width(44)
              .height(44)
              .objectFit(ImageFit.Contain)
          }
          .width(64)
          .height(64)
          .borderRadius(14)
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .border({ width: 1, color: $r('app.color.app_border') })

          Text('从第一个工作区开始')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))

          Text('导入视频、截取片段，然后围绕画面发起问答。')
            .fontSize(13)
            .fontColor($r('app.color.app_text_secondary'))
            .textAlign(TextAlign.Center)
            .width('78%')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 52 })

      } else {
        List({ space: 12 }) {
          ForEach(this.workspaces, (ws: WorkspaceInfo): void => {
            ListItem() {
              Row({ space: 12 }) {
                Blank()
                  .width(3)
                  .height(54)
                  .backgroundColor($r('app.color.app_selection'))

                Image($r('app.media.business_workspace'))
                  .width(34)
                  .height(34)
                  .objectFit(ImageFit.Contain)

                Column({ space: 4 }) {
                  Text(`工作区 #${ws.id}`)
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.app_text_muted'))

                  Text(ws.name)
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row({ space: 5 }) {
                    Image($r('app.media.business_ai_qa'))
                      .width(16)
                      .height(16)
                      .objectFit(ImageFit.Contain)
                    Text(`${ws.qa_count} 条问答记录`)
                      .fontSize(12)
                      .fontColor($r('app.color.app_text_secondary'))
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Row({ space: 4 }) {
                  Text('打开')
                    .fontSize(12)
                    .fontColor($r('app.color.app_text_secondary'))
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([$r('app.color.app_text_muted')])
                }
              }
              .width('100%')
              .padding({ left: 15, right: 14, top: 15, bottom: 15 })
              .backgroundColor($r('app.color.app_card_bg'))
              .border({ width: 1, color: $r('app.color.app_border') })
              .borderRadius(10)
              .onClick((): void => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/WorkspaceDetail',
                  params: {
                    workspaceId: ws.id,
                    workspaceName: ws.name
                  }
                });
              })
            }
          })
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 24 })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
  }
}
