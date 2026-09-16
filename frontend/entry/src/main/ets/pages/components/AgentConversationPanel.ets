import { HttpUtil } from '../../utils/http'

class AgentSegmentChoice {
  id: number = 0;
  title: string = '';
  videoName: string = '';
  durationText: string = '';
  status: string = 'pending';
}

class AgentConversationItem {
  id: string = '';
  title: string = '';
  turnCount: number = 0;
  latestStatus: string = 'idle';
  latestQuestion: string = '';
}

class AgentTurnItem {
  id: string = '';
  question: string = '';
  answer: string = '';
  status: string = 'processing';
  turnIndex: number = 1;
  createdAt: string = '';
  toolCalls: Array<AgentToolCall> = [];
}

class AgentToolCall {
  name: string = '';
}

class AgentTurnPayload {
  question: string = '';
  conversation_id: string = '';
  segment_ids: Array<number> = [];
}

@Component
export struct AgentConversationPanel {
  @Prop workspaceId: number = 0;

  @State conversations: Array<AgentConversationItem> = [];
  @State messages: Array<AgentTurnItem> = [];
  @State segments: Array<AgentSegmentChoice> = [];
  @State selectedConversationId: string = '';
  @State selectedSegmentIds: Array<number> = [];
  @State composerText: string = '';
  @State creatingInvestigation: boolean = false;
  @State isLoading: boolean = true;
  @State isSending: boolean = false;
  @State liveProgress: string = '';
  @State currentTaskId: string = '';
  private pollTimer: number = 0;
  private polling: boolean = false;
  private messageScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.refreshAll();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  async refreshAll(): Promise<void> {
    this.isLoading = true;
    await this.loadConversations();
    await this.loadSegments();
    if (this.selectedConversationId.length > 0) {
      await this.openConversation(this.selectedConversationId, false);
    }
    this.isLoading = false;
  }

  async loadConversations(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/agent/conversations`);
    if (res.code !== 0 || !res.data) {
      this.conversations = [];
      return;
    }
    const raw = JSON.parse(res.data) as Array<Record<string, Object>>;
    const mapped: Array<AgentConversationItem> = [];
    for (let i = 0; i < raw.length; i++) {
      const item = raw[i];
      const conversation = new AgentConversationItem();
      conversation.id = (item['id'] as string) || '';
      conversation.title = (item['title'] as string) || '未命名调查';
      conversation.turnCount = (item['turn_count'] as number) || 0;
      conversation.latestStatus = (item['latest_status'] as string) || 'idle';
      conversation.latestQuestion = (item['latest_question'] as string) || '';
      mapped.push(conversation);
    }
    this.conversations = mapped;
  }

  async loadSegments(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/segments`);
    if (res.code !== 0 || !res.data) {
      this.segments = [];
      return;
    }
    const raw = JSON.parse(res.data) as Array<Record<string, Object>>;
    const mapped: Array<AgentSegmentChoice> = [];
    for (let i = 0; i < raw.length; i++) {
      const item = raw[i];
      const segment = new AgentSegmentChoice();
      segment.id = item['id'] as number;
      segment.title = (item['remark'] as string) || '未命名片段';
      segment.videoName = (item['video_name'] as string) || '监控录像';
      const start = (item['start_offset'] as number) || 0;
      const end = (item['end_offset'] as number) || 0;
      segment.durationText = `${start.toFixed(0)}s – ${end.toFixed(0)}s`;
      segment.status = (item['status'] as string) || 'pending';
      mapped.push(segment);
    }
    this.segments = mapped;
  }

  async openConversation(conversationId: string, scrollToEnd: boolean = true): Promise<void> {
    this.stopPolling();
    this.selectedConversationId = conversationId;
    this.creatingInvestigation = false;
    const res = await HttpUtil.get(`/workspaces/agent/conversations/${conversationId}/messages`);
    if (res.code !== 0 || !res.data) {
      this.messages = [];
      return;
    }
    const data = JSON.parse(res.data) as Record<string, Object>;
    const rawMessages = data['messages'] as Array<Record<string, Object>>;
    const mapped: Array<AgentTurnItem> = [];
    let processingId = '';
    for (let i = 0; i < rawMessages.length; i++) {
      const item = rawMessages[i];
      const turn = new AgentTurnItem();
      turn.id = (item['id'] as string) || '';
      turn.question = (item['question'] as string) || '';
      turn.answer = (item['answer'] as string) || '';
      turn.status = (item['status'] as string) || 'processing';
      turn.turnIndex = (item['turn_index'] as number) || (i + 1);
      turn.createdAt = (item['created_at'] as string) || '';
      const rawCalls = (item['tool_calls'] as Array<Record<string, Object>>) || [];
      for (let callIndex = 0; callIndex < rawCalls.length; callIndex++) {
        const call = new AgentToolCall();
        call.name = (rawCalls[callIndex]['name'] as string) || '';
        if (call.name.length > 0) {
          turn.toolCalls.push(call);
        }
      }
      if (turn.status === 'processing') {
        processingId = turn.id;
      }
      mapped.push(turn);
    }
    this.messages = mapped;
    if (processingId.length > 0) {
      this.currentTaskId = processingId;
      this.isSending = true;
      this.startPolling(processingId);
    }
    if (scrollToEnd) {
      setTimeout((): void => this.messageScroller.scrollEdge(Edge.Bottom), 120);
    }
  }

  isSelected(segmentId: number): boolean {
    return this.selectedSegmentIds.indexOf(segmentId) >= 0;
  }

  toggleSegment(segmentId: number): void {
    const index = this.selectedSegmentIds.indexOf(segmentId);
    if (index >= 0) {
      this.selectedSegmentIds.splice(index, 1);
    } else {
      this.selectedSegmentIds.push(segmentId);
    }
    this.selectedSegmentIds = [...this.selectedSegmentIds];
  }

  startInvestigation(): void {
    this.stopPolling();
    this.selectedConversationId = '';
    this.messages = [];
    this.selectedSegmentIds = [];
    this.composerText = '';
    this.liveProgress = '';
    this.creatingInvestigation = true;
  }

  async submitTurn(): Promise<void> {
    const question = this.composerText.trim();
    if (!question || this.isSending) {
      return;
    }
    if (this.creatingInvestigation && this.selectedSegmentIds.length === 0) {
      this.liveProgress = '先选择至少一个视频片段，再开始调查。';
      return;
    }
    const payload = new AgentTurnPayload();
    payload.question = question;
    if (this.selectedConversationId.length > 0) {
      payload.conversation_id = this.selectedConversationId;
    } else {
      payload.segment_ids = this.selectedSegmentIds;
    }

    this.isSending = true;
    this.liveProgress = '正在建立证据链…';
    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/qa`, payload);
    if (res.code !== 0 || !res.data) {
      this.isSending = false;
      this.liveProgress = res.message || '提交调查失败';
      return;
    }
    const data = JSON.parse(res.data) as Record<string, Object>;
    this.currentTaskId = (data['task_id'] as string) || '';
    this.selectedConversationId = (data['conversation_id'] as string) || this.selectedConversationId;
    this.composerText = '';
    this.creatingInvestigation = false;
    await this.loadConversations();
    await this.openConversation(this.selectedConversationId, true);
    if (this.currentTaskId.length > 0) {
      this.startPolling(this.currentTaskId);
    }
  }

  startPolling(taskId: string): void {
    this.stopPolling();
    this.pollTimer = setInterval(async (): Promise<void> => {
      if (this.polling) {
        return;
      }
      this.polling = true;
      try {
        const res = await HttpUtil.get(`/workspaces/qa/${taskId}/status`);
        if (res.code !== 0 || !res.data) {
          return;
        }
        const data = JSON.parse(res.data) as Record<string, Object>;
        const progress = (data['progress'] as Array<Record<string, Object>>) || [];
        if (progress.length > 0) {
          const last = progress[progress.length - 1];
          this.liveProgress = (last['message'] as string) || '正在整理证据…';
        }
        const status = (data['status'] as string) || 'processing';
        if (status === 'completed' || status === 'failed') {
          this.stopPolling();
          this.isSending = false;
          await this.loadConversations();
          await this.openConversation(this.selectedConversationId, true);
          this.liveProgress = status === 'completed' ? '' : '本轮调查未完成，请检查模型配置后重试。';
        }
      } finally {
        this.polling = false;
      }
    }, 1000);
  }

  stopPolling(): void {
    if (this.pollTimer > 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = 0;
    }
    this.polling = false;
  }

  toolLabel(progressText: string): string {
    if (progressText.indexOf('search_objects') >= 0) return '查找目标';
    if (progressText.indexOf('track_target') >= 0) return '追踪轨迹';
    if (progressText.indexOf('search_face_tracks') >= 0) return '查询人脸线索';
    if (progressText.indexOf('read_frame_image') >= 0) return '核验画面';
    return '正在推理';
  }

  toolNameLabel(toolName: string): string {
    if (toolName === 'search_objects' || toolName === 'spatiotemporal_search') return '查找目标';
    if (toolName === 'track_target') return '追踪轨迹';
    if (toolName === 'search_face_tracks') return '人脸线索';
    if (toolName === 'read_frame_image') return '核验画面';
    if (toolName === 'get_video_metadata') return '读取元数据';
    return '工具调用';
  }

  @Builder ConversationRail() {
    List({ space: 8 }) {
      ForEach(this.conversations, (item: AgentConversationItem): void => {
        ListItem() {
          Column({ space: 6 }) {
            Row() {
              Text(item.title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.selectedConversationId === item.id ? '#17324D' : '#38536A')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(`${item.turnCount}`)
                .fontSize(11)
                .fontColor('#5D7992')
            }
            Text(item.latestStatus === 'processing' ? '正在核验线索' : '可继续追问')
              .fontSize(11)
              .fontColor(item.latestStatus === 'processing' ? '#C77818' : '#64819A')
          }
          .width('100%')
          .padding(12)
          .backgroundColor(this.selectedConversationId === item.id ? '#E7F3FA' : '#F8FBFD')
          .border({ width: 1, color: this.selectedConversationId === item.id ? '#90C8E6' : '#E4EDF3' })
          .borderRadius(10)
          .onClick((): void => { this.openConversation(item.id); })
        }
      })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder MessageStream() {
    List({ space: 18, scroller: this.messageScroller }) {
      ForEach(this.messages, (turn: AgentTurnItem): void => {
        ListItem() {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text(`调查轮次 ${turn.turnIndex}`)
                .fontSize(11)
                .fontColor('#5C7992')
              Text(turn.status === 'processing' ? '正在查证' : (turn.status === 'failed' ? '未完成' : '已形成结论'))
                .fontSize(11)
                .fontColor(turn.status === 'failed' ? '#BA4A4A' : (turn.status === 'processing' ? '#C77818' : '#298066'))
            }
            Text(turn.question)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#17324D')
              .lineHeight(24)
            if (turn.status === 'processing') {
              Row({ space: 8 }) {
                LoadingProgress().width(16).height(16).color('#2788B8')
                Text(this.liveProgress || 'Agent 正在调取视频证据与轨迹索引…')
                  .fontSize(13)
                  .fontColor('#5D7992')
                  .maxLines(2)
              }
              .padding(12)
              .backgroundColor('#F0F8FC')
              .borderRadius(8)
            } else {
              Text(turn.answer || '没有生成可用结论。')
                .fontSize(14)
                .fontColor(turn.status === 'failed' ? '#9C3D3D' : '#38536A')
                .lineHeight(22)
                .copyOption(CopyOptions.InApp)
              if (turn.toolCalls.length > 0) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  Text('本轮查证')
                    .fontSize(11)
                    .fontColor('#6B8499')
                    .margin({ right: 6, top: 4, bottom: 4 })
                  ForEach(turn.toolCalls, (call: AgentToolCall, index: number): void => {
                    Text(this.toolNameLabel(call.name))
                      .fontSize(11)
                      .fontColor('#2A688C')
                      .padding({ left: 7, right: 7, top: 4, bottom: 4 })
                      .backgroundColor('#EAF5FA')
                      .borderRadius(6)
                      .margin({ right: 6, top: 3, bottom: 3 })
                  }, (call: AgentToolCall, index: number): string => `${call.name}-${index}`)
                }
                .width('100%')
              }
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .border({ width: { left: 3, top: 1, right: 1, bottom: 1 }, color: turn.status === 'processing' ? '#7DC2E8' : '#E2ECF2' })
          .borderRadius(12)
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder Composer() {
    Column({ space: 8 }) {
      if (this.liveProgress.length > 0 && !this.isSending) {
        Text(this.liveProgress)
          .fontSize(12)
          .fontColor('#A24B32')
      }
      TextArea({ placeholder: '继续追问，Agent 会继承本次调查的证据范围与已确认结论', text: this.composerText })
        .height(82)
        .fontSize(14)
        .fontColor('#17324D')
        .backgroundColor('#F8FBFD')
        .border({ width: 1, color: '#CFE0EA' })
        .borderRadius(12)
        .padding(10)
        .onChange((value: string): void => { this.composerText = value; })
      Row() {
        Text('工具可按需查找目标、追踪轨迹、查询人脸线索、核验单帧。')
          .fontSize(11)
          .fontColor('#6B8499')
          .layoutWeight(1)
        Button(this.isSending ? '查证中' : '发送追问')
          .enabled(!this.isSending && this.composerText.trim().length > 0)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#173D59')
          .fontColor(Color.White)
          .borderRadius(9)
          .onClick((): void => { this.submitTurn(); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .border({ width: { top: 1 }, color: '#E0EBF1' })
  }

  @Builder NewInvestigation() {
    Column({ space: 14 }) {
      Text('建立一条调查线')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#17324D')
      Text('先圈定证据范围。后续追问会沿用这些录像，并将确认过的结论带入下一轮核验。')
        .fontSize(13)
        .fontColor('#5D7992')
        .lineHeight(20)
      Text('选择相关片段')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#38536A')
      List({ space: 8 }) {
        ForEach(this.segments, (segment: AgentSegmentChoice): void => {
          ListItem() {
            Row({ space: 10 }) {
              Text(this.isSelected(segment.id) ? '✓' : '')
                .fontSize(16)
                .fontColor('#FFFFFF')
                .textAlign(TextAlign.Center)
                .width(22)
                .height(22)
                .backgroundColor(this.isSelected(segment.id) ? '#2788B8' : '#D8E5EC')
                .borderRadius(11)
              Column({ space: 3 }) {
                Text(segment.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#17324D')
                  .maxLines(1)
                Text(`${segment.videoName} · ${segment.durationText}`)
                  .fontSize(11)
                  .fontColor('#668198')
              }
              .layoutWeight(1)
              Text(segment.status === 'completed' ? '已索引' : '待索引')
                .fontSize(11)
                .fontColor(segment.status === 'completed' ? '#2A8268' : '#C77818')
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.isSelected(segment.id) ? '#EDF8FD' : '#FFFFFF')
            .border({ width: 1, color: this.isSelected(segment.id) ? '#8BC8E7' : '#E2ECF2' })
            .borderRadius(10)
            .onClick((): void => { this.toggleSegment(segment.id); })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      TextArea({ placeholder: '例如：这个穿深色上衣的人先后出现在哪里？', text: this.composerText })
        .height(88)
        .fontSize(14)
        .backgroundColor('#F8FBFD')
        .border({ width: 1, color: '#CFE0EA' })
        .borderRadius(12)
        .padding(10)
        .onChange((value: string): void => { this.composerText = value; })
      Row({ space: 10 }) {
        Button('返回')
          .layoutWeight(1)
          .height(42)
          .backgroundColor('#FFFFFF')
          .fontColor('#38536A')
          .border({ width: 1, color: '#CFE0EA' })
          .borderRadius(9)
          .onClick((): void => { this.creatingInvestigation = false; })
        Button('开始调查')
          .layoutWeight(1)
          .height(42)
          .enabled(!this.isSending && this.composerText.trim().length > 0 && this.selectedSegmentIds.length > 0)
          .backgroundColor('#173D59')
          .fontColor(Color.White)
          .borderRadius(9)
          .onClick((): void => { this.submitTurn(); })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .padding(18)
  }

  build() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text('调查 Agent')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17324D')
          Text(this.selectedConversationId ? '证据优先 · 支持连续追问' : '从一段录像开始建立可核验的调查线')
            .fontSize(11)
            .fontColor('#668198')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('+ 新调查')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#E7F3FA')
          .fontColor('#1C628C')
          .border({ width: 1, color: '#9CCDE5' })
          .borderRadius(8)
          .onClick((): void => { this.startInvestigation(); })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 15, bottom: 12 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#E0EBF1' })

      if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress().width(28).height(28).color('#2788B8')
          Text('正在整理调查记录…').fontSize(13).fontColor('#668198')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.creatingInvestigation) {
        this.NewInvestigation()
      } else if (!this.selectedConversationId) {
        Column({ space: 14 }) {
          if (this.conversations.length > 0) {
            Text('继续一条调查').fontSize(13).fontColor('#668198')
            this.ConversationRail()
          } else {
            Text('还没有调查线').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#17324D')
            Text('选择相关视频并提出第一个问题，Agent 会持续保存这条调查的证据范围和结论。')
              .fontSize(13).fontColor('#668198').textAlign(TextAlign.Center).lineHeight(20)
            Button('开始第一条调查')
              .backgroundColor('#173D59').fontColor(Color.White).borderRadius(9)
              .onClick((): void => { this.startInvestigation(); })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding(22)
        .justifyContent(FlexAlign.Center)
      } else {
        this.MessageStream()
        this.Composer()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F9FB')
  }
}
