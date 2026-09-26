import { HttpUtil } from '../../utils/http'
import { MarkdownAnswer } from './MarkdownAnswer'
import { ModelConfigOption, parseModelConfig } from '../../utils/modelConfig'

class ConfigSelectItem {
  value: string = '';
}

class AgentSegmentChoice {
  id: number = 0;
  title: string = '';
  videoName: string = '';
  filePath: string = '';
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
  creatorId: string = '';
  modelConfigLabel: string = '';
  question: string = '';
  answer: string = '';
  status: string = 'processing';
  turnIndex: number = 1;
  createdAt: string = '';
  toolCalls: Array<AgentToolCall> = [];
  segmentIds: Array<number> = [];
}

class AgentToolCall {
  name: string = '';
  summary: string = '';
  query: string = '';
  queryType: string = '';
  videoId: string = '';
  timestampSec: number = -1;
  times: Array<number> = [];
  details: Array<string> = [];
  evidence: Array<AgentToolEvidence> = [];
  status: string = 'running';
  iteration: number = 0;
}

class AgentToolEvidence {
  segmentId: number = 0;
  timestampSec: number = 0;
  label: string = '';
}

class AgentTurnPayload {
  question: string = '';
  model_config_id: number = 0;
  conversation_id: string = '';
  segment_ids: Array<number> = [];
}

class EmptyRequestPayload {}

@Component
export struct AgentConversationPanel {
  @Prop workspaceId: number = 0;
  onTimestampClick: (segmentId: number, timeStr: string) => void =
    (_segmentId: number, _timeStr: string): void => {};

  @State conversations: Array<AgentConversationItem> = [];
  @State modelConfigs: Array<ModelConfigOption> = [];
  @State selectedModelConfigId: number = 0;
  @State messages: Array<AgentTurnItem> = [];
  @State segments: Array<AgentSegmentChoice> = [];
  @State selectedConversationId: string = '';
  @State evidenceSegmentIds: Array<number> = [];
  @State selectedSegmentIds: Array<number> = [];
  @State composerText: string = '';
  @State creatingInvestigation: boolean = false;
  @State isLoading: boolean = true;
  @State isSending: boolean = false;
  @State isStopping: boolean = false;
  @State liveProgress: string = '';
  @State liveStage: string = '准备调查';
  @State elapsedSeconds: number = 0;
  @State quietSeconds: number = 0;
  @State currentTaskId: string = '';
  @State conversationReady: boolean = false;
  @State expandedCallKeys: Array<string> = [];
  @State expandedTraceTurns: Array<string> = [];
  private pollTimer: number = 0;
  private pollEpoch: number = 0;
  private syncTimer: number = 0;
  private clockTimer: number = 0;
  private activeStartedAtMs: number = 0;
  private lastProgressAtMs: number = 0;
  private lastProgressCount: number = 0;
  private syncing: boolean = false;
  private messageScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.refreshAll();
  }

  aboutToDisappear(): void {
    this.stopPolling();
    this.stopSync();
  }

  async refreshAll(): Promise<void> {
    this.isLoading = true;
    await Promise.all([this.loadConversations(), this.loadSegments(), this.loadModelConfigs()]);
    if (this.selectedConversationId.length > 0) {
      await this.openConversation(this.selectedConversationId, false);
    } else {
      this.startSync();
    }
    this.isLoading = false;
  }

  async loadConversations(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/agent/conversations`);
    if (res.code !== 0 || !res.data) {
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

  async loadModelConfigs(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/model-configs`);
    if (res.code !== 0 || !res.data) return;
    const raw = JSON.parse(res.data) as Array<Record<string, Object>>;
    this.modelConfigs = raw.map((item: Record<string, Object>): ModelConfigOption => parseModelConfig(item));
    if (!this.modelConfigs.some((item: ModelConfigOption): boolean => item.id === this.selectedModelConfigId)) {
      this.selectedModelConfigId = this.modelConfigs.length > 0 ? this.modelConfigs[0].id : 0;
    }
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
      segment.filePath = (item['filepath'] as string) || '';
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
    const epoch = this.pollEpoch;
    this.selectedConversationId = conversationId;
    this.conversationReady = false;
    this.messages = [];
    this.creatingInvestigation = false;
    this.currentTaskId = '';
    this.isSending = false;
    this.isStopping = false;
    this.liveProgress = '';
    const res = await HttpUtil.get(`/workspaces/agent/conversations/${conversationId}/messages`);
    if (epoch !== this.pollEpoch || conversationId !== this.selectedConversationId) {
      return;
    }
    if (res.code !== 0 || !res.data) {
      this.messages = [];
      this.liveProgress = res.message || '加载调查记录失败';
      return;
    }
    const data = JSON.parse(res.data) as Record<string, Object>;
    this.applyConversationData(data, scrollToEnd);
    this.startSync();
  }

  applyConversationData(data: Record<string, Object>, scrollToEnd: boolean): void {
    const conversation = data['conversation'] as Record<string, Object>;
    this.conversationReady = true;
    const conversationSegmentIds = (conversation['segment_ids'] as Array<number>) || [];
    this.evidenceSegmentIds = conversationSegmentIds;
    const rawMessages = (data['messages'] as Array<Record<string, Object>>) || [];
    const mapped: Array<AgentTurnItem> = [];
    let processingId = '';
    for (let i = 0; i < rawMessages.length; i++) {
      const item = rawMessages[i];
      const turn = new AgentTurnItem();
      turn.id = (item['id'] as string) || '';
      turn.creatorId = (item['creator_id'] as string) || '';
      turn.modelConfigLabel = (item['model_config_label'] as string) || '';
      turn.question = (item['question'] as string) || '';
      turn.answer = (item['answer'] as string) || '';
      turn.status = (item['status'] as string) || 'processing';
      turn.turnIndex = (item['turn_index'] as number) || (i + 1);
      turn.createdAt = (item['created_at'] as string) || '';
      const selections = (item['selections'] as Array<Record<string, Object>>) || [];
      turn.segmentIds = conversationSegmentIds.length > 0 ? conversationSegmentIds :
        selections.map((selection: Record<string, Object>): number => selection['segment_id'] as number)
          .filter((segmentId: number): boolean => segmentId > 0);
      const rawCalls = (item['tool_calls'] as Array<Record<string, Object>>) || [];
      for (let callIndex = 0; callIndex < rawCalls.length; callIndex++) {
        const call = this.mapToolCall(rawCalls[callIndex]);
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
      const activeTurn = mapped.find((turn: AgentTurnItem): boolean => turn.id === processingId);
      this.startPolling(processingId, activeTurn ? activeTurn.createdAt : '');
    } else {
      this.currentTaskId = '';
      this.isSending = false;
      this.isStopping = false;
    }
    if (scrollToEnd) {
      setTimeout((): void => this.messageScroller.scrollEdge(Edge.Bottom), 120);
    }
  }

  startSync(): void {
    if (this.syncTimer > 0) return;
    this.syncTimer = setInterval(async (): Promise<void> => {
      const conversationId = this.selectedConversationId;
      if (!conversationId && !this.creatingInvestigation && !this.syncing) {
        this.syncing = true;
        try {
          await this.loadConversations();
        } catch (_error) {
          // Keep the last known list while connectivity recovers.
        } finally {
          this.syncing = false;
        }
        return;
      }
      if (!conversationId || !this.conversationReady || this.currentTaskId || this.isSending || this.syncing) return;
      this.syncing = true;
      try {
        const res = await HttpUtil.get(`/workspaces/agent/conversations/${conversationId}/messages`);
        if (conversationId !== this.selectedConversationId || res.code !== 0 || !res.data) return;
        const data = JSON.parse(res.data) as Record<string, Object>;
        const rawMessages = (data['messages'] as Array<Record<string, Object>>) || [];
        const last = rawMessages.length > 0 ? rawMessages[rawMessages.length - 1] : null;
        const current = this.messages.length > 0 ? this.messages[this.messages.length - 1] : null;
        if (rawMessages.length !== this.messages.length ||
            (last && current && (last['id'] !== current.id || last['status'] !== current.status))) {
          this.applyConversationData(data, true);
          await this.loadConversations();
        }
      } catch (_error) {
        // Transient sync failures should not disturb the conversation.
      } finally {
        this.syncing = false;
      }
    }, 1500);
  }

  stopSync(): void {
    if (this.syncTimer > 0) {
      clearInterval(this.syncTimer);
      this.syncTimer = 0;
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
    this.stopSync();
    this.selectedConversationId = '';
    this.conversationReady = false;
    this.evidenceSegmentIds = [];
    this.messages = [];
    this.selectedSegmentIds = [];
    this.composerText = '';
    this.liveProgress = '';
    this.currentTaskId = '';
    this.isSending = false;
    this.isStopping = false;
    this.creatingInvestigation = true;
  }

  showConversationList(): void {
    this.stopPolling();
    this.stopSync();
    this.selectedConversationId = '';
    this.conversationReady = false;
    this.evidenceSegmentIds = [];
    this.currentTaskId = '';
    this.messages = [];
    this.isSending = false;
    this.isStopping = false;
    this.liveProgress = '';
    this.creatingInvestigation = false;
    this.loadConversations();
    this.startSync();
  }

  canContinue(): boolean {
    return this.selectedConversationId.length > 0 && this.conversationReady;
  }

  evidenceScopeLabel(): string {
    const names: Array<string> = [];
    for (let i = 0; i < this.evidenceSegmentIds.length; i++) {
      const segment = this.segments.find((choice: AgentSegmentChoice): boolean => choice.id === this.evidenceSegmentIds[i]);
      names.push(segment ? segment.title : `片段 ${this.evidenceSegmentIds[i]}`);
    }
    return names.length > 0 ? `证据范围：${names.join('、')}` : '正在加载证据范围…';
  }

  activeConversationTitle(): string {
    const active = this.conversations.find((item: AgentConversationItem): boolean =>
      item.id === this.selectedConversationId);
    return active ? active.title : '调查记录';
  }

  async submitTurn(): Promise<void> {
    const question = this.composerText.trim();
    if (!question || this.isSending || this.currentTaskId.length > 0 ||
        (this.selectedConversationId.length > 0 && !this.canContinue())) {
      return;
    }
    if (this.creatingInvestigation && this.selectedSegmentIds.length === 0) {
      this.liveProgress = '先选择至少一个视频片段，再开始调查。';
      return;
    }
    if (!this.selectedModelConfigId) {
      this.liveProgress = '请先到「我的 → 模型 API」创建配置，然后在这里选择。';
      return;
    }
    const payload = new AgentTurnPayload();
    payload.question = question;
    payload.model_config_id = this.selectedModelConfigId;
    if (this.selectedConversationId.length > 0) {
      payload.conversation_id = this.selectedConversationId;
    } else {
      payload.segment_ids = this.selectedSegmentIds;
    }

    this.isSending = true;
    this.liveProgress = '正在建立证据链…';
    const epoch = this.pollEpoch;
    if (this.selectedConversationId.length > 0) {
      const latest = await HttpUtil.get(`/workspaces/agent/conversations/${this.selectedConversationId}/messages`);
      if (epoch !== this.pollEpoch) return;
      if (latest.code === 0 && latest.data) {
        const snapshot = JSON.parse(latest.data) as Record<string, Object>;
        const turns = (snapshot['messages'] as Array<Record<string, Object>>) || [];
        if (turns.some((turn: Record<string, Object>): boolean => turn['status'] === 'processing')) {
          this.applyConversationData(snapshot, true);
          return;
        }
      }
    }
    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/qa`, payload);
    if (epoch !== this.pollEpoch) {
      return;
    }
    if (res.code !== 0 || !res.data) {
      this.isSending = false;
      const errorMessage = res.message || '提交调查失败';
      if (this.selectedConversationId.length > 0) {
        await this.openConversation(this.selectedConversationId, true);
      }
      if (!this.currentTaskId) this.liveProgress = errorMessage;
      if (res.code === 6105) await this.loadModelConfigs();
      return;
    }
    const data = JSON.parse(res.data) as Record<string, Object>;
    this.currentTaskId = (data['task_id'] as string) || '';
    this.selectedConversationId = (data['conversation_id'] as string) || this.selectedConversationId;
    this.composerText = '';
    this.creatingInvestigation = false;
    await this.loadConversations();
    if (epoch !== this.pollEpoch) {
      return;
    }
    await this.openConversation(this.selectedConversationId, true);
  }

  formatDuration(seconds: number): string {
    const minutes = Math.floor(seconds / 60);
    const remainder = seconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${remainder.toString().padStart(2, '0')}`;
  }

  stageLabel(stage: string, phase: string): string {
    if (stage === 'slicing' || stage === 'metadata') return '准备证据';
    if (stage === 'model_initialization') return '启动分析';
    if (stage === 'jit_ingestion') return '建立视频索引';
    if (stage === 'reasoning') {
      if (phase === 'action') return '调用工具';
      if (phase === 'observation') return '核验线索';
      return '分析线索';
    }
    if (stage === 'answering') return '整理结论';
    return '正在调查';
  }

  startClock(createdAt: string): void {
    if (this.clockTimer > 0) clearInterval(this.clockTimer);
    this.liveStage = '准备调查';
    const parsed = Date.parse(createdAt);
    this.activeStartedAtMs = Number.isFinite(parsed) ? parsed : Date.now();
    this.lastProgressAtMs = Date.now();
    this.lastProgressCount = 0;
    this.elapsedSeconds = Math.max(0, Math.floor((Date.now() - this.activeStartedAtMs) / 1000));
    this.quietSeconds = 0;
    this.clockTimer = setInterval((): void => {
      this.elapsedSeconds = Math.max(0, Math.floor((Date.now() - this.activeStartedAtMs) / 1000));
      this.quietSeconds = Math.max(0, Math.floor((Date.now() - this.lastProgressAtMs) / 1000));
    }, 1000);
  }

  startPolling(taskId: string, createdAt: string = ''): void {
    this.stopPolling();
    this.startClock(createdAt);
    const epoch = this.pollEpoch;
    let polling = false;
    this.pollTimer = setInterval(async (): Promise<void> => {
      if (polling || epoch !== this.pollEpoch) {
        return;
      }
      polling = true;
      try {
        const res = await HttpUtil.get(`/workspaces/qa/${taskId}/status`);
        if (epoch !== this.pollEpoch || taskId !== this.currentTaskId) {
          return;
        }
        if (res.code !== 0 || !res.data) {
          this.liveProgress = res.message || '暂时无法获取调查进度，正在重试…';
          return;
        }
        const data = JSON.parse(res.data) as Record<string, Object>;
        const progress = (data['progress'] as Array<Record<string, Object>>) || [];
        this.updateLiveTurn(taskId, progress);
        const last = progress.length > 0 ? progress[progress.length - 1] : null;
        this.liveProgress = last ? ((last['message'] as string) || '正在整理证据…') : '正在整理证据…';
        if (last) {
          const detail = (last['data'] as Record<string, Object>) || {};
          this.liveStage = this.stageLabel((last['stage'] as string) || '', (detail['phase'] as string) || '');
          const recordedAt = Date.parse((last['at'] as string) || '');
          if (Number.isFinite(recordedAt)) {
            this.lastProgressAtMs = recordedAt;
          } else if (progress.length !== this.lastProgressCount) {
            this.lastProgressAtMs = Date.now();
          }
          this.lastProgressCount = progress.length;
        }
        const status = (data['status'] as string) || 'processing';
        if (status === 'completed' || status === 'failed' || status === 'stopped') {
          this.stopPolling();
          this.isSending = false;
          await this.loadConversations();
          if (epoch + 1 !== this.pollEpoch || !this.selectedConversationId) {
            return;
          }
          const conversationId = this.selectedConversationId;
          await this.openConversation(conversationId, true);
        }
      } catch (error) {
        if (epoch === this.pollEpoch) {
          this.liveProgress = '暂时无法获取调查进度，正在重试…';
        }
      } finally {
        polling = false;
      }
    }, 1000);
  }

  stopPolling(): void {
    this.pollEpoch += 1;
    if (this.pollTimer > 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = 0;
    }
    if (this.clockTimer > 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = 0;
    }
  }

  retryTurn(turn: AgentTurnItem): void {
    if (this.isSending || this.currentTaskId || !this.canContinue()) return;
    this.composerText = turn.question;
    this.submitTurn();
  }

  async stopTask(): Promise<void> {
    const taskId = this.currentTaskId;
    if (!taskId || this.isStopping) return;
    this.isStopping = true;
    const conversationId = this.selectedConversationId;
    const res = await HttpUtil.post(`/workspaces/qa/${taskId}/stop`, new EmptyRequestPayload());
    if (taskId !== this.currentTaskId || conversationId !== this.selectedConversationId) return;
    this.isStopping = false;
    if (res.code !== 0) {
      this.liveProgress = res.message || '停止失败，请重试。';
      return;
    }
    await this.openConversation(conversationId, true);
    await this.loadConversations();
  }

  mapToolCall(raw: Record<string, Object>): AgentToolCall {
    const call = new AgentToolCall();
    call.name = (raw['name'] as string) || '';
    call.summary = (raw['summary'] as string) || '';
    call.times = (raw['times'] as Array<number>) || [];
    call.details = (raw['details'] as Array<string>) || [];
    call.status = (raw['status'] as string) || 'running';
    call.iteration = (raw['iteration'] as number) || 0;
    const rawEvidence = (raw['evidence'] as Array<Record<string, Object>>) || [];
    call.evidence = rawEvidence.map((item: Record<string, Object>): AgentToolEvidence => {
      const evidence = new AgentToolEvidence();
      evidence.segmentId = (item['segment_id'] as number) || 0;
      evidence.timestampSec = (item['timestamp_sec'] as number) || 0;
      evidence.label = (item['label'] as string) || '查看证据';
      return evidence;
    });
    const params = (raw['params'] as Record<string, Object>) || {};
    call.videoId = (params['video_id'] as string) || (params['video_path'] as string) || '';
    const query = params['query_text'] || params['track_id'];
    call.query = (typeof query === 'string' ? query : (query ? String(query) : '')).substring(0, 120);
    if (call.name === 'read_frames') {
      const frames = (params['frames'] as Array<Record<string, Object>>) || [];
      call.query = `${frames.length} 张画面`;
    }
    if (call.name === 'search_visual_semantics_batch') {
      const queries = (params['queries'] as Array<string>) || [];
      call.query = queries.join(' · ').substring(0, 200);
    }
    call.queryType = (params['query_type'] as string) || '';
    const timestamp = params['timestamp_sec'];
    const numericTimestamp = Number(timestamp);
    call.timestampSec = timestamp !== undefined && !isNaN(numericTimestamp) ? numericTimestamp : -1;
    return call;
  }

  updateLiveTurn(taskId: string, progress: Array<Record<string, Object>>): void {
    const calls: Array<AgentToolCall> = [];
    for (let i = 0; i < progress.length; i++) {
      const entry = progress[i];
      if (entry['stage'] !== 'reasoning') {
        continue;
      }
      const data = (entry['data'] as Record<string, Object>) || {};
      if (data['phase'] === 'action') {
        const raw = JSON.parse('{}') as Record<string, Object>;
        raw['name'] = (data['tool_name'] as string) || '';
        raw['params'] = (data['tool_params'] as Record<string, Object>) || JSON.parse('{}') as Record<string, Object>;
        raw['iteration'] = (data['iteration'] as number) || 0;
        raw['status'] = 'running';
        calls.push(this.mapToolCall(raw));
      } else if (data['phase'] === 'observation') {
        for (let j = calls.length - 1; j >= 0; j--) {
          if (calls[j].iteration === (data['iteration'] as number)) {
            calls[j].summary = (data['summary'] as string) || '';
            calls[j].times = (data['times'] as Array<number>) || [];
            calls[j].details = (data['details'] as Array<string>) || [];
            calls[j].status = (data['result_status'] as string) || (entry['status'] as string) || 'completed';
            const rawEvidence = (data['evidence'] as Array<Record<string, Object>>) || [];
            calls[j].evidence = rawEvidence.map((item: Record<string, Object>): AgentToolEvidence => {
              const evidence = new AgentToolEvidence();
              evidence.segmentId = (item['segment_id'] as number) || 0;
              evidence.timestampSec = (item['timestamp_sec'] as number) || 0;
              evidence.label = (item['label'] as string) || '查看证据';
              return evidence;
            });
            break;
          }
        }
      }
    }
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === taskId) {
        this.messages[i].toolCalls = calls;
        this.messages = [...this.messages];
        break;
      }
    }
  }

  toolVideoLabel(turn: AgentTurnItem, videoId: string): string {
    if (!videoId) return '';
    const filename = videoId.split('/').pop() || videoId;
    for (let i = 0; i < turn.segmentIds.length; i++) {
      const segment = this.segments.find((choice: AgentSegmentChoice): boolean => choice.id === turn.segmentIds[i]);
      if (segment && segment.filePath.split('/').pop() === filename) {
        return `视频${i + 1} · ${segment.title}`;
      }
    }
    return filename;
  }

  toolSegmentId(turn: AgentTurnItem, videoId: string): number {
    if (!videoId && turn.segmentIds.length === 1) return turn.segmentIds[0];
    const filename = videoId.split('/').pop() || videoId;
    for (let i = 0; i < turn.segmentIds.length; i++) {
      const segment = this.segments.find((choice: AgentSegmentChoice): boolean => choice.id === turn.segmentIds[i]);
      if (segment && segment.filePath.split('/').pop() === filename) return segment.id;
    }
    return 0;
  }

  formatTimestamp(seconds: number): string {
    const whole = Math.floor(seconds);
    const minutes = Math.floor(whole / 60);
    const secs = whole % 60;
    return `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  toolLabel(progressText: string): string {
    if (progressText.indexOf('search_objects') >= 0 || progressText.indexOf('spatiotemporal_search') >= 0) return '查找目标';
    if (progressText.indexOf('search_visual_semantics') >= 0) return '检索画面语义';
    if (progressText.indexOf('search_video_text') >= 0) return '检索画面文字';
    if (progressText.indexOf('track_target') >= 0) return '追踪轨迹';
    if (progressText.indexOf('search_face_tracks') >= 0) return '查询人脸线索';
    if (progressText.indexOf('read_frame_image') >= 0 || progressText.indexOf('read_frames') >= 0) return '核验画面';
    // Earlier conversations may still contain the retired metadata tool.
    if (progressText.indexOf('get_video_metadata') >= 0) return '读取视频信息';
    return '正在推理';
  }

  toolNameLabel(toolName: string): string {
    if (toolName === 'search_objects' || toolName === 'spatiotemporal_search') return '查找目标';
    if (toolName === 'search_visual_semantics' || toolName === 'search_visual_semantics_batch') return '画面语义';
    if (toolName === 'search_video_text') return '画面文字';
    if (toolName === 'track_target') return '追踪轨迹';
    if (toolName === 'search_face_tracks') return '人脸线索';
    if (toolName === 'read_frame_image' || toolName === 'read_frames') return '核验画面';
    if (toolName === 'get_video_metadata') return '读取元数据';
    return '工具调用';
  }

  toolMark(toolName: string): string {
    if (toolName === 'search_objects' || toolName === 'spatiotemporal_search') return '⌕';
    if (toolName === 'track_target') return '◎';
    if (toolName === 'search_visual_semantics' || toolName === 'search_visual_semantics_batch') return '◈';
    if (toolName === 'search_video_text') return '文';
    if (toolName === 'search_face_tracks') return '人';
    if (toolName === 'read_frame_image' || toolName === 'read_frames') return '▣';
    if (toolName === 'get_video_metadata') return 'i';
    return '•';
  }

  toolAccent(toolName: string): string {
    if (toolName === 'search_video_text') return '#9A641F';
    if (toolName === 'search_face_tracks') return '#745E9F';
    if (toolName === 'read_frame_image' || toolName === 'read_frames') return '#2C659A';
    if (toolName === 'get_video_metadata') return '#536B77';
    return '#18735E';
  }

  toolSoft(toolName: string): string {
    if (toolName === 'search_video_text') return '#FFF1DC';
    if (toolName === 'search_face_tracks') return '#F0ECF8';
    if (toolName === 'read_frame_image' || toolName === 'read_frames') return '#EAF3FC';
    if (toolName === 'get_video_metadata') return '#EAF0F3';
    return '#E8F3ED';
  }

  toolKind(toolName: string): string {
    if (toolName === 'search_objects' || toolName === 'spatiotemporal_search') return '目标索引';
    if (toolName === 'track_target') return '轨迹追踪';
    if (toolName === 'search_visual_semantics' || toolName === 'search_visual_semantics_batch') return '语义检索';
    if (toolName === 'search_video_text') return '文字识别';
    if (toolName === 'search_face_tracks') return '人脸索引';
    if (toolName === 'read_frame_image' || toolName === 'read_frames') return '视觉核验';
    if (toolName === 'get_video_metadata') return '视频信息';
    return '工具';
  }

  isCallExpanded(key: string): boolean {
    return this.expandedCallKeys.indexOf(key) >= 0;
  }

  toggleCall(key: string): void {
    const index = this.expandedCallKeys.indexOf(key);
    if (index >= 0) {
      this.expandedCallKeys.splice(index, 1);
    } else {
      this.expandedCallKeys.push(key);
    }
    this.expandedCallKeys = [...this.expandedCallKeys];
  }

  isTraceExpanded(turnId: string): boolean {
    return this.expandedTraceTurns.indexOf(turnId) >= 0;
  }

  toggleTrace(turnId: string): void {
    const index = this.expandedTraceTurns.indexOf(turnId);
    if (index >= 0) {
      this.expandedTraceTurns.splice(index, 1);
    } else {
      this.expandedTraceTurns.push(turnId);
    }
    this.expandedTraceTurns = [...this.expandedTraceTurns];
  }

  @Builder ToolTrace(turn: AgentTurnItem) {
    Column({ space: 9 }) {
      Row({ space: 9 }) {
        Text('⌘')
          .fontSize(16)
          .fontColor('#18735E')
          .width(27)
          .height(27)
          .textAlign(TextAlign.Center)
          .backgroundColor('#DDEFE5')
          .borderRadius(8)
        Text('执行记录')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#233C37')
        Text(`${turn.toolCalls.length} 次工具调用`)
          .fontSize(11)
          .fontColor('#607570')
          .layoutWeight(1)
          .textAlign(TextAlign.End)
        Text(this.isTraceExpanded(turn.id) ? '收起⌃' : '查看⌄')
          .fontSize(11)
          .fontColor('#18735E')
      }
      .width('100%')
      .padding({ left: 11, right: 11, top: 10, bottom: 10 })
      .backgroundColor('#EDF4EF')
      .borderRadius(10)
      .onClick((): void => { this.toggleTrace(turn.id); })
      if (this.isTraceExpanded(turn.id)) {
        ForEach(turn.toolCalls, (call: AgentToolCall, index: number): void => {
          Column({ space: 9 }) {
            Row({ space: 10 }) {
              Text(this.toolMark(call.name))
                .fontSize(19)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.toolAccent(call.name))
                .textAlign(TextAlign.Center)
                .width(36)
                .height(36)
                .backgroundColor(this.toolSoft(call.name))
                .borderRadius(10)
              Column({ space: 3 }) {
                Text(this.toolNameLabel(call.name))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1F2B2E')
                Text(`${this.toolKind(call.name)} · 第 ${index + 1} 步`)
                  .fontSize(10)
                  .fontColor('#7A8B87')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(call.status === 'running' ? '进行中' : (call.status === 'failed' ? '未完成' : '已完成'))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(call.status === 'failed' ? '#A14D4D' :
                  (call.status === 'running' ? '#A56822' : '#18735E'))
                .padding({ left: 7, right: 7, top: 4, bottom: 4 })
                .backgroundColor(call.status === 'failed' ? '#FCECEC' :
                  (call.status === 'running' ? '#FFF2DC' : '#E8F3ED'))
                .borderRadius(6)
            }
            .width('100%')
            .onClick((): void => { this.toggleCall(`${turn.id}-${index}`); })

            Text(call.summary || (call.status === 'running' ? '正在等待工具返回…' : '工具已执行'))
                .fontSize(12)
                .fontColor(call.status === 'failed' ? '#A14D4D' : '#435A56')
                .maxLines(this.isCallExpanded(`${turn.id}-${index}`) ? 8 : 2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            if (!this.isCallExpanded(`${turn.id}-${index}`) && (call.query || call.evidence.length > 0)) {
              Row({ space: 7 }) {
                if (call.query) {
                  Text(call.query)
                    .fontSize(10)
                    .fontColor(this.toolAccent(call.name))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 7, right: 7, top: 4, bottom: 4 })
                    .backgroundColor(this.toolSoft(call.name))
                    .borderRadius(5)
                    .layoutWeight(1)
                }
                if (call.evidence.length > 0) {
                  Text(`${call.evidence.length} 个证据入口`)
                    .fontSize(10)
                    .fontColor('#18735E')
                }
              }
              .width('100%')
            }
            Row() {
              Blank()
              Text(this.isCallExpanded(`${turn.id}-${index}`) ? '收起详情  ⌃' : '查看参数与证据  ⌄')
                .fontSize(11)
                .fontColor(this.toolAccent(call.name))
            }
            .width('100%')
            .onClick((): void => { this.toggleCall(`${turn.id}-${index}`); })
            if (this.isCallExpanded(`${turn.id}-${index}`)) {
                Column({ space: 8 }) {
                  if (call.query || call.videoId || call.timestampSec >= 0 || call.queryType) {
                    Text('调用参数')
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#708080')
                    if (call.query) {
                      Text(call.query).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#29463F')
                    }
                    if (call.queryType) {
                      Text(`检索类型：${call.queryType === 'identity' ? '同一目标' : '语义分类'}`)
                        .fontSize(11).fontColor('#697C7C')
                    }
                    if (call.videoId) {
                      Text(this.toolVideoLabel(turn, call.videoId)).fontSize(11).fontColor('#697C7C')
                    }
                    if (call.timestampSec >= 0 && this.toolSegmentId(turn, call.videoId) > 0) {
                      Text(`打开核验画面 · ${this.formatTimestamp(call.timestampSec)} ↗`)
                        .fontSize(11)
                        .fontColor('#2C659A')
                        .padding({ left: 9, right: 9, top: 7, bottom: 7 })
                        .backgroundColor('#EAF3FC')
                        .borderRadius(6)
                        .onClick((): void => {
                          this.onTimestampClick(this.toolSegmentId(turn, call.videoId), this.formatTimestamp(call.timestampSec));
                        })
                    }
                  }
                  Divider().color('#E3EAE6')
                  Text('观察结果')
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#708080')
                  ForEach(call.details, (detail: string, detailIndex: number): void => {
                    Row({ space: 6 }) {
                      Text('•').fontSize(12).fontColor(this.toolAccent(call.name))
                      Text(detail).fontSize(11).fontColor('#445658').layoutWeight(1)
                    }.width('100%')
                  }, (detail: string, detailIndex: number): string => `${turn.id}-${index}-detail-${detailIndex}`)
                  if (call.times.length > 0 && this.toolSegmentId(turn, call.videoId) > 0) {
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(call.times, (seconds: number, timeIndex: number): void => {
                        Text(`${this.formatTimestamp(seconds)} ↗`)
                          .fontSize(11)
                          .fontColor(this.toolAccent(call.name))
                          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                          .backgroundColor(this.toolSoft(call.name))
                          .borderRadius(6)
                          .margin({ right: 6, bottom: 5 })
                          .onClick((): void => {
                            this.onTimestampClick(this.toolSegmentId(turn, call.videoId), this.formatTimestamp(seconds));
                          })
                      }, (seconds: number, timeIndex: number): string => `${turn.id}-${index}-time-${timeIndex}`)
                    }
                  }
                  if (call.evidence.length > 0) {
                    Text('可查看的证据')
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#708080')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(call.evidence, (evidence: AgentToolEvidence, evidenceIndex: number): void => {
                        Text(`${evidence.label} · ${this.formatTimestamp(evidence.timestampSec)} ↗`)
                          .fontSize(11)
                          .fontColor(this.toolAccent(call.name))
                          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                          .backgroundColor(this.toolSoft(call.name))
                          .borderRadius(6)
                          .margin({ right: 6, bottom: 5 })
                          .onClick((): void => {
                            if (turn.segmentIds.indexOf(evidence.segmentId) >= 0) {
                              this.onTimestampClick(evidence.segmentId, this.formatTimestamp(evidence.timestampSec));
                            }
                          })
                      }, (evidence: AgentToolEvidence, evidenceIndex: number): string =>
                        `${turn.id}-${index}-evidence-${evidenceIndex}`)
                    }
                  }
                }
                .width('100%')
                .padding(10)
                .backgroundColor('#F8FAF9')
                .borderRadius(7)
                .border({ width: 1, color: '#E2EAE5' })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(13)
          .backgroundColor('#FFFFFF')
          .borderRadius(11)
          .border({ width: 1, color: '#E0E8E3' })
        }, (call: AgentToolCall, index: number): string => `${turn.id}-${index}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 3 })
  }

  @Builder ConversationRail() {
    List({ space: 0 }) {
      ForEach(this.conversations, (item: AgentConversationItem): void => {
        ListItem() {
          Column() {
            Row({ space: 12 }) {
              Text('✦')
                .fontSize(16)
                .fontColor(item.latestStatus === 'processing' ? '#A56822' : '#147666')
                .textAlign(TextAlign.Center)
                .width(34)
                .height(34)
                .backgroundColor(item.latestStatus === 'processing' ? '#FFF4E6' : '#EDF4EF')
                .borderRadius(10)
              Column({ space: 5 }) {
                Row({ space: 8 }) {
                  Text(item.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1F2B2E')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(`${item.turnCount} 轮`)
                    .fontSize(11)
                    .fontColor('#80908A')
                }
                Text(item.latestQuestion || '打开调查记录')
                  .fontSize(12)
                  .fontColor('#708080')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (item.latestStatus === 'processing') {
                  Text('● 正在运行')
                    .fontSize(11)
                    .fontColor('#A56822')
                } else if (item.latestStatus === 'stopped') {
                  Text('已停止 · 可以追问')
                    .fontSize(11)
                    .fontColor('#708080')
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ top: 15, bottom: 15 })
            .onClick((): void => { this.openConversation(item.id); })
          }
          .width('100%')
          .border({ width: { bottom: 1 }, color: '#E8EEEA' })
        }
      })
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 18, right: 18 })
    .backgroundColor('#FFFFFF')
  }

  @Builder MessageStream() {
    List({ space: 0, scroller: this.messageScroller }) {
      ForEach(this.messages, (turn: AgentTurnItem): void => {
        ListItem() {
          Column({ space: 13 }) {
            Row({ space: 8 }) {
              Text(`第 ${turn.turnIndex} 轮`)
                .fontSize(11)
                .fontColor('#8A9791')
                .layoutWeight(1)
              Text(turn.status === 'processing' ? '运行中' :
                (turn.status === 'stopped' ? '已停止' : (turn.status === 'failed' ? '未完成' : '已完成')))
                .fontSize(11)
                .fontColor(turn.status === 'failed' || turn.status === 'stopped' ? '#A14D4D' :
                  (turn.status === 'processing' ? '#C77818' : '#178272'))
            }
            Column({ space: 6 }) {
              Text(turn.creatorId ? `${turn.creatorId} · 提问` : '组员提问')
                .fontSize(11)
                .fontColor('#758580')
              if (turn.modelConfigLabel) {
                Text(turn.modelConfigLabel)
                  .fontSize(10)
                  .fontColor('#557568')
              }
              Text(turn.question)
                .fontSize(15)
                .fontColor('#1F2B2E')
                .lineHeight(23)
            }
            .width('88%')
            .alignSelf(ItemAlign.End)
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 14, right: 14, top: 11, bottom: 11 })
            .backgroundColor('#EBF1ED')
            .borderRadius(16)
            Row({ space: 7 }) {
              Text('✦').fontSize(16).fontColor('#178272')
              Text('调查 Agent')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor('#405753')
            }
            if (turn.status === 'processing') {
              Column({ space: 7 }) {
                Row({ space: 8 }) {
                  LoadingProgress().width(16).height(16).color('#178272')
                  Text(turn.id === this.currentTaskId ?
                    `${this.liveStage} · 已运行 ${this.formatDuration(this.elapsedSeconds)}` : '调查任务仍在运行…')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#147666')
                }
                Text(turn.id === this.currentTaskId ?
                  (this.liveProgress || 'Agent 正在调取视频证据与轨迹索引…') : '正在等待最新进度…')
                  .fontSize(13).fontColor('#697C7C').maxLines(2)
                if (turn.id === this.currentTaskId && this.quietSeconds >= 90) {
                  Text(`已有 ${this.formatDuration(this.quietSeconds)} 没有新步骤，可能仍在等待模型或工具。可停止本轮后重试。`)
                    .fontSize(11).fontColor('#A56822')
                }
              }
              .padding({ left: 0, right: 0, top: 4, bottom: 4 })
            }
            if (turn.toolCalls.length > 0) {
              this.ToolTrace(turn)
            }
            if (turn.status !== 'processing') {
              Column({ space: 9 }) {
                MarkdownAnswer({
                  markdown: turn.answer || '没有生成可用结论。',
                  failed: turn.status === 'failed' || turn.status === 'stopped',
                  onTimestampClick: (video: number, time: string): void => {
                    if (video <= turn.segmentIds.length) {
                      this.onTimestampClick(turn.segmentIds[video - 1], time);
                    }
                  }
                })
                  .width('100%')
                if (turn.status === 'failed' && turn.id === this.messages[this.messages.length - 1].id) {
                  Button('重新尝试这一问  ↗')
                    .fontSize(12)
                    .backgroundColor('#EEF6F2')
                    .fontColor('#147666')
                    .borderRadius(8)
                    .enabled(!this.isSending && this.canContinue())
                    .onClick((): void => { this.retryTurn(turn); })
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 18, right: 18, top: 20, bottom: 23 })
          .backgroundColor('#FFFFFF')
          .border({ width: { bottom: 1 }, color: '#EDF1EE' })
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#FFFFFF')
  }

  @Builder Composer() {
    Column({ space: 8 }) {
      if (this.currentTaskId.length > 0) {
        Row({ space: 10 }) {
          LoadingProgress().width(16).height(16).color('#178272')
          Text('正在调查 · 组员可查看进度')
            .fontSize(12)
            .fontColor('#536760')
            .maxLines(1)
            .layoutWeight(1)
          Button(this.isStopping ? '停止中…' : '停止本轮')
            .enabled(!this.isStopping)
            .fontSize(12)
            .backgroundColor('#F8ECE8')
            .fontColor('#A24B32')
            .borderRadius(8)
            .onClick((): void => { this.stopTask(); })
        }
        .width('100%')
      } else if (this.isSending) {
        Row({ space: 8 }) {
          LoadingProgress().width(17).height(17).color('#178272')
          Text('正在提交调查…').fontSize(13).fontColor('#708080')
        }
      } else {
        if (this.liveProgress.length > 0) {
          Text(this.liveProgress)
            .fontSize(12)
            .fontColor('#A24B32')
        }
        TextArea({ placeholder: '继续追问…', text: this.composerText })
          .height(60)
          .fontSize(14)
          .fontColor('#1F2B2E')
          .backgroundColor('#F6F8F6')
          .border({ width: 1, color: '#D5E2DA' })
          .borderRadius(16)
          .padding(10)
          .onChange((value: string): void => { this.composerText = value; })
        Row() {
          Text('沿用本次调查的视频片段')
            .fontSize(11)
            .fontColor('#708080')
            .layoutWeight(1)
          Button('发送')
            .enabled(this.canContinue() && this.composerText.trim().length > 0)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .height(36)
            .backgroundColor('#233B39')
            .fontColor(Color.White)
            .borderRadius(9)
            .onClick((): void => { this.submitTurn(); })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        this.ModelSelector()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#FFFFFF')
    .border({ width: { top: 1 }, color: '#DFE7E1' })
  }

  @Builder ModelSelector() {
    Row({ space: 6 }) {
      Text('模型').fontSize(11).fontColor('#708080')
      Select(this.modelConfigs.map((item: ModelConfigOption): SelectOption => {
        const option = new ConfigSelectItem();
        option.value = `${item.scope === 'group' ? '小组' : '个人'} · ${item.name} (${item.model})`;
        return option as SelectOption;
      }))
        .selected(Math.max(0, this.modelConfigs.findIndex((item: ModelConfigOption): boolean =>
          item.id === this.selectedModelConfigId)))
        .value(this.modelConfigs.find((item: ModelConfigOption): boolean =>
          item.id === this.selectedModelConfigId)?.name || '选择配置')
        .font({ size: 11 })
        .backgroundColor('#EEF5F1')
        .onSelect((index: number): void => {
          if (this.modelConfigs[index]) this.selectedModelConfigId = this.modelConfigs[index].id;
        })
        .width(190)
      Button('刷新').fontSize(11).backgroundColor(Color.Transparent).fontColor('#178272')
        .onClick((): void => { this.loadModelConfigs(); })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
  }

  @Builder NewInvestigation() {
    Column({ space: 14 }) {
      Text('建立一条调查线')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1F2B2E')
      Text('先圈定证据范围。后续追问会沿用这些录像，并将确认过的结论带入下一轮核验。')
        .fontSize(13)
        .fontColor('#697C7C')
        .lineHeight(20)
      Text('选择相关片段')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#445658')
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
                .backgroundColor(this.isSelected(segment.id) ? '#178272' : '#D9E6DD')
                .borderRadius(11)
              Column({ space: 3 }) {
                Text(segment.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1F2B2E')
                  .maxLines(1)
                Text(`${segment.videoName} · ${segment.durationText}`)
                  .fontSize(11)
                  .fontColor('#708080')
              }
              .layoutWeight(1)
              Text(segment.status === 'completed' ? '已索引' : '待索引')
                .fontSize(11)
                .fontColor(segment.status === 'completed' ? '#178272' : '#C77818')
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.isSelected(segment.id) ? '#EEF6F2' : '#FFFFFF')
            .border({ width: 1, color: this.isSelected(segment.id) ? '#9BCFB3' : '#E2EAE5' })
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
        .backgroundColor('#FAFCFA')
        .border({ width: 1, color: '#D5E2DA' })
        .borderRadius(12)
        .padding(10)
        .onChange((value: string): void => { this.composerText = value; })
      this.ModelSelector()
      Row({ space: 10 }) {
        Button('返回')
          .layoutWeight(1)
          .height(42)
          .backgroundColor('#FFFFFF')
          .fontColor('#445658')
          .border({ width: 1, color: '#D5E2DA' })
          .borderRadius(9)
          .onClick((): void => { this.showConversationList(); })
        Button('开始调查')
          .layoutWeight(1)
          .height(42)
          .enabled(!this.isSending && this.composerText.trim().length > 0 && this.selectedSegmentIds.length > 0)
          .backgroundColor('#233B39')
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
        if (this.selectedConversationId || this.creatingInvestigation) {
          Button('‹')
            .width(36)
            .height(36)
            .fontSize(23)
            .backgroundColor(Color.Transparent)
            .fontColor('#1F2B2E')
            .margin({ right: 8 })
            .onClick((): void => { this.showConversationList(); })
        }
        Column({ space: 3 }) {
          Text(this.selectedConversationId ? this.activeConversationTitle() : '调查 Agent')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2B2E')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.selectedConversationId ? this.evidenceScopeLabel() : '视频调查与组员协作')
            .fontSize(11)
            .fontColor('#708080')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('+ 新建')
          .enabled(this.currentTaskId.length === 0 && !this.isSending)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#F0F4F1')
          .fontColor('#30463E')
          .borderRadius(8)
          .onClick((): void => { this.startInvestigation(); })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#DFE7E1' })

      if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress().width(28).height(28).color('#178272')
          Text('正在整理调查记录…').fontSize(13).fontColor('#708080')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.creatingInvestigation) {
        this.NewInvestigation()
      } else if (!this.selectedConversationId) {
        Column({ space: 10 }) {
          if (this.conversations.length > 0) {
            Row() {
              Text('调查记录')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1F2B2E')
                .layoutWeight(1)
              Text(`${this.conversations.length} 条调查线`)
                .fontSize(11)
                .fontColor('#708080')
            }
            .width('100%')
            this.ConversationRail()
          } else {
            Text('✦')
              .fontSize(30)
              .fontColor('#178272')
              .textAlign(TextAlign.Center)
              .width(64)
              .height(64)
              .backgroundColor('#E9F3ED')
              .borderRadius(18)
            Text('从证据开始调查')
              .fontSize(21).fontWeight(FontWeight.Bold).fontColor('#1F2B2E')
            Text('选择视频片段，提出一个问题。Agent 会展示检索、核验与结论，组员可以沿着同一条线继续追问。')
              .fontSize(13).fontColor('#708080').textAlign(TextAlign.Center).lineHeight(21)
            Text('视频检索   ·   工具记录   ·   连续追问')
              .fontSize(11).fontColor('#478470')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor('#EEF6F2')
              .borderRadius(8)
            Button('开始第一条调查  ↗')
              .height(44)
              .backgroundColor('#233B39').fontColor(Color.White).borderRadius(10)
              .onClick((): void => { this.startInvestigation(); })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20, top: 18, bottom: 18 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      } else {
        this.MessageStream()
        if (this.canContinue()) {
          this.Composer()
        } else {
          Text('调查记录尚未加载，暂时无法追问。')
            .fontSize(12)
            .fontColor('#708080')
            .width('100%')
            .padding(15)
            .backgroundColor('#FFFFFF')
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F8F6')
  }
}
