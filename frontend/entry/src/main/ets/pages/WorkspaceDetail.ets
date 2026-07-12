import router from '@ohos.router';
import { HttpUtil, BASE_HOST } from '../utils/http'
import promptAction from '@ohos.promptAction'
import { QARecordInfo } from './tabs/WorkspaceTab'

export class WorkspaceVideoSegment {
  id: number = 0;
  workspace_id: number = 0;
  video_name: string = '';
  start_offset: number = 0;
  end_offset: number = 0;
  duration: number = 0;
  remark: string = '';
  filepath: string = '';
  created_at: string = '';
  isSelected: boolean = false; // UI selection state
}

export class ExampleVideoInfo {
  name: string = '';
  url: string = '';
  duration: number = 0;
  isSelected: boolean = false;
  startOffset: number = 0;
  endOffset: number = 0;
}

export class ProgressGroup {
  id: string = '';
  title: string = '';
  isCompleted: boolean = false;
  isFailed: boolean = false;
  isCollapsed: boolean = false;
  details: Array<string> = [];
}

@CustomDialog
struct VideoRangeDialog {
  controller: CustomDialogController
  activeVideo: ExampleVideoInfo = new ExampleVideoInfo();
  @State startOffset: number = 0;
  @State endOffset: number = 0;
  @State remarkText: string = '';
  confirm: (start: number, end: number, remark: string) => void = (_start: number, _end: number, _remark: string): void => {};
  
  videoController: VideoController = new VideoController();

  aboutToAppear(): void {
    this.startOffset = this.activeVideo.startOffset;
    this.endOffset = this.activeVideo.endOffset > 0 ? this.activeVideo.endOffset : this.activeVideo.duration;
  }

  build() {
    Column({ space: 15 }) {
      Text('截取视频片段')
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

      TextInput({ placeholder: '请输入片段备注，例如：大门经过车辆', text: this.remarkText })
        .width('100%')
        .height(45)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .onChange((value: string): void => {
          this.remarkText = value;
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
            this.confirm(this.startOffset, this.endOffset, this.remarkText);
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

@CustomDialog
struct SegmentDetailDialog {
  controller: CustomDialogController
  segment: WorkspaceVideoSegment = new WorkspaceVideoSegment();
  @State remarkText: string = '';
  showSelectionActions: boolean = false;
  onUpdate: (remark: string) => void = (_remark: string): void => {};
  onDelete: () => void = (): void => {};
  onConfirmSelection: () => void = (): void => {};

  videoController: VideoController = new VideoController();

  aboutToAppear(): void {
    this.remarkText = this.segment.remark;
  }

  build() {
    Column({ space: 15 }) {
      Text('片段详情与预览')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      Text(`${this.segment.video_name} (${this.segment.start_offset.toFixed(1)}s - ${this.segment.end_offset.toFixed(1)}s)`)
        .fontSize(13)
        .fontColor($r('app.color.app_text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Video({
        src: BASE_HOST + '/api/video/' + this.segment.filepath,
        controller: this.videoController
      })
        .width('100%')
        .height(180)
        .autoPlay(true)
        .controls(true)
        .borderRadius(8)

      if (!this.showSelectionActions) {
        TextInput({ placeholder: '修改片段备注', text: this.remarkText })
          .width('100%')
          .height(45)
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_input_bg'))
          .onChange((value: string): void => {
            this.remarkText = value;
          })
      }

      Row({ space: 10 }) {
        if (this.showSelectionActions) {
          Button('确认选择')
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .layoutWeight(1)
            .height(40)
            .onClick((): void => {
              this.onConfirmSelection();
              this.controller.close();
            })

          Button('取消')
            .backgroundColor('#999999')
            .fontColor(Color.White)
            .layoutWeight(1)
            .height(40)
            .onClick((): void => {
              this.controller.close();
            })
        } else {
          Button('删除片段')
            .backgroundColor('#EF4444')
            .fontColor(Color.White)
            .layoutWeight(1)
            .height(40)
            .onClick((): void => {
              this.onDelete();
              this.controller.close();
            })

          Button('修改备注')
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .layoutWeight(1)
            .height(40)
            .onClick((): void => {
              this.onUpdate(this.remarkText);
              this.controller.close();
            })

          Button('关闭')
            .backgroundColor('#999999')
            .fontColor(Color.White)
            .layoutWeight(1)
            .height(40)
            .onClick((): void => {
              this.controller.close();
            })
        }
      }
      .width('100%')
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

  @State currentSubTab: number = 0; // 0: 片段, 1: 问答
  @State segments: Array<WorkspaceVideoSegment> = [];
  @State exampleVideos: Array<ExampleVideoInfo> = [];
  @State showSelectExampleVideo: boolean = false;
  @State activeVideo: ExampleVideoInfo = new ExampleVideoInfo();
  @State activeIndex: number = 0;

  @State qaRecords: Array<QARecordInfo> = [];
  @State showCreateQA: boolean = false;
  @State questionText: string = '';
  @State aiProgressText: string = '';
  @State pollIntervalId: number = 0;

  @State activeTaskId: string = '';
  @State activeTaskQuestion: string = '';
  @State activeTaskAnswer: string = '';
  @State activeTaskStatus: string = '';
  @State activeTaskProgress: Array<Record<string, Object>> = [];
  @State progressGroups: Array<ProgressGroup> = [];
  @State manualCollapsedState: Record<string, boolean> = {};
  scroller: Scroller = new Scroller();

  // Active segment for detail view
  @State selectedSegment: WorkspaceVideoSegment = new WorkspaceVideoSegment();
  @State selectedSegmentIndex: number = 0;

  rangeDialogController: CustomDialogController = new CustomDialogController({
    builder: VideoRangeDialog({
      activeVideo: this.activeVideo,
      confirm: (start: number, end: number, remark: string): void => {
        this.submitCreateSegment(this.activeIndex, start, end, remark);
      }
    }),
    autoCancel: true
  })

  detailDialogController: CustomDialogController = new CustomDialogController({
    builder: SegmentDetailDialog({
      segment: this.selectedSegment,
      onUpdate: (remark: string): void => {
        this.submitUpdateSegment(this.selectedSegment.id, remark);
      },
      onDelete: (): void => {
        this.submitDeleteSegment(this.selectedSegment.id);
      }
    }),
    autoCancel: true
  })

  qaSegmentPreviewDialogController: CustomDialogController = new CustomDialogController({
    builder: SegmentDetailDialog({
      segment: this.selectedSegment,
      showSelectionActions: true,
      onConfirmSelection: (): void => {
        this.toggleSegmentSelection(this.selectedSegmentIndex, true);
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
    this.loadSegments();
    this.loadQARecords();
  }

  aboutToDisappear(): void {
    if (this.pollIntervalId) {
      clearInterval(this.pollIntervalId);
    }
  }

  async loadSegments(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/segments`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<WorkspaceVideoSegment> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const s = new WorkspaceVideoSegment();
        s.id = item['id'] as number;
        s.workspace_id = item['workspace_id'] as number;
        s.video_name = item['video_name'] as string;
        s.start_offset = item['start_offset'] as number;
        s.end_offset = item['end_offset'] as number;
        s.duration = item['duration'] as number;
        s.remark = (item['remark'] as string) || '';
        s.filepath = item['filepath'] as string;
        s.created_at = item['created_at'] as string;
        mapped.push(s);
      }
      this.segments = mapped;
    } else {
      this.segments = [];
    }
  }

  async loadExampleVideos(): Promise<void> {
    const res = await HttpUtil.get('/workspaces/example-videos');
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<ExampleVideoInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const v = new ExampleVideoInfo();
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

  handleExampleVideoClick(index: number): void {
    const video = this.exampleVideos[index];
    this.activeIndex = index;
    this.activeVideo.name = video.name;
    this.activeVideo.url = BASE_HOST + "/api/video/" + video.url;
    this.activeVideo.duration = video.duration;
    this.activeVideo.startOffset = 0;
    this.activeVideo.endOffset = video.duration;
    this.rangeDialogController.open();
  }

  async submitCreateSegment(index: number, start: number, end: number, remark: string): Promise<void> {
    const video = this.exampleVideos[index];
    
    class SegmentPayload {
      video_name: string = '';
      start_offset: number = 0;
      end_offset: number = 0;
      remark: string = '';
    }
    const payload = new SegmentPayload();
    payload.video_name = video.name;
    payload.start_offset = start;
    payload.end_offset = end;
    payload.remark = remark;

    promptAction.showToast({ message: '正在物理裁剪并保存片段...', duration: 1500 });
    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/segments`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '片段添加成功', duration: 1500 });
      this.showSelectExampleVideo = false;
      this.loadSegments();
    } else {
      promptAction.showToast({ message: '保存失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  showSegmentDetail(seg: WorkspaceVideoSegment): void {
    this.selectedSegment = seg;
    this.detailDialogController.open();
  }

  showQASegmentPreview(seg: WorkspaceVideoSegment, index: number): void {
    this.selectedSegment = seg;
    this.selectedSegmentIndex = index;
    this.qaSegmentPreviewDialogController.open();
  }

  async submitUpdateSegment(segmentId: number, remark: string): Promise<void> {
    class UpdatePayload {
      remark: string = '';
    }
    const payload = new UpdatePayload();
    payload.remark = remark;

    const res = await HttpUtil.put(`/workspaces/segments/${segmentId}`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '备注修改成功', duration: 1500 });
      this.loadSegments();
    } else {
      promptAction.showToast({ message: '修改失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  async submitDeleteSegment(segmentId: number): Promise<void> {
    const res = await HttpUtil.del(`/workspaces/segments/${segmentId}`);
    if (res.code === 0) {
      promptAction.showToast({ message: '片段删除成功', duration: 1500 });
      this.loadSegments();
    } else {
      promptAction.showToast({ message: '删除失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  async loadQARecords(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/qa`);
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
      this.updateProgress(progressList);
    }
  }

  updateProgress(progressList: Array<Record<string, Object>>): void {
    this.activeTaskProgress = progressList || [];
    this.progressGroups = this.parseProgressToGroups(this.activeTaskProgress);
    // Smoothly scroll to bottom
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  parseProgressToGroups(progressList: Array<Record<string, Object>>): Array<ProgressGroup> {
    const groups: Array<ProgressGroup> = [];
    
    for (let i = 0; i < progressList.length; i++) {
      const item = progressList[i];
      const stage = (item['stage'] as string) || '';
      const status = (item['status'] as string) || '';
      const msg = (item['message'] as string) || '';
      const data = (item['data'] as Record<string, Object>) || {};

      if (stage === 'question_analysis') {
        let g = groups.find(x => x.id === 'question_analysis');
        if (!g) {
          g = new ProgressGroup();
          g.id = 'question_analysis';
          g.title = '模型决策';
          groups.push(g);
        }
        g.isCompleted = (status === 'completed');
        if (data['analysis']) {
          g.details = [`分析策略: ${data['analysis']}`];
        } else if (msg) {
          g.details.push(msg);
        }
      }
      else if (stage === 'initialization' && status === 'running') {
        const video = (data['video'] as string) || '';
        const id = 'init_desc_' + video;
        let g = groups.find(x => x.id === id);
        if (!g) {
          g = new ProgressGroup();
          g.id = id;
          g.title = `初始化视频: ${video}`;
          groups.push(g);
        }
        g.isCompleted = false;
        if (msg) {
          g.details = [msg];
        }
      }
      else if (stage === 'sampling' && status === 'failed') {
        const video = (data['video'] as string) || '';
        const iter = data['iteration'] !== undefined ? ` (循环 ${data['iteration']})` : '';
        const id = 'sample_fail_' + video + '_' + (data['iteration'] || 'init');
        const g = new ProgressGroup();
        g.id = id;
        g.title = `采样失败: ${video}${iter}`;
        g.isFailed = true;
        g.details.push(msg);
        groups.push(g);
      }
      else if (stage === 'description_scoring' && status === 'completed') {
        const video = (data['video'] as string) || '';
        const iteration = data['iteration'] as number;
        
        if (iteration === undefined) {
          // Initialization phase description
          const id = 'init_desc_' + video;
          let g = groups.find(x => x.id === id);
          if (!g) {
            g = new ProgressGroup();
            g.id = id;
            g.title = `初始化视频: ${video}`;
            groups.push(g);
          }
          g.isCompleted = true;
          
          const vTerm = data['v_term'] as boolean;
          const vStatus = (data['status'] as string) || '';
          let statusText = '继续探索';
          if (vTerm || vStatus === 'desc_terminated') {
            statusText = '已终止探索';
          }
          
          g.details = [
            `初始评分: ${data['score'] !== undefined ? data['score'] : '0.50'}`,
            `初始描述: ${data['description'] || ''}`,
            `当前优先级: ${data['priority'] !== undefined ? data['priority'] : '0.50'}`,
            `视频终止探索: ${vTerm ? '是 (已锁定目标特征)' : '否'}`,
            `探索状态: ${statusText}`
          ];
        } else {
          // Iteration phase description
          const id = `iter_desc_${video}_${iteration}`;
          let g = groups.find(x => x.id === id);
          if (!g) {
            g = new ProgressGroup();
            g.id = id;
            g.title = `搜索视频: ${video} (第 ${iteration} 次循环)`;
            groups.push(g);
          }
          g.isCompleted = true;
          
          const priority = data['iteration_data'] ? (data['iteration_data'] as Record<string, Object>)['priority'] : undefined;
          const vTerm = data['v_term'] as boolean;
          const gTerm = data['g_term'] as boolean;
          
          g.details = [
            `帧评分: ${data['new_score'] !== undefined ? data['new_score'] : '0.50'}`,
            `新增描述: ${data['description_snippet'] || ''}`,
            `视频评分: ${data['new_score'] !== undefined ? data['new_score'] : '0.50'}`,
            `加速度: ${data['acceleration'] !== undefined ? data['acceleration'] : '1'}`,
            `优先级: ${priority !== undefined ? priority : '0.50'}`,
            `单视频终止探索: ${vTerm ? '是' : '否'}`,
            `全局终止探索: ${gTerm ? '是' : '否'}`
          ];
        }
      }
      else if (stage === 'iteration' && status === 'tool_decided') {
        const iter = data['iteration'] as number;
        const id = `decision_${iter}`;
        let g = groups.find(x => x.id === id);
        if (!g) {
          g = new ProgressGroup();
          g.id = id;
          g.title = `制定决策 (第 ${iter} 次循环)`;
          groups.push(g);
        }
        g.isCompleted = true;
        
        const option = data['option'] !== undefined ? data['option'] : '5';
        const start = data['target_start'] !== undefined ? (data['target_start'] as number).toFixed(2) + 's' : '0.00s';
        const end = data['target_end'] !== undefined ? (data['target_end'] as number).toFixed(2) + 's' : '0.00s';
        
        g.details = [
          `目标视频: ${data['selected_video'] || ''}`,
          `行动选项: 选项 ${option}`,
          `目标区间: ${start} - ${end}`,
          `候选得分: ${data['candidate_scores'] !== undefined ? JSON.stringify(data['candidate_scores']) : '[]'}`
        ];
      }
      else if (stage === 'finalization') {
        let g = groups.find(x => x.id === 'finalization');
        if (!g) {
          g = new ProgressGroup();
          g.id = 'finalization';
          g.title = '分析探索总结';
          groups.push(g);
        }
        g.isCompleted = (status === 'completed');
        
        const termReason = (data['term_reason'] as string) || '';
        const iterCount = data['iteration_count'] !== undefined ? data['iteration_count'] as number : 0;
        const numVideos = data['num_videos'] !== undefined ? data['num_videos'] as number : 1;
        
        g.details = [
          `终止原因: ${termReason || msg || '探索完成'}`,
          `分析视频数: ${numVideos}`,
          `探索迭代次数: ${iterCount}`
        ];
      }
      else if (stage === 'answering') {
        let g = groups.find(x => x.id === 'answering');
        if (!g) {
          g = new ProgressGroup();
          g.id = 'answering';
          g.title = '生成最终回答';
          groups.push(g);
        }
        g.isCompleted = (status === 'completed');
        g.details = [];
      }
      else if (stage === 'system') {
        const id = 'sys_error';
        let g = groups.find(x => x.id === id);
        if (!g) {
          g = new ProgressGroup();
          g.id = id;
          g.title = '系统执行错误';
          groups.push(g);
        }
        g.isFailed = true;
        g.details.push(msg);
      }
    }

    const isFinished = (this.activeTaskStatus === 'completed' || this.activeTaskStatus === 'failed');
    
    for (let i = 0; i < groups.length; i++) {
      const g = groups[i];
      if (this.manualCollapsedState[g.id] !== undefined) {
        g.isCollapsed = this.manualCollapsedState[g.id];
      } else {
        if (isFinished) {
          g.isCollapsed = true;
        } else {
          g.isCollapsed = (g.isCompleted && i < groups.length - 1);
        }
      }
    }

    return groups;
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
        this.updateProgress(progressList);
        
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
          this.loadQARecords();
        } else if (status === 'failed') {
          clearInterval(this.pollIntervalId);
          this.pollIntervalId = 0;
          this.aiProgressText = '分析失败：' + error;
          promptAction.showToast({ message: 'AI 分析发生错误', duration: 2000 });
          this.loadQARecords();
        }
      } else {
        clearInterval(this.pollIntervalId);
        this.pollIntervalId = 0;
        this.aiProgressText = '获取分析进度失败: ' + (res.message || '网络连接异常');
      }
    }, 400);
  }

  async submitQA(): Promise<void> {
    if (!this.questionText) {
      promptAction.showToast({ message: '请输入问题', duration: 1500 });
      return;
    }
    
    const selectedList = this.segments.filter(v => v.isSelected);
    if (selectedList.length === 0) {
      promptAction.showToast({ message: '请至少选择一个视频片段', duration: 1500 });
      return;
    }
    
    this.aiProgressText = '正在提交任务...';

    class SubmitPayload {
      question: string = '';
      segment_ids: Array<number> = [];
    }

    const payload = new SubmitPayload();
    payload.question = this.questionText;
    
    for (let i = 0; i < selectedList.length; i++) {
      payload.segment_ids.push(selectedList[i].id);
    }

    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/qa`, payload);

    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      const taskId = dataObj['task_id'] as string;
      
      // Direct transition to analysis process timeline view
      this.activeTaskId = taskId;
      this.activeTaskQuestion = this.questionText;
      this.activeTaskAnswer = '';
      this.activeTaskStatus = 'processing';
      this.activeTaskProgress = [];
      this.progressGroups = [];
      this.showCreateQA = false;
      this.questionText = '';
      
      this.loadQARecords();
      this.startPollingStatus(taskId);
    } else {
      this.aiProgressText = '提交失败: ' + (res.message || '未知异常');
    }
  }

  toggleSegmentSelection(index: number, forceSelect?: boolean): void {
    const s = this.segments[index];
    if (forceSelect !== undefined) {
      s.isSelected = forceSelect;
    } else {
      s.isSelected = !s.isSelected;
    }
    this.segments = [...this.segments];
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
                this.loadQARecords();
              })
            Blank()
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

          Scroll(this.scroller) {
            Column({ space: 15 }) {
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

              if (this.progressGroups.length > 0) {
                ForEach(this.progressGroups, (group: ProgressGroup, idx: number): void => {
                  Column() {
                    Row() {
                      Circle({ width: 10, height: 10 })
                        .fill(group.isFailed ? '#EF4444' : (group.isCompleted ? '#10B981' : '#3B82F6'))
                        .margin({ right: 10 })

                      Text(group.title)
                        .fontSize(14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#374151')
                        .layoutWeight(1)

                      if (group.isFailed) {
                        Text('失败')
                          .fontSize(12)
                          .fontColor('#EF4444')
                          .margin({ right: 10 })
                      } else if (group.isCompleted) {
                        Text('已完成')
                          .fontSize(12)
                          .fontColor('#10B981')
                          .margin({ right: 10 })
                      } else {
                        Text('运行中')
                          .fontSize(12)
                          .fontColor('#3B82F6')
                          .margin({ right: 10 })
                      }

                      if (group.id !== 'answering') {
                        Text(group.isCollapsed ? '▼' : '▲')
                          .fontSize(12)
                          .fontColor('#9CA3AF')
                      }
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12, left: 15, right: 15 })
                    .backgroundColor('#F3F4F6')
                    .borderRadius(8)
                    .onClick((): void => {
                      if (group.id !== 'answering') {
                        const newState = !group.isCollapsed;
                        this.manualCollapsedState[group.id] = newState;
                        this.progressGroups = this.parseProgressToGroups(this.activeTaskProgress);
                      }
                    })

                    if (!group.isCollapsed && group.id !== 'answering') {
                      Column({ space: 8 }) {
                        ForEach(group.details, (detail: string): void => {
                          Row() {
                            Text('•')
                              .fontSize(14)
                              .fontColor('#4B5563')
                              .margin({ right: 8 })
                            Text(detail)
                              .fontSize(13)
                              .fontColor('#4B5563')
                              .lineHeight(18)
                              .layoutWeight(1)
                          }
                          .width('100%')
                          .alignItems(VerticalAlign.Top)
                        })
                      }
                      .width('100%')
                      .padding({ left: 30, right: 15, top: 10, bottom: 10 })
                      .backgroundColor(Color.White)
                      .borderWidth({ left: 2, right: 0, top: 0, bottom: 0 })
                      .borderColor('#E5E7EB')
                    }
                  }
                  .width('100%')
                  .borderRadius(8)
                  .clip(true)
                  .shadow({ radius: 2, color: '#05000000' })
                })
              } else {
                Text('等待分析任务启动...')
                  .fontSize(13)
                  .fontColor('#9CA3AF')
                  .padding(15)
              }

              if (this.activeTaskAnswer || this.activeTaskStatus === 'completed' || this.activeTaskStatus === 'failed') {
                Column({ space: 8 }) {
                  Text('AI 回答')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#9CA3AF')
                    .alignSelf(ItemAlign.Start)

                  Text(this.activeTaskAnswer ? this.activeTaskAnswer : '思考中...')
                    .fontSize(14)
                    .fontColor(this.activeTaskStatus === 'failed' ? '#EF4444' : '#1F2937')
                    .width('100%')
                    .lineHeight(20)
                }
                .width('100%')
                .padding(15)
                .backgroundColor(Color.White)
                .borderRadius(8)
                .shadow({ radius: 3, color: '#0D000000' })
              }
            }
            .width('100%')
          }
          .width('90%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)

      } else {
        // ===== Workspace Internal Tab View =====
        Column() {
          if (this.currentSubTab === 0) {
            // ================== "片段" Tab Content ==================
            if (this.showSelectExampleVideo) {
              // Video Selection grid for adding fragment
              Column({ space: 10 }) {
                Row() {
                  Text('选择监控源视频')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                    .layoutWeight(1)
                  
                  Button('返回片段页')
                    .fontSize(13)
                    .backgroundColor('#666666')
                    .fontColor(Color.White)
                    .onClick((): void => {
                      this.showSelectExampleVideo = false;
                    })
                }
                .width('100%')
                .padding({ bottom: 10 })

                if (this.exampleVideos.length > 0) {
                  Grid() {
                    ForEach(this.exampleVideos, (video: ExampleVideoInfo, index: number): void => {
                      GridItem() {
                        VideoItemCard({
                          name: video.name,
                          duration: video.duration,
                          onCardClick: (): void => {
                            this.handleExampleVideoClick(index);
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
                } else {
                  Column() {
                    Text('未在 example 目录下发现原视频')
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
              }
              .padding(15)
              .width('100%')
              .layoutWeight(1)

            } else {
              // Saved Video Segments list
              Column() {
                if (this.segments.length === 0) {
                  Column() {
                    Text('暂无视频片段，请点击下方加号添加')
                      .fontSize(16)
                      .fontColor($r('app.color.app_text_muted'))
                      .margin({ top: 80 })
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Start)
                } else {
                  List({ space: 12 }) {
                    ForEach(this.segments, (seg: WorkspaceVideoSegment): void => {
                      ListItem() {
                        Row() {
                          Image(BASE_HOST + '/api/video/thumbnail/' + seg.filepath)
                            .width(100)
                            .height(60)
                            .borderRadius(6)
                            .objectFit(ImageFit.Cover)
                            .margin({ right: 12 })

                          Column({ space: 4 }) {
                            Text(seg.remark ? seg.remark : '未命名片段')
                              .fontSize(15)
                              .fontWeight(FontWeight.Bold)
                              .fontColor($r('app.color.app_text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            Text('来自监控：' + seg.video_name)
                              .fontSize(12)
                              .fontColor('#9CA3AF')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            Text(`时间段：${seg.start_offset.toFixed(1)}s - ${seg.end_offset.toFixed(1)}s`)
                              .fontSize(12)
                              .fontColor('#9CA3AF')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)
                        }
                        .width('100%')
                        .padding(15)
                        .backgroundColor($r('app.color.app_card_bg'))
                        .borderRadius(10)
                        .shadow({ radius: 4, color: $r('app.color.app_shadow') })
                        .onClick((): void => {
                          this.showSegmentDetail(seg);
                        })
                      }
                    })
                  }
                  .width('90%')
                  .layoutWeight(1)
                }

                Button('+ 截取新片段')
                  .width('90%')
                  .height(48)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .margin({ top: 15, bottom: 20 })
                  .onClick((): void => {
                    this.loadExampleVideos();
                    this.showSelectExampleVideo = true;
                  })
              }
              .width('100%')
              .layoutWeight(1)
            }

          } else {
            // ================== "问答" Tab Content ==================
            if (this.showCreateQA) {
              // Create Q&A Form choosing segments
              Column({ space: 10 }) {
                Text('新建问答 - 选择包含的视频片段')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.app_text_primary'))
                  .alignSelf(ItemAlign.Start)

                if (this.segments.length > 0) {
                  List({ space: 10 }) {
                    ForEach(this.segments, (seg: WorkspaceVideoSegment, index: number): void => {
                       ListItem() {
                        Row() {
                          Image(BASE_HOST + '/api/video/thumbnail/' + seg.filepath)
                            .width(100)
                            .height(60)
                            .borderRadius(6)
                            .objectFit(ImageFit.Cover)
                            .margin({ right: 12 })

                          Column({ space: 4 }) {
                            Text(seg.remark ? seg.remark : '未命名片段')
                              .fontSize(15)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(seg.isSelected ? '#3B82F6' : $r('app.color.app_text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            Text('来自监控：' + seg.video_name)
                              .fontSize(12)
                              .fontColor('#9CA3AF')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            Text(`时间段：${seg.start_offset.toFixed(1)}s - ${seg.end_offset.toFixed(1)}s`)
                              .fontSize(12)
                              .fontColor('#9CA3AF')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)
                        }
                        .width('100%')
                        .padding(10)
                        .backgroundColor(seg.isSelected ? '#EFF6FF' : $r('app.color.app_card_bg'))
                        .borderRadius(8)
                        .border({
                          width: 1.5,
                          color: seg.isSelected ? '#3B82F6' : Color.Transparent
                        })
                        .onClick((): void => {
                          if (seg.isSelected) {
                            this.toggleSegmentSelection(index, false);
                          } else {
                            this.showQASegmentPreview(seg, index);
                          }
                        })
                      }
                    })
                  }
                  .width('100%')
                  .layoutWeight(1)
                } else {
                  Column() {
                    Text('本工作区暂无视频片段，请先前往片段页裁剪视频')
                      .fontSize(14)
                      .fontColor($r('app.color.app_text_muted'))
                      .textAlign(TextAlign.Center)
                      .margin({ bottom: 20 })
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

            } else {
              // Q&A Records List
              Column() {
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
                          this.progressGroups = [];
                          this.manualCollapsedState = {};
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
                }

                Button('+ 新建问答')
                  .width('90%')
                  .height(48)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .margin({ top: 15, bottom: 20 })
                  .onClick((): void => {
                    for (let i = 0; i < this.segments.length; i++) {
                      this.segments[i].isSelected = false;
                    }
                    this.segments = [...this.segments];
                    this.questionText = '';
                    this.aiProgressText = '';
                    this.activeTaskId = '';
                    this.activeTaskProgress = [];
                    this.progressGroups = [];
                    this.manualCollapsedState = {};
                    this.showCreateQA = true;
                  })
              }
              .width('100%')
              .layoutWeight(1)
            }
          }

          // ===== Bottom Tab Bar =====
          Row() {
            Column() {
              Image(this.currentSubTab === 0 ? $r('app.media.startIcon') : $r('app.media.foreground'))
                .width(22)
                .height(22)
              Text('片段')
                .fontSize(11)
                .fontColor(this.currentSubTab === 0 ? $r('app.color.app_primary') : $r('app.color.app_text_muted'))
            }
            .layoutWeight(1)
            .onClick((): void => {
              this.currentSubTab = 0;
              this.showCreateQA = false;
              this.showSelectExampleVideo = false;
              this.loadSegments();
            })

            Column() {
              Image(this.currentSubTab === 1 ? $r('app.media.startIcon') : $r('app.media.foreground'))
                .width(22)
                .height(22)
              Text('问答')
                .fontSize(11)
                .fontColor(this.currentSubTab === 1 ? $r('app.color.app_primary') : $r('app.color.app_text_muted'))
            }
            .layoutWeight(1)
            .onClick((): void => {
              this.currentSubTab = 1;
              this.showCreateQA = false;
              this.showSelectExampleVideo = false;
              this.loadQARecords();
            })
          }
          .width('100%')
          .height(56)
          .backgroundColor('#F9FAFB')
          .border({ width: { top: 1 }, color: '#E5E7EB' })
          .padding({ top: 5, bottom: 5 })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
  }
}

@Component
struct VideoItemCard {
  @Prop name: string = '';
  @Prop duration: number = 0;
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
      }
      .padding(8)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(8)
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
