import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { floatView, floatingBall, window } from '@kit.ArkUI';
import { InvestigationDashboard, InvestigationTaskSnapshot } from './investigationTaskState';
import { InvestigationFloatSnapshot, floatSnapshot, floatStatusLabel, floatErrorHint,
  selectFloatTask, nextFloatTask, floatWindowSize, FloatWindowBounds, FloatWindowRatio } from './investigationFloatState';

export class InvestigationFloat {
  private static controller?: floatView.FloatViewController;
  private static ball?: floatingBall.FloatingBallController;
  private static storage: LocalStorage = new LocalStorage();
  private static dashboard: InvestigationDashboard = new InvestigationDashboard();
  private static selected: string = '';
  private static preferredConversation: string = '';
  private static preferredWorkspace: number = 0;
  private static synchronizedAt: number = 0;
  private static failed: boolean = false;
  private static frozenAt: number = 0;
  private static generation: number = 0;
  private static timer: number = 0;
  private static active: boolean = false;
  private static queue: Promise<void> = Promise.resolve();
  private static ballUpdatedAt: number = 0;
  private static lastBallText: string = '';
  private static lastStatus: string = '';
  private static hint: string = '';
  private static startSignal?: (started: boolean) => void;
  private static permissionDenied: boolean = false;
  private static viewStopped: boolean = true;
  private static ballStopped: boolean = true;
  private static releasing: boolean = false;
  private static stopSignal?: () => void;
  private static restoring: boolean = false;

  static supported(): boolean {
    try {
      return deviceInfo.apiAvailable('26.0.0') && canIUse('SystemCapability.Window.SessionManager') &&
        floatView.isFloatViewEnabled() && floatingBall.isFloatingBallEnabled();
    } catch (_error) { return false; }
  }

  private static enqueue(action: () => Promise<void>): Promise<void> {
    const next = InvestigationFloat.queue.catch((): void => {}).then(action);
    InvestigationFloat.queue = next.catch((): void => {});
    return next;
  }

  static update(dashboard: InvestigationDashboard): void {
    const previous = InvestigationFloat.dashboard.tasks.find((task: InvestigationTaskSnapshot): boolean => task.taskId === InvestigationFloat.selected);
    InvestigationFloat.selected = selectFloatTask(dashboard, InvestigationFloat.selected,
      InvestigationFloat.preferredConversation || previous?.conversationId || '',
      InvestigationFloat.preferredWorkspace || previous?.workspaceId || 0);
    InvestigationFloat.dashboard = dashboard;
    InvestigationFloat.synchronizedAt = Date.now();
    InvestigationFloat.failed = false;
    InvestigationFloat.frozenAt = 0;
    if (InvestigationFloat.hint === '后台同步已停止，请返回应用更新进度。') {
      InvestigationFloat.hint = '';
      AppStorage.setOrCreate('investigation_float_hint', '');
    }
    InvestigationFloat.render();
  }

  static syncFailed(): void {
    if (!InvestigationFloat.failed) InvestigationFloat.frozenAt = Date.now();
    InvestigationFloat.failed = true;
    InvestigationFloat.render();
  }

  static backgroundCancelled(): void {
    InvestigationFloat.syncFailed();
    InvestigationFloat.setHint('后台同步已停止，请返回应用更新进度。');
  }

  static cycle(direction: number): void {
    InvestigationFloat.selected = nextFloatTask(InvestigationFloat.dashboard, InvestigationFloat.selected, direction);
    const chosen = InvestigationFloat.dashboard.tasks.find((task: InvestigationTaskSnapshot): boolean => task.taskId === InvestigationFloat.selected);
    InvestigationFloat.preferredConversation = chosen?.conversationId || '';
    InvestigationFloat.preferredWorkspace = chosen?.workspaceId || 0;
    InvestigationFloat.setHint('');
  }

  private static setHint(hint: string): void {
    InvestigationFloat.hint = hint;
    AppStorage.setOrCreate('investigation_float_hint', hint);
    InvestigationFloat.render();
  }

  private static render(): void {
    const snapshot = floatSnapshot(InvestigationFloat.dashboard, InvestigationFloat.selected,
      InvestigationFloat.synchronizedAt, Date.now(), InvestigationFloat.failed, InvestigationFloat.frozenAt);
    snapshot.hint = InvestigationFloat.hint;
    InvestigationFloat.storage.setOrCreate('floatTask', snapshot);
    if (!InvestigationFloat.active || !AppStorage.get<string>('access_token')) return;
    const terminalChanged = snapshot.status !== InvestigationFloat.lastStatus;
    if (!terminalChanged && Date.now() - InvestigationFloat.ballUpdatedAt < 10000) return;
    const text = snapshot.stale ? '等待同步' : snapshot.taskId ?
      `${snapshot.steps} 步 · ${snapshot.duration}` : '暂无任务';
    const fingerprint = `${snapshot.status}:${text}`;
    if (fingerprint === InvestigationFloat.lastBallText) return;
    InvestigationFloat.ballUpdatedAt = Date.now();
    InvestigationFloat.lastBallText = fingerprint;
    InvestigationFloat.lastStatus = snapshot.status;
    const generation = InvestigationFloat.generation;
    InvestigationFloat.enqueue(async (): Promise<void> => {
      if (generation !== InvestigationFloat.generation || !InvestigationFloat.active) return;
      try {
        if (deviceInfo.apiAvailable('26.0.0')) {
          await InvestigationFloat.ball?.updateFloatingBall(InvestigationFloat.ballParams(snapshot));
        }
      } catch (_error) {
        // A minimized or temporarily hidden window may reject updates; the next snapshot retries.
        InvestigationFloat.lastBallText = '';
      }
    });
  }

  private static ballParams(snapshot: InvestigationFloatSnapshot): floatingBall.FloatingBallParams {
    return { template: floatingBall.FloatingBallTemplate.NORMAL,
      title: snapshot.taskId ? floatStatusLabel(snapshot.status) : '清眸调查',
      content: snapshot.stale ? '等待同步' : snapshot.taskId ? `${snapshot.steps} 步 · ${snapshot.duration}` : '暂无任务' };
  }

  static async open(context: common.UIAbilityContext, conversationId: string, workspaceId: number): Promise<void> {
    if (AppStorage.get<boolean>('investigation_float_busy')) return;
    if (!AppStorage.get<string>('access_token')) { InvestigationFloat.setHint('请先登录清眸。'); return; }
    if (!InvestigationFloat.supported()) {
      InvestigationFloat.setHint('当前设备不支持鸿蒙闪控，请使用任务通知或桌面小部件。');
      return;
    }
    if (InvestigationFloat.active) return;
    const generation = ++InvestigationFloat.generation;
    AppStorage.setOrCreate('investigation_float_busy', true);
    InvestigationFloat.setHint('');
    InvestigationFloat.preferredConversation = conversationId;
    InvestigationFloat.preferredWorkspace = workspaceId;
    InvestigationFloat.selected = selectFloatTask(InvestigationFloat.dashboard, InvestigationFloat.selected,
      conversationId, workspaceId);
    await InvestigationFloat.enqueue(async (): Promise<void> => {
      try {
        if (generation !== InvestigationFloat.generation) return;
        const manager = abilityAccessCtrl.createAtManager();
        if (manager.checkAccessTokenSync(context.applicationInfo.accessTokenId, 'ohos.permission.USE_FLOAT_BALL') !==
          abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          InvestigationFloat.setHint('当前安装包未获得闪控球系统授权，需由开发者申请权限并更新签名；可继续使用任务通知。');
          return;
        }
        const granted = InvestigationFloat.permissionDenied ?
          await manager.requestPermissionOnSetting(context, ['ohos.permission.FLOAT_VIEW']) :
          (await manager.requestPermissionsFromUser(context, ['ohos.permission.FLOAT_VIEW'])).authResults;
        if (generation !== InvestigationFloat.generation) return;
        if (granted.length !== 1 || granted[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          InvestigationFloat.permissionDenied = true;
          InvestigationFloat.setHint('闪控权限未开启；再次点击可前往授权。调查仍在继续。');
          return;
        }
        InvestigationFloat.permissionDenied = false;
        if (deviceInfo.apiAvailable('26.0.0')) {
          const controller = await floatView.create({ context,
            templateType: floatView.FloatViewTemplateType.ROUNDED_RECTANGLE, isConfirmOnClose: false });
          InvestigationFloat.controller = controller;
          const ball = await floatingBall.create({ context });
          InvestigationFloat.ball = ball;
          InvestigationFloat.viewStopped = true;
          InvestigationFloat.ballStopped = true;
          ball.on('stateChange', (state: floatingBall.FloatingBallState): void => {
            if (InvestigationFloat.ball !== ball) return;
            InvestigationFloat.ballStopped = state === floatingBall.FloatingBallState.STOPPED;
            InvestigationFloat.stopSignal?.();
            if (generation !== InvestigationFloat.generation || InvestigationFloat.releasing) return;
            if (InvestigationFloat.ballStopped) InvestigationFloat.close();
          });
          controller.onStateChange((info: floatView.FloatViewStateChangeInfo): void => {
            if (InvestigationFloat.controller !== controller) return;
            InvestigationFloat.viewStopped = info.state === floatView.FloatViewState.STOPPED;
            InvestigationFloat.stopSignal?.();
            if (generation !== InvestigationFloat.generation || InvestigationFloat.releasing) return;
            if (info.state === floatView.FloatViewState.STARTED) {
              InvestigationFloat.active = true;
              AppStorage.setOrCreate('investigation_float_active', true);
              InvestigationFloat.startSignal?.(true);
            } else if (info.state === floatView.FloatViewState.STOPPED || info.state === floatView.FloatViewState.ERROR) {
              if (info.state === floatView.FloatViewState.ERROR) InvestigationFloat.setHint(floatErrorHint(0));
              InvestigationFloat.active = false;
              AppStorage.setOrCreate('investigation_float_active', false);
              InvestigationFloat.stopTimer();
              InvestigationFloat.startSignal?.(false);
              // Respect a user/system close. Never respawn the window on a polling tick.
              InvestigationFloat.close();
            }
          });
          InvestigationFloat.render();
          await controller.setUIContext('pages/InvestigationFloatWindow', InvestigationFloat.storage);
          await floatView.bind(controller, ball, InvestigationFloat.ballParams(
            floatSnapshot(InvestigationFloat.dashboard, InvestigationFloat.selected,
              InvestigationFloat.synchronizedAt, Date.now(), InvestigationFloat.failed, InvestigationFloat.frozenAt)));
          if (generation !== InvestigationFloat.generation) { await InvestigationFloat.release(); return; }
          const limits = floatView.getFloatViewLimits(floatView.FloatViewTemplateType.ROUNDED_RECTANGLE);
          let density = 1;
          try { density = (await window.getLastWindow(context)).getUIContext().vp2px(1); } catch (_error) {}
          const bounds: FloatWindowBounds = {
            minSize: { width: limits.minSize.width, height: limits.minSize.height },
            maxSize: { width: limits.maxSize.width, height: limits.maxSize.height },
            ratioLimits: limits.ratioLimits.map((range: floatView.RatioLimit): FloatWindowRatio =>
              ({ minRatio: range.minRatio, maxRatio: range.maxRatio }))
          };
          const size = floatWindowSize(bounds, density);
          await controller.setWindowSize({ width: size.width, height: size.height });
          let timeout: number = 0;
          const started = new Promise<boolean>((resolve): void => {
            InvestigationFloat.startSignal = resolve;
            timeout = setTimeout((): void => resolve(false), 10000);
          });
          try {
            InvestigationFloat.viewStopped = false;
            InvestigationFloat.ballStopped = false;
            await controller.start();
            if (!await started) throw new Error('Float window did not start');
          } finally {
            clearTimeout(timeout);
            InvestigationFloat.startSignal = undefined;
          }
          if (generation !== InvestigationFloat.generation || !AppStorage.get<string>('access_token')) {
            await InvestigationFloat.release(); return;
          }
          InvestigationFloat.timer = setInterval((): void => InvestigationFloat.render(), 1000);
          InvestigationFloat.lastBallText = '';
          InvestigationFloat.render();
        }
      } catch (error) {
        await InvestigationFloat.release();
        if (generation === InvestigationFloat.generation) {
          InvestigationFloat.setHint(floatErrorHint((error as BusinessError).code || 0));
        }
      } finally {
        AppStorage.setOrCreate('investigation_float_busy', false);
      }
    });
  }

  static async returnToInvestigation(): Promise<void> {
    if (InvestigationFloat.restoring) return;
    const snapshot = floatSnapshot(InvestigationFloat.dashboard, InvestigationFloat.selected,
      InvestigationFloat.synchronizedAt, Date.now(), InvestigationFloat.failed, InvestigationFloat.frozenAt);
    if (!AppStorage.get<string>('access_token')) { await InvestigationFloat.close(); return; }
    InvestigationFloat.restoring = true;
    try {
      if (deviceInfo.apiAvailable('26.0.0') && InvestigationFloat.controller) {
        const params: Record<string, Object> = {};
        if (snapshot.taskId) {
          params['fromInvestigationCard'] = 'true';
          params['workspaceId'] = snapshot.workspaceId.toString();
          params['groupId'] = snapshot.groupId.toString();
          params['conversationId'] = snapshot.conversationId;
        }
        await InvestigationFloat.controller.restoreMainWindow(params);
        await InvestigationFloat.close();
      }
    } catch (error) { InvestigationFloat.setHint(floatErrorHint((error as BusinessError).code || 0)); }
    finally { InvestigationFloat.restoring = false; }
  }

  private static stopTimer(): void {
    if (InvestigationFloat.timer) clearInterval(InvestigationFloat.timer);
    InvestigationFloat.timer = 0;
  }

  private static async release(): Promise<void> {
    InvestigationFloat.stopTimer();
    const controller = InvestigationFloat.controller;
    const ball = InvestigationFloat.ball;
    InvestigationFloat.active = false;
    AppStorage.setOrCreate('investigation_float_active', false);
    if (deviceInfo.apiAvailable('26.0.0')) {
      InvestigationFloat.releasing = true;
      let timeout: number = 0;
      const stopped = new Promise<void>((resolve): void => {
        InvestigationFloat.stopSignal = (): void => {
          if ((!controller || InvestigationFloat.viewStopped) && (!ball || InvestigationFloat.ballStopped)) resolve();
        };
        timeout = setTimeout(resolve, 2000);
        InvestigationFloat.stopSignal();
      });
      try { await controller?.stop(); } catch (_error) {}
      try { await ball?.stopFloatingBall(); } catch (_error) {}
      // stop() only requests shutdown; unbind after both native STOPPED callbacks.
      await stopped;
      clearTimeout(timeout);
      InvestigationFloat.stopSignal = undefined;
      try { controller?.offStateChange(); } catch (_error) {}
      try { ball?.off('stateChange'); } catch (_error) {}
      if (controller && ball && InvestigationFloat.viewStopped && InvestigationFloat.ballStopped) {
        try { await floatView.unbind(controller, ball); } catch (_error) {}
      }
    }
    InvestigationFloat.controller = undefined;
    InvestigationFloat.ball = undefined;
    InvestigationFloat.releasing = false;
  }

  static close(): Promise<void> {
    ++InvestigationFloat.generation;
    InvestigationFloat.startSignal?.(false);
    InvestigationFloat.stopTimer();
    InvestigationFloat.active = false;
    AppStorage.setOrCreate('investigation_float_active', false);
    return InvestigationFloat.enqueue(async (): Promise<void> => InvestigationFloat.release());
  }

  static clear(): Promise<void> {
    InvestigationFloat.dashboard = new InvestigationDashboard();
    InvestigationFloat.selected = '';
    InvestigationFloat.preferredConversation = '';
    InvestigationFloat.preferredWorkspace = 0;
    InvestigationFloat.synchronizedAt = 0;
    InvestigationFloat.failed = false;
    InvestigationFloat.frozenAt = 0;
    InvestigationFloat.hint = '';
    InvestigationFloat.storage.setOrCreate('floatTask', new InvestigationFloatSnapshot());
    AppStorage.setOrCreate('investigation_float_hint', '');
    return InvestigationFloat.close();
  }
}
