import { HttpUtil } from '../../utils/http'
import promptAction from '@ohos.promptAction'

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

@CustomDialog
struct CreateWorkspaceDialog {
  controller: CustomDialogController
  @State workspaceName: string = '';
  confirm: (name: string) => void = (_name: string): void => {};

  build() {
    Column({ space: 20 }) {
      Text('创建工作区')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '请输入工作区名称', text: this.workspaceName })
        .height(45)
        .onChange((val: string): void => {
          this.workspaceName = val;
        })

      Row({ space: 20 }) {
        Button('取消')
          .backgroundColor(Color.Gray)
          .onClick((): void => {
            this.controller.close();
          })

        Button('确认创建')
          .onClick((): void => {
            this.confirm(this.workspaceName);
            this.controller.close();
          })
      }
      .margin({ top: 5 })
    }
    .padding(25)
    .width('90%')
  }
}

@Component
export struct WorkspaceTab {
  @Prop @Watch('onGroupChange') groupId: number = 0;
  @State workspaces: Array<WorkspaceInfo> = [];

  @State selectedWorkspaceId: number = 0;
  @State selectedWorkspaceName: string = '';

  @State qaRecords: Array<QARecordInfo> = [];
  @State showCreateQA: boolean = false;
  @State questionText: string = '';
  @State aiProgressText: string = '';
  @State pollIntervalId: number = 0;

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

  aboutToDisappear(): void {
    if (this.pollIntervalId) {
      clearInterval(this.pollIntervalId);
    }
  }

  onGroupChange(): void {
    if (this.pollIntervalId) {
      clearInterval(this.pollIntervalId);
      this.pollIntervalId = 0;
    }
    this.selectedWorkspaceId = 0;
    this.selectedWorkspaceName = '';
    this.qaRecords = [];
    this.showCreateQA = false;
    this.questionText = '';
    this.aiProgressText = '';
    this.loadWorkspaces();
  }

  async loadWorkspaces(): Promise<void> {
    if (!this.groupId) {
      return;
    }
    const res = await HttpUtil.get(`/workspaces/${this.groupId}`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<WorkspaceInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const w = new WorkspaceInfo();
        w.id = item['id'] as number;
        w.name = item['name'] as string;
        w.qa_count = (item['qa_count'] as number) || 0;
        mapped.push(w);
      }
      this.workspaces = mapped;
    } else {
      this.workspaces = [];
    }
  }

  async loadQARecords(workspaceId: number): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${workspaceId}/qa`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<QARecordInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const r = new QARecordInfo();
        r.id = item['id'] as string;
        r.question = item['question'] as string;
        r.answer = (item['answer'] as string) || '';
        r.status = item['status'] as string;
        r.created_at = item['created_at'] as string;
        mapped.push(r);
      }
      this.qaRecords = mapped;
    } else {
      this.qaRecords = [];
    }
  }

  async submitCreateWorkspace(name: string): Promise<void> {
    if (!name) {
      return;
    }
    class CreatePayload {
      name: string = '';
    }
    const payload = new CreatePayload();
    payload.name = name;
    const res = await HttpUtil.post(`/workspaces/${this.groupId}`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '工作区创建成功', duration: 2000 });
      this.loadWorkspaces();
    } else {
      promptAction.showToast({ message: res.message || '创建失败', duration: 2000 });
    }
  }

  startPollingStatus(taskId: string): void {
    this.aiProgressText = '正在连接 AI 推理引擎...';
    if (this.pollIntervalId) {
      clearInterval(this.pollIntervalId);
    }
    this.pollIntervalId = setInterval(async (): Promise<void> => {
      const res = await HttpUtil.get(`/workspaces/qa/${taskId}/status`);
      if (res.code === 0 && res.data) {
        const statusObj = JSON.parse(res.data) as Record<string, Object>;
        const status = statusObj['status'] as string;
        const answer = (statusObj['answer'] as string) || '';
        const error = (statusObj['error'] as string) || '';
        const progressList = statusObj['progress'] as Array<Record<string, Object>>;
        if (progressList && progressList.length > 0) {
          const latestItem = progressList[progressList.length - 1];
          this.aiProgressText = latestItem['message'] as string;
        }
        if (status === 'completed') {
          clearInterval(this.pollIntervalId);
          this.pollIntervalId = 0;
          this.aiProgressText = '分析完成：' + answer;
          this.questionText = '';
          promptAction.showToast({ message: 'AI 分析已完成', duration: 2000 });
          this.loadQARecords(this.selectedWorkspaceId);
        } else if (status === 'failed') {
          clearInterval(this.pollIntervalId);
          this.pollIntervalId = 0;
          this.aiProgressText = '分析失败：' + error;
          promptAction.showToast({ message: 'AI 分析发生错误', duration: 2000 });
          this.loadQARecords(this.selectedWorkspaceId);
        }
      } else {
        clearInterval(this.pollIntervalId);
        this.pollIntervalId = 0;
        this.aiProgressText = '获取分析进度失败: ' + (res.message || '网络连接异常');
      }
    }, 1500);
  }

  async submitQA(): Promise<void> {
    if (!this.questionText) {
      promptAction.showToast({ message: '请输入问题', duration: 1500 });
      return;
    }
    this.aiProgressText = '正在提交任务...';

    class Selection {
      monitor_id: number = 1;
      start_time: string = '';
      end_time: string = '';
    }

    class SubmitPayload {
      question: string = '';
      selections: Array<Selection> = [];
    }

    const payload = new SubmitPayload();
    payload.question = this.questionText;
    const sel = new Selection();
    sel.start_time = new Date().toISOString();
    sel.end_time = new Date().toISOString();
    payload.selections.push(sel);

    const res = await HttpUtil.post(`/workspaces/${this.selectedWorkspaceId}/qa`, payload);

    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      const taskId = dataObj['task_id'] as string;
      this.startPollingStatus(taskId);
    } else {
      this.aiProgressText = '提交失败: ' + (res.message || '未知异常');
    }
  }

  build() {
    Column() {
      if (this.selectedWorkspaceId !== 0) {
        // ===== Detail View =====
        Row() {
          Button('← 返回')
            .backgroundColor('#666666')
            .fontColor(Color.White)
            .onClick((): void => {
              if (this.pollIntervalId) {
                clearInterval(this.pollIntervalId);
                this.pollIntervalId = 0;
              }
              this.selectedWorkspaceId = 0;
              this.selectedWorkspaceName = '';
              this.showCreateQA = false;
              this.aiProgressText = '';
              this.questionText = '';
              this.loadWorkspaces();
            })

          Text(this.selectedWorkspaceName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding(15)

        if (this.showCreateQA) {
          // ===== New QA Form =====
          Column({ space: 15 }) {
            Text('新建 AI 问答')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)

            TextArea({ placeholder: '请输入问题，例如：昨天下午2点有没有穿红衣服的人经过？', text: this.questionText })
              .height(120)
              .onChange((val: string): void => {
                this.questionText = val;
              })

            Text('已选定当前监控视角与时间段')
              .fontColor(Color.Gray)
              .fontSize(13)

            Button('提交分析')
              .width('100%')
              .height(45)
              .onClick((): void => {
                this.submitQA();
              })

            if (this.aiProgressText.length > 0) {
              Text(this.aiProgressText)
                .width('100%')
                .padding(15)
                .backgroundColor('#E8F5E9')
                .borderRadius(8)
                .fontColor('#2E7D32')
                .fontSize(14)
            }

            Button('取消')
              .width('100%')
              .backgroundColor(Color.Gray)
              .fontColor(Color.White)
              .onClick((): void => {
                this.showCreateQA = false;
                this.aiProgressText = '';
                this.questionText = '';
              })
          }
          .padding(20)
          .width('100%')
          .backgroundColor(Color.White)

        } else {
          // ===== QA Records List =====
          if (this.qaRecords.length === 0) {
            Column() {
              Text('暂无问答记录')
                .fontSize(16)
                .fontColor('#999999')
                .margin({ top: 80 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Start)

          } else {
            List({ space: 15 }) {
              ForEach(this.qaRecords, (record: QARecordInfo): void => {
                ListItem() {
                  Column({ space: 8 }) {
                    Text('Q: ' + record.question)
                      .fontWeight(FontWeight.Bold)
                      .fontSize(15)

                    Text('A: ' + (record.answer ? record.answer : record.status))
                      .fontColor('#666666')
                      .fontSize(14)

                    Text('创建时间: ' + record.created_at)
                      .fontSize(12)
                      .fontColor('#AAAAAA')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .padding(15)
                  .backgroundColor(Color.White)
                  .borderRadius(8)
                  .shadow({ radius: 4, color: '#1A000000' })
                }
              })
            }
            .width('90%')
            .layoutWeight(1)
            .margin({ top: 10 })
          }

          Button('+ 新建问答')
            .width('90%')
            .height(48)
            .margin({ top: 15, bottom: 20 })
            .onClick((): void => {
              this.showCreateQA = true;
            })
        }

      } else {
        // ===== Workspace List View =====
        Row() {
          Text('所有工作区')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)

          Button('创建工作区')
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
              .fontColor('#999999')
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

                    Text('问答数: ' + ws.qa_count.toString())
                      .fontSize(14)
                      .fontColor(Color.Gray)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Image($r('app.media.foreground'))
                    .width(24)
                    .height(24)
                }
                .width('100%')
                .padding(20)
                .backgroundColor(Color.White)
                .borderRadius(8)
                .shadow({ radius: 4, color: '#1A000000' })
                .onClick((): void => {
                  this.selectedWorkspaceId = ws.id;
                  this.selectedWorkspaceName = ws.name;
                  this.showCreateQA = false;
                  this.aiProgressText = '';
                  this.questionText = '';
                  this.loadQARecords(ws.id);
                })
              }
            })
          }
          .width('90%')
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
