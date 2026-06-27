import { HttpUtil, BASE_HOST } from '../../utils/http'
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

@CustomDialog
struct VideoRangeDialog {
  controller: CustomDialogController
  activeVideo: SelectableVideo = new SelectableVideo();
  @State startOffset: number = 0;
  @State endOffset: number = 0;
  confirm: (start: number, end: number) => void = (_start: number, _end: number): void => {};
  
  videoController: VideoController = new VideoController();

  aboutToAppear(): void {
    this.startOffset = this.activeVideo.startOffset;
    this.endOffset = this.activeVideo.endOffset > 0 ? this.activeVideo.endOffset : this.activeVideo.duration;
  }

  build() {
    Column({ space: 15 }) {
      Text('选择裁剪时间范围')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Text(this.activeVideo.name)
        .fontSize(14)
        .fontColor('#555555')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Video({
        src: this.activeVideo.url,
        controller: this.videoController
      })
        .width('100%')
        .height(180)
        .autoPlay(true)
        .controls(true)
        .borderRadius(8)

      Column({ space: 8 }) {
        Row() {
          Text(`开始: ${this.startOffset.toFixed(1)}s`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
          Blank()
          Text(`结束: ${this.endOffset.toFixed(1)}s`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')

        Text('拖动选择起始时间:')
          .fontSize(11)
          .fontColor(Color.Gray)
          .alignSelf(ItemAlign.Start)
        Slider({
          value: this.startOffset,
          min: 0,
          max: this.activeVideo.duration,
          step: 0.1
        })
          .blockColor('#007DFF')
          .trackColor('#CCCCCC')
          .selectedColor('#007DFF')
          .width('100%')
          .onChange((val: number): void => {
            this.startOffset = Math.min(val, this.endOffset - 0.5);
            this.videoController.setCurrentTime(this.startOffset);
          })

        Text('拖动选择截止时间:')
          .fontSize(11)
          .fontColor(Color.Gray)
          .alignSelf(ItemAlign.Start)
        Slider({
          value: this.endOffset,
          min: 0,
          max: this.activeVideo.duration,
          step: 0.1
        })
          .blockColor('#007DFF')
          .trackColor('#CCCCCC')
          .selectedColor('#007DFF')
          .width('100%')
          .onChange((val: number): void => {
            this.endOffset = Math.max(val, this.startOffset + 0.5);
            this.videoController.setCurrentTime(this.endOffset);
          })
      }
      .width('100%')
      .padding(10)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)

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
          .backgroundColor('#007DFF')
          .fontColor(Color.White)
          .width(100)
          .height(40)
          .onClick((): void => {
            this.confirm(this.startOffset, this.endOffset);
            this.controller.close();
          })
      }
    }
    .padding(20)
    .width('95%')
    .backgroundColor(Color.White)
    .borderRadius(16)
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
  @State exampleVideos: Array<SelectableVideo> = [];
  @State activeVideo: SelectableVideo = new SelectableVideo();
  @State activeIndex: number = 0;

  createDialogController: CustomDialogController = new CustomDialogController({
    builder: CreateWorkspaceDialog({
      confirm: (name: string): void => {
        this.submitCreateWorkspace(name);
      }
    }),
    autoCancel: true
  })

  rangeDialogController: CustomDialogController = new CustomDialogController({
    builder: VideoRangeDialog({
      activeVideo: this.activeVideo,
      confirm: (start: number, end: number): void => {
        this.confirmVideoSelection(this.activeIndex, start, end);
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

  async loadExampleVideos(): Promise<void> {
    const res = await HttpUtil.get('/workspaces/example-videos');
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<SelectableVideo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const v = new SelectableVideo();
        v.name = item['name'] as string;
        v.url = item['url'] as string;
        v.duration = (item['duration'] as number) || 0;
        v.isSelected = false;
        v.startOffset = 0;
        v.endOffset = v.duration;
        mapped.push(v);
      }
      this.exampleVideos = mapped;
    } else {
      this.exampleVideos = [];
    }
  }

  handleVideoClick(index: number): void {
    const video = this.exampleVideos[index];
    if (video.isSelected) {
      video.isSelected = false;
      this.exampleVideos = [...this.exampleVideos];
    } else {
      this.showRangeSelector(index);
    }
  }

  showRangeSelector(index: number): void {
    const video = this.exampleVideos[index];
    this.activeIndex = index;
    
    this.activeVideo.name = video.name;
    this.activeVideo.url = BASE_HOST + "/api/video/" + video.url;
    this.activeVideo.duration = video.duration;
    this.activeVideo.startOffset = video.startOffset;
    this.activeVideo.endOffset = video.endOffset > 0 ? video.endOffset : video.duration;
    
    this.rangeDialogController.open();
  }

  confirmVideoSelection(index: number, start: number, end: number): void {
    const video = this.exampleVideos[index];
    video.isSelected = true;
    video.startOffset = start;
    video.endOffset = end;
    this.exampleVideos = [...this.exampleVideos];
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
    
    const selectedList = this.exampleVideos.filter(v => v.isSelected);
    if (selectedList.length === 0) {
      promptAction.showToast({ message: '请至少选择一个视频文件', duration: 1500 });
      return;
    }
    
    this.aiProgressText = '正在提交任务...';

    class Selection {
      video_name: string = '';
      start_time_offset: number = 0;
      end_time_offset: number = 0;
    }

    class SubmitPayload {
      question: string = '';
      selections: Array<Selection> = [];
    }

    const payload = new SubmitPayload();
    payload.question = this.questionText;
    
    for (let i = 0; i < selectedList.length; i++) {
      const v = selectedList[i];
      const sel = new Selection();
      sel.video_name = v.name;
      sel.start_time_offset = v.startOffset;
      sel.end_time_offset = v.endOffset > 0 ? v.endOffset : v.duration;
      payload.selections.push(sel);
    }

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
          // ===== New QA Form (Multi-video Grid + Range Slider popup) =====
          Column({ space: 10 }) {
            Text('新建 AI 问答 - 选择分析视频')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .alignSelf(ItemAlign.Start)

            if (this.exampleVideos.length > 0) {
              Grid() {
                ForEach(this.exampleVideos, (video: SelectableVideo, index: number): void => {
                  GridItem() {
                    VideoSelectCard({
                      name: video.name,
                      duration: video.duration,
                      isSelected: video.isSelected,
                      startOffset: video.startOffset,
                      endOffset: video.endOffset,
                      onCardClick: (): void => {
                        this.handleVideoClick(index);
                      }
                    })
                  }
                })
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(10)
              .rowsGap(10)
              .width('100%')
              .layoutWeight(1)
              .margin({ bottom: 5 })
            } else {
              Column() {
                Text('未在 example 目录下发现测试视频')
                  .fontSize(14)
                  .fontColor('#999999')
                  .margin({ bottom: 10 })
                Button('刷新')
                  .width(80)
                  .height(35)
                  .fontSize(13)
                  .onClick((): void => {
                    this.loadExampleVideos();
                  })
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            }

            Text('AI 分析提问:')
              .fontSize(14)
              .fontColor('#333333')
              .alignSelf(ItemAlign.Start)
            TextArea({ placeholder: '请输入问题，例如：画面里有没有人经过？有几个人？', text: this.questionText })
              .height(80)
              .onChange((val: string): void => {
                this.questionText = val;
              })

            Row({ space: 15 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(Color.Gray)
                .fontColor(Color.White)
                .onClick((): void => {
                  this.showCreateQA = false;
                  this.aiProgressText = '';
                  this.questionText = '';
                })

              Button('提交分析')
                .layoutWeight(1)
                .onClick((): void => {
                  this.submitQA();
                })
            }
            .width('100%')
            .margin({ top: 5 })

            if (this.aiProgressText.length > 0) {
              Text(this.aiProgressText)
                .width('100%')
                .padding(10)
                .backgroundColor('#E8F5E9')
                .borderRadius(8)
                .fontColor('#2E7D32')
                .fontSize(13)
            }
          }
          .padding(15)
          .width('100%')
          .layoutWeight(1)
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
              this.loadExampleVideos();
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

@Component
struct VideoSelectCard {
  @Prop name: string = '';
  @Prop duration: number = 0;
  @Prop isSelected: boolean = false;
  @Prop startOffset: number = 0;
  @Prop endOffset: number = 0;
  onCardClick: () => void = (): void => {};

  build() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        // Thumbnail with nice gradient (Bilibili card style placeholder)
        Column()
          .width('100%')
          .height(95)
          .linearGradient({
            angle: 135,
            colors: [['#E0F2FE', 0.0], ['#bae6fd', 1.0]]
          })
          .borderRadius({ topLeft: 8, topRight: 8 })

        // Play/Video Icon overlay in the center of the gradient
        Image($r('app.media.startIcon'))
          .width(28)
          .height(28)
          .alignSelf(ItemAlign.Center)
          .opacity(0.8)

        // Duration Label at bottom-right
        Text(this.formatDuration(this.duration))
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor('rgba(0, 0, 0, 0.65)')
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .borderRadius(3)
          .margin(5)
      }
      .width('100%')

      Column() {
        Text(this.name)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.isSelected) {
          Text(`已选: ${this.startOffset.toFixed(1)}s-${this.endOffset.toFixed(1)}s`)
            .fontSize(11)
            .fontColor('#007DFF')
            .margin({ top: 3 })
        } else {
          Text('未选择')
            .fontSize(11)
            .fontColor('#999999')
            .margin({ top: 3 })
        }
      }
      .padding(8)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .backgroundColor(Color.White)
    .borderRadius(8)
    .border({
      width: this.isSelected ? 2 : 0,
      color: '#007DFF'
    })
    .shadow({ radius: 3, color: '#1A000000' })
    .onClick((): void => {
      this.onCardClick();
    })
  }

  formatDuration(sec: number): string {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }
}
