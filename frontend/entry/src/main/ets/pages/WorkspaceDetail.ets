import router from '@ohos.router';
import { HttpUtil, BASE_HOST } from '../utils/http'
import promptAction from '@ohos.promptAction'
import { QARecordInfo, SelectableVideo } from './tabs/WorkspaceTab'

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
        .fontColor($r('app.color.app_text_primary'))

      Text(this.activeVideo.name)
        .fontSize(14)
        .fontColor($r('app.color.app_text_secondary'))
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
            .fontColor($r('app.color.app_text_primary'))
          Blank()
          Text(`结束: ${this.endOffset.toFixed(1)}s`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_text_primary'))
        }
        .width('100%')

        Text('拖动选择起始时间:')
          .fontSize(11)
          .fontColor($r('app.color.app_text_secondary'))
          .alignSelf(ItemAlign.Start)
        Slider({
          value: this.startOffset,
          min: 0,
          max: this.activeVideo.duration,
          step: 0.1
        })
          .blockColor($r('app.color.app_primary'))
          .trackColor($r('app.color.app_text_muted'))
          .selectedColor($r('app.color.app_primary'))
          .width('100%')
          .onChange((val: number): void => {
            this.startOffset = Math.min(val, this.endOffset - 0.5);
            this.videoController.setCurrentTime(this.startOffset);
          })

        Text('拖动选择截止时间:')
          .fontSize(11)
          .fontColor($r('app.color.app_text_secondary'))
          .alignSelf(ItemAlign.Start)
        Slider({
          value: this.endOffset,
          min: 0,
          max: this.activeVideo.duration,
          step: 0.1
        })
          .blockColor($r('app.color.app_primary'))
          .trackColor($r('app.color.app_text_muted'))
          .selectedColor($r('app.color.app_primary'))
          .width('100%')
          .onChange((val: number): void => {
            this.endOffset = Math.max(val, this.startOffset + 0.5);
            this.videoController.setCurrentTime(this.endOffset);
          })
      }
      .width('100%')
      .padding(10)
      .backgroundColor($r('app.color.app_page_bg'))
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
          .backgroundColor($r('app.color.app_primary'))
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
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(16)
  }
}

@Entry
@Component
struct WorkspaceDetail {
  workspaceId: number = 0;
  workspaceName: string = '';

  @State qaRecords: Array<QARecordInfo> = [];
  @State showCreateQA: boolean = false;
  @State questionText: string = '';
  @State aiProgressText: string = '';
  @State pollIntervalId: number = 0;
  @State exampleVideos: Array<SelectableVideo> = [];
  @State activeVideo: SelectableVideo = new SelectableVideo();
  @State activeIndex: number = 0;

  @State activeTaskId: string = '';
  @State activeTaskQuestion: string = '';
  @State activeTaskAnswer: string = '';
  @State activeTaskStatus: string = '';
  @State activeTaskProgress: Array<Record<string, Object>> = [];

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
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.workspaceId = params['workspaceId'] as number;
      this.workspaceName = params['workspaceName'] as string;
    }
    this.loadQARecords(this.workspaceId);
  }

  aboutToDisappear(): void {
    if (this.pollIntervalId) {
      clearInterval(this.pollIntervalId);
    }
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

  async fetchSingleStatus(taskId: string): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/qa/${taskId}/status`);
    if (res.code === 0 && res.data) {
      const statusObj = JSON.parse(res.data) as Record<string, Object>;
      const progressList = statusObj['progress'] as Array<Record<string, Object>>;
      this.activeTaskProgress = progressList || [];
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
        
        this.activeTaskStatus = status;
        this.activeTaskAnswer = answer ? answer : (error ? '错误: ' + error : '');
        this.activeTaskProgress = progressList || [];
        
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
          this.loadQARecords(this.workspaceId);
        } else if (status === 'failed') {
          clearInterval(this.pollIntervalId);
          this.pollIntervalId = 0;
          this.aiProgressText = '分析失败：' + error;
          promptAction.showToast({ message: 'AI 分析发生错误', duration: 2000 });
          this.loadQARecords(this.workspaceId);
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

    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/qa`, payload);

    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      const taskId = dataObj['task_id'] as string;
      
      // Directly transition to analysis process view
      this.activeTaskId = taskId;
      this.activeTaskQuestion = this.questionText;
      this.activeTaskAnswer = '';
      this.activeTaskStatus = 'processing';
      this.activeTaskProgress = [];
      this.showCreateQA = false;
      this.questionText = '';
      
      this.loadQARecords(this.workspaceId);
      this.startPollingStatus(taskId);
    } else {
      this.aiProgressText = '提交失败: ' + (res.message || '未知异常');
    }
  }

  build() {
    Column() {
      // ===== Top Bar =====
      Row() {
        Button('← 返回')
          .backgroundColor('#666666')
          .fontColor(Color.White)
          .onClick((): void => {
            if (this.pollIntervalId) {
              clearInterval(this.pollIntervalId);
              this.pollIntervalId = 0;
            }
            router.back();
          })

        Text(this.workspaceName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .width('100%')
      .padding(15)

      if (this.activeTaskId !== '') {
        // ===== Q&A Analysis Process / Detail View =====
        Column({ space: 15 }) {
          // Header with back to list button
          Row() {
            Button('← 返回列表')
              .fontSize(14)
              .backgroundColor('#E5E7EB')
              .fontColor('#374151')
              .height(36)
              .onClick((): void => {
                if (this.pollIntervalId) {
                  clearInterval(this.pollIntervalId);
                  this.pollIntervalId = 0;
                }
                this.activeTaskId = '';
                this.aiProgressText = '';
                this.questionText = '';
                this.loadQARecords(this.workspaceId);
              })
            Blank()
            // Status Badge
            Text(this.activeTaskStatus === 'completed' ? '已完成' : (this.activeTaskStatus === 'failed' ? '失败' : '分析中'))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.activeTaskStatus === 'completed' ? '#10B981' : (this.activeTaskStatus === 'failed' ? '#EF4444' : '#3B82F6'))
              .backgroundColor(this.activeTaskStatus === 'completed' ? '#D1FAE5' : (this.activeTaskStatus === 'failed' ? '#FEE2E2' : '#DBEAFE'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(12)
          }
          .width('90%')
          .margin({ top: 5 })

          Scroll() {
            Column({ space: 15 }) {
              // 1. Question Card
              Column({ space: 8 }) {
                Text('问题')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#9CA3AF')
                  .alignSelf(ItemAlign.Start)
                
                Text(this.activeTaskQuestion)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#111827')
                  .width('100%')
              }
              .width('100%')
              .padding(15)
              .backgroundColor(Color.White)
              .borderRadius(8)
              .shadow({ radius: 3, color: '#0D000000' })

              // 2. AI Answer Card
              Column({ space: 8 }) {
                Text('AI 回答')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#9CA3AF')
                  .alignSelf(ItemAlign.Start)

                if (this.activeTaskStatus === 'processing' && !this.activeTaskAnswer) {
                  Row({ space: 8 }) {
                    Text('AI 正在分析中，请稍候...')
                      .fontSize(14)
                      .fontColor('#6B7280')
                  }
                  .padding({ top: 10, bottom: 10 })
                } else {
                  Text(this.activeTaskAnswer ? this.activeTaskAnswer : '分析中...')
                    .fontSize(14)
                    .fontColor(this.activeTaskStatus === 'failed' ? '#EF4444' : '#1F2937')
                    .width('100%')
                }
              }
              .width('100%')
              .padding(15)
              .backgroundColor(Color.White)
              .borderRadius(8)
              .shadow({ radius: 3, color: '#0D000000' })

              // 3. Real-time Analysis Logs (Timeline)
              Column({ space: 10 }) {
                Text('分析过程日志')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#9CA3AF')
                  .alignSelf(ItemAlign.Start)

                if (this.activeTaskProgress.length > 0) {
                  ForEach(this.activeTaskProgress, (item: Record<string, Object>, idx: number): void => {
                    Row() {
                      // Timeline Dot & vertical connector
                      Column() {
                        Circle({ width: 8, height: 8 })
                          .fill(idx === this.activeTaskProgress.length - 1 && this.activeTaskStatus === 'processing' ? '#3B82F6' : '#9CA3AF')
                        
                        if (idx < this.activeTaskProgress.length - 1) {
                          Column()
                            .width(2)
                            .height(30)
                            .backgroundColor('#E5E7EB')
                            .margin({ top: 4 })
                        }
                      }
                      .width(20)
                      .justifyContent(FlexAlign.Start)
                      .alignItems(HorizontalAlign.Center)

                      // Log text
                      Column() {
                        Text(item['message'] as string)
                          .fontSize(13)
                          .fontColor('#4B5563')
                          .width('100%')
                          .lineHeight(18)
                      }
                      .layoutWeight(1)
                      .margin({ left: 8 })
                      .padding({ bottom: idx < this.activeTaskProgress.length - 1 ? 15 : 0 })
                    }
                    .alignItems(VerticalAlign.Top)
                    .width('100%')
                  })
                } else {
                  Text('等待分析任务启动...')
                    .fontSize(13)
                    .fontColor('#9CA3AF')
                    .padding(15)
                }
              }
              .width('100%')
              .padding(15)
              .backgroundColor(Color.White)
              .borderRadius(8)
              .shadow({ radius: 3, color: '#0D000000' })
            }
            .width('100%')
          }
          .width('90%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)

      } else if (this.showCreateQA) {
        // ===== New QA Form (Multi-video Grid + Range Slider popup) =====
        Column({ space: 10 }) {
          Text('新建 AI 问答 - 选择分析视频')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
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
                .fontColor($r('app.color.app_text_muted'))
                .margin({ bottom: 10 })
              Button('刷新')
                .width(80)
                .height(35)
                .fontSize(13)
                .backgroundColor($r('app.color.app_primary'))
                .fontColor(Color.White)
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
            .fontColor($r('app.color.app_text_primary'))
            .alignSelf(ItemAlign.Start)
          TextArea({ placeholder: '请输入问题，例如：画面里有没有人经过？有几个人？', text: this.questionText })
            .height(80)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((val: string): void => {
              this.questionText = val;
            })

          Row({ space: 15 }) {
            Button('取消')
              .layoutWeight(1)
              .backgroundColor($r('app.color.app_text_muted'))
              .fontColor(Color.White)
              .onClick((): void => {
                this.showCreateQA = false;
                this.aiProgressText = '';
                this.questionText = '';
              })

            Button('提交分析')
              .layoutWeight(1)
              .backgroundColor($r('app.color.app_primary'))
              .fontColor(Color.White)
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
              .borderRadius(10)
              .fontColor('#2E7D32')
              .fontSize(13)
          }
        }
        .padding(15)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.app_card_bg'))

      } else {
        // ===== QA Records List =====
        if (this.qaRecords.length === 0) {
          Column() {
            Text('暂无问答记录')
              .fontSize(16)
              .fontColor($r('app.color.app_text_muted'))
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
                    .fontColor($r('app.color.app_text_primary'))

                  Text('A: ' + (record.status === 'processing' ? '分析中...' : (record.answer ? record.answer : record.status)))
                    .fontColor(record.status === 'processing' ? '#007DFF' : $r('app.color.app_text_secondary'))
                    .fontSize(14)

                  Text('创建时间: ' + record.created_at)
                    .fontSize(12)
                    .fontColor($r('app.color.app_text_muted'))
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding(15)
                .backgroundColor($r('app.color.app_card_bg'))
                .borderRadius(10)
                .shadow({ radius: 5, color: $r('app.color.app_shadow') })
                .onClick((): void => {
                  this.activeTaskId = record.id;
                  this.activeTaskQuestion = record.question;
                  this.activeTaskAnswer = record.answer;
                  this.activeTaskStatus = record.status;
                  this.activeTaskProgress = [];
                  if (record.status === 'processing') {
                    this.startPollingStatus(record.id);
                  } else {
                    this.fetchSingleStatus(record.id);
                  }
                })
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
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .margin({ top: 15, bottom: 20 })
          .onClick((): void => {
            this.loadExampleVideos();
            this.questionText = '';
            this.aiProgressText = '';
            this.showCreateQA = true;
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
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
        Column()
          .width('100%')
          .height(95)
          .linearGradient({
            angle: 135,
            colors: [['#E0F2FE', 0.0], ['#bae6fd', 1.0]]
          })
          .borderRadius({ topLeft: 8, topRight: 8 })

        Image($r('app.media.startIcon'))
          .width(28)
          .height(28)
          .alignSelf(ItemAlign.Center)
          .opacity(0.8)

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
          .fontColor($r('app.color.app_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.isSelected) {
          Text(`已选: ${this.startOffset.toFixed(1)}s-${this.endOffset.toFixed(1)}s`)
            .fontSize(11)
            .fontColor($r('app.color.app_primary'))
            .margin({ top: 3 })
        } else {
          Text('未选择')
            .fontSize(11)
            .fontColor($r('app.color.app_text_muted'))
            .margin({ top: 3 })
        }
      }
      .padding(8)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(8)
    .border({
      width: this.isSelected ? 2 : 0,
      color: $r('app.color.app_primary')
    })
    .shadow({ radius: 3, color: $r('app.color.app_shadow') })
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
