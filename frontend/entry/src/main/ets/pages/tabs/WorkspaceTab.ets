import { HttpUtil } from '../../utils/http'
import promptAction from '@ohos.promptAction'
import router from '@ohos.router';

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

  build() {
    Column({ space: 15 }) {
      Text('新建工作区')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .margin({ bottom: 10 })

      TextInput({ placeholder: '请输入工作区名称', text: this.nameText })
        .width('100%')
        .height(45)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .onChange((value: string): void => {
          this.nameText = value;
        })

      Row({ space: 20 }) {
        Button('取消')
          .backgroundColor('#999999')
          .fontColor(Color.White)
          .width(100)
          .height(40)
          .onClick((): void => {
            this.controller.close();
          })

        Button('确认')
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .width(100)
          .height(40)
          .onClick((): void => {
            if (!this.nameText.trim()) {
              promptAction.showToast({ message: '请输入名称', duration: 1500 });
              return;
            }
            this.confirm(this.nameText);
            this.controller.close();
          })
      }
    }
    .padding(20)
    .width('90%')
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(16)
  }
}

@Component
export struct WorkspaceTab {
  @Prop @Watch('onGroupChange') groupId: number = 0;
  @State workspaces: Array<WorkspaceInfo> = [];

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
      promptAction.showToast({ message: '创建成功', duration: 1500 });
      this.loadWorkspaces();
    } else {
      promptAction.showToast({ message: '创建失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  build() {
    Column() {
      // ===== Workspace List View =====
      Row() {
        Text('所有工作区')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .layoutWeight(1)

        Button('创建工作区')
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.createDialogController.open();
          })
      }
      .width('90%')
      .padding({ top: 20, bottom: 10 })

      if (this.workspaces.length === 0) {
        Column() {
          Text('暂无工作区，请点击上方按钮创建')
            .fontSize(16)
            .fontColor($r('app.color.app_text_muted'))
            .margin({ top: 80 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)

      } else {
        List({ space: 15 }) {
          ForEach(this.workspaces, (ws: WorkspaceInfo): void => {
            ListItem() {
              Row() {
                Column({ space: 5 }) {
                  Text(ws.name)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))

                  Text('问答数: ' + ws.qa_count.toString())
                    .fontSize(14)
                    .fontColor($r('app.color.app_text_secondary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Image($r('app.media.foreground'))
                  .width(24)
                  .height(24)
              }
              .width('100%')
              .padding(20)
              .backgroundColor($r('app.color.app_card_bg'))
              .borderRadius(10)
              .shadow({ radius: 5, color: $r('app.color.app_shadow') })
              .onClick((): void => {
                router.pushUrl({
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
        .width('90%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
  }
}
