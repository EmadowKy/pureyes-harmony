import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { HttpUtil } from './http';
import { InvestigationCard } from './investigationCard';
import { InvestigationDashboard, InvestigationTaskSnapshot, parseInvestigationDashboard, taskDuration } from './investigationTaskState';

export class InvestigationTaskCenter {
  private static context?: common.UIAbilityContext;
  private static timer: number = 0;
  private static busy: boolean = false;
  private static foreground: boolean = true;
  private static lastRefresh: number = 0;
  private static backgroundStarted: boolean = false;
  private static dashboard: InvestigationDashboard = new InvestigationDashboard();
  private static initialized: boolean = false;
  private static epoch: number = 0;
  private static notificationTimes: Map<string, number> = new Map();
  private static watchedTasks: Set<string> = new Set();
  private static observingBackground: boolean = false;

  static start(context: common.UIAbilityContext): void {
    InvestigationTaskCenter.context = context;
    notificationManager.isNotificationEnabled().then((enabled: boolean): void => {
      AppStorage.setOrCreate('investigation_notifications_enabled', enabled);
    }).catch((): void => {});
    if (!InvestigationTaskCenter.observingBackground) {
      try {
        backgroundTaskManager.on('continuousTaskCancel', (): void => {
          InvestigationTaskCenter.backgroundStarted = false;
          if (InvestigationTaskCenter.dashboard.activeCount > 0) {
            AppStorage.setOrCreate('investigation_notification_hint', '后台同步已被系统取消；返回应用可继续同步。');
          }
        });
        InvestigationTaskCenter.observingBackground = true;
      } catch (_error) {}
    }
    if (!InvestigationTaskCenter.timer) {
      const epoch = InvestigationTaskCenter.epoch;
      InvestigationCard.dashboard(context).then((data: InvestigationDashboard): void => {
        if (epoch !== InvestigationTaskCenter.epoch) return;
        InvestigationTaskCenter.dashboard = data;
        InvestigationTaskCenter.initialized = true;
        InvestigationTaskCenter.refresh();
      }).catch((): void => {
        if (epoch !== InvestigationTaskCenter.epoch) return;
        InvestigationTaskCenter.initialized = true;
        InvestigationTaskCenter.refresh();
      });
      InvestigationTaskCenter.timer = setInterval((): void => { InvestigationTaskCenter.refresh(); }, 5000);
    }
    InvestigationTaskCenter.foreground = true;
    InvestigationTaskCenter.refresh();
  }
  static setForeground(value: boolean): void {
    InvestigationTaskCenter.foreground = value;
    if (value) InvestigationTaskCenter.refresh();
  }
  static async enableNotifications(context: common.UIAbilityContext): Promise<void> {
    InvestigationTaskCenter.start(context);
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        await notificationManager.requestEnableNotification(context);
      }
      const enabled = await notificationManager.isNotificationEnabled();
      AppStorage.setOrCreate('investigation_notifications_enabled', enabled);
      AppStorage.setOrCreate('investigation_notification_hint', enabled ? '' :
        '未开启通知，可在系统设置中允许清眸通知。');
      if (enabled) { InvestigationTaskCenter.lastRefresh = 0; await InvestigationTaskCenter.refresh(); }
    } catch (_error) {
      AppStorage.setOrCreate('investigation_notification_hint', '未开启通知，可在系统设置中允许清眸通知。');
    }
  }
  private static notificationId(taskId: string): number {
    let value = 17;
    for (let index = 0; index < taskId.length; index++) value = (value * 31 + taskId.charCodeAt(index)) % 1000000000;
    return value + 1000;
  }
  private static async target(task: InvestigationTaskSnapshot): Promise<WantAgent> {
    return wantAgent.getWantAgent({ wants: [{ bundleName: 'cn.edu.nuaa.pureyes', abilityName: 'EntryAbility',
      parameters: { fromInvestigationCard: 'true', workspaceId: task.workspaceId.toString(), groupId: task.groupId.toString(), conversationId: task.conversationId } }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: InvestigationTaskCenter.notificationId(task.taskId),
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
  }
  private static async notify(task: InvestigationTaskSnapshot, terminal: boolean, epoch: number): Promise<void> {
    if (!await notificationManager.isNotificationEnabled()) return;
    const target = await InvestigationTaskCenter.target(task);
    if (epoch !== InvestigationTaskCenter.epoch || !AppStorage.get<string>('access_token')) return;
    const now = Date.now();
    if (!terminal && now - (InvestigationTaskCenter.notificationTimes.get(task.taskId) || 0) < 15000) return;
    await notificationManager.publish({ id: InvestigationTaskCenter.notificationId(task.taskId),
      notificationSlotType: terminal ? notificationManager.SlotType.SERVICE_INFORMATION : notificationManager.SlotType.OTHER_TYPES,
      isAlertOnce: !terminal, showDeliveryTime: terminal,
      content: { contentType: 0,
        normal: { title: terminal ? (task.status === 'completed' ? '清眸 · 调查已完成' : '清眸 · 调查已结束') : '清眸 · 调查进行中',
          text: `${task.stage} · ${task.steps} 步 · ${taskDuration(task.elapsedSeconds)}`,
          additionalText: '点击返回调查' } },
      wantAgent: target });
    InvestigationTaskCenter.notificationTimes.set(task.taskId, now);
  }
  static async submitted(taskId: string, conversationId: string, workspaceId: number): Promise<void> {
    if (!taskId || !InvestigationTaskCenter.context) return;
    const task = new InvestigationTaskSnapshot();
    task.taskId = taskId;
    task.conversationId = conversationId;
    task.workspaceId = workspaceId;
    task.status = 'processing';
    task.stage = '准备调查';
    InvestigationTaskCenter.watchedTasks.add(taskId);
    const dashboard = InvestigationTaskCenter.dashboard;
    dashboard.tasks = [task, ...dashboard.tasks.filter((item: InvestigationTaskSnapshot): boolean => item.conversationId !== conversationId)];
    dashboard.activeCount = dashboard.tasks.filter((item: InvestigationTaskSnapshot): boolean => item.status === 'processing').length;
    dashboard.updatedAt = new Date().toISOString();
    try { await InvestigationCard.publishDashboard(InvestigationTaskCenter.context, dashboard); } catch (_error) {}
    InvestigationTaskCenter.lastRefresh = 0;
    await InvestigationTaskCenter.refresh();
  }
  static async refresh(): Promise<void> {
    const context = InvestigationTaskCenter.context;
    if (!context || !InvestigationTaskCenter.initialized || InvestigationTaskCenter.busy || Date.now() - InvestigationTaskCenter.lastRefresh < 4000) return;
    if (!AppStorage.get<string>('access_token')) return;
    if (!InvestigationTaskCenter.foreground && InvestigationTaskCenter.dashboard.activeCount === 0) return;
    InvestigationTaskCenter.busy = true;
    const epoch = InvestigationTaskCenter.epoch;
    InvestigationTaskCenter.lastRefresh = Date.now();
    try {
      const res = await HttpUtil.get('/workspaces/agent/tasks');
      if (res.code !== 0 || !res.data) return;
      const next = parseInvestigationDashboard(JSON.parse(res.data) as Record<string, Object>);
      if (!AppStorage.get<string>('access_token') || epoch !== InvestigationTaskCenter.epoch) return;
      const previous = InvestigationTaskCenter.dashboard;
      InvestigationTaskCenter.dashboard = next;
      await InvestigationCard.publishDashboard(context, next);
      if (epoch !== InvestigationTaskCenter.epoch) return;
      for (const old of previous.tasks) {
        if (!next.tasks.some((task: InvestigationTaskSnapshot): boolean => task.taskId === old.taskId)) {
          try { await notificationManager.cancel(InvestigationTaskCenter.notificationId(old.taskId)); } catch (_error) {}
          InvestigationTaskCenter.notificationTimes.delete(old.taskId);
        }
      }
      for (const task of next.tasks) {
        try {
          if (task.status === 'processing') {
            InvestigationTaskCenter.watchedTasks.add(task.taskId);
            await InvestigationTaskCenter.notify(task, false, epoch);
          } else if (InvestigationTaskCenter.watchedTasks.has(task.taskId) || previous.tasks.some(
            (item: InvestigationTaskSnapshot): boolean => item.taskId === task.taskId && item.status === 'processing')) {
            await InvestigationTaskCenter.notify(task, true, epoch);
            InvestigationTaskCenter.watchedTasks.delete(task.taskId);
          }
        } catch (_error) { AppStorage.setOrCreate('investigation_notification_hint', '通知暂不可用，请查看应用内进度。'); }
      }
      if (epoch !== InvestigationTaskCenter.epoch) return;
      if (next.activeCount > 0 && !InvestigationTaskCenter.backgroundStarted && InvestigationTaskCenter.foreground) {
        try {
          await backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
            await InvestigationTaskCenter.target(next.tasks[0]));
          InvestigationTaskCenter.backgroundStarted = true;
        } catch (_error) {
          AppStorage.setOrCreate('investigation_notification_hint', '系统未允许后台同步；离开应用后通知可能延迟。');
        }
      } else if (next.activeCount === 0 && InvestigationTaskCenter.backgroundStarted) {
        await backgroundTaskManager.stopBackgroundRunning(context);
        InvestigationTaskCenter.backgroundStarted = false;
      }
    } catch (_error) {
      // Preserve the last synchronized card during transient connection failures.
    } finally { InvestigationTaskCenter.busy = false; }
  }
  static async clear(context: common.Context): Promise<void> {
    InvestigationTaskCenter.epoch++;
    InvestigationTaskCenter.initialized = false;
    if (InvestigationTaskCenter.timer) clearInterval(InvestigationTaskCenter.timer);
    InvestigationTaskCenter.timer = 0;
    const tasks = InvestigationTaskCenter.dashboard.tasks;
    InvestigationTaskCenter.dashboard = new InvestigationDashboard();
    for (const task of tasks) {
      try { await notificationManager.cancel(InvestigationTaskCenter.notificationId(task.taskId)); } catch (_error) {}
    }
    if (InvestigationTaskCenter.backgroundStarted && InvestigationTaskCenter.context) {
      try { await backgroundTaskManager.stopBackgroundRunning(InvestigationTaskCenter.context); } catch (_error) {}
    }
    InvestigationTaskCenter.backgroundStarted = false;
    InvestigationTaskCenter.notificationTimes.clear();
    InvestigationTaskCenter.watchedTasks.clear();
    InvestigationTaskCenter.lastRefresh = 0;
    AppStorage.setOrCreate('investigation_notification_hint', '');
    AppStorage.setOrCreate('investigation_notifications_enabled', false);
    await InvestigationCard.clear(context);
  }
}
