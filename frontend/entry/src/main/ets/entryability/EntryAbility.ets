import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SecurityUtil } from '../utils/security';
import { InvestigationTaskCenter } from '../utils/investigationTasks';
import { CaptureProtection } from '../utils/captureProtection';
import { InvestigationFloat } from '../utils/investigationFloat';
import { AppMotion } from '../utils/appMotion';
import { AntiPeep } from '../utils/antiPeep';
import { VideoShare } from '../utils/videoShare';
import { InvestigationHandoff } from '../utils/investigationHandoff';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainStage?: window.WindowStage;

  private cardTarget(want: Want): string {
    const params = want.parameters;
    if (params?.['fromInvestigationCard'] !== 'true') return '';
    const workspaceId = Number(params['workspaceId']);
    const groupId = Number(params['groupId'] || 0);
    const conversationId = (params['conversationId'] as string) || '';
    if (!Number.isSafeInteger(workspaceId) || workspaceId < 0 ||
        conversationId.length > 128) return '';
    return JSON.stringify({ workspaceId, groupId, conversationId });
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppMotion.start();
    InvestigationHandoff.bind(this.context);
    this.receiveContinuation(want, launchParam);
    VideoShare.receiveWant(want);
    const route = this.cardTarget(want);
    if (route) AppStorage.setOrCreate('widget_route', route);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    AntiPeep.clear();
    VideoShare.clear();
    InvestigationHandoff.clear();
    AppMotion.stop();
    InvestigationFloat.clear();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainStage = windowStage;
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    SecurityUtil.initSecureState().then((): void => {
      InvestigationTaskCenter.start(this.context);
      this.loadMainContent(windowStage);
    }).catch((err: Object): void => {
      hilog.warn(DOMAIN, 'SecurityState', 'Secure state initialization failed: %{public}s', JSON.stringify(err));
      this.loadMainContent(windowStage);
    });
  }

  private async loadMainContent(windowStage: window.WindowStage): Promise<void> {
    try {
      const win = await windowStage.getMainWindow();
      await CaptureProtection.bind(win);
      AntiPeep.bind(win, this.context);
      VideoShare.bind(this.context, win.getWindowProperties().id);
    } catch (error) {
      hilog.error(DOMAIN, 'PrivacyMode', 'Unable to initialize capture protection');
      return;
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

    });
  }

  onWindowStageDestroy(): void {
    AntiPeep.clear();
    VideoShare.setForeground(false);
    InvestigationFloat.clear();
    CaptureProtection.unbind();
    this.mainStage = undefined;
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const continuation = this.continuationPayload(want, launchParam);
    VideoShare.receiveWant(want);
    const route = this.cardTarget(want);
    if (!route && !continuation) return;
    if (!this.mainStage) {
      if (continuation) InvestigationHandoff.receive(continuation);
      else AppStorage.setOrCreate('widget_route', route);
      return;
    }
    this.mainStage.getMainWindow().then((win: window.Window): void => {
      win.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' }).then((): void => {
        if (continuation) InvestigationHandoff.receive(continuation);
        else AppStorage.setOrCreate('widget_route', route);
      }).catch((error: Object): void => {
        hilog.error(DOMAIN, 'InvestigationCard', 'Failed to open index: %{public}s', JSON.stringify(error));
      });
    }).catch((error: Object): void => {
      hilog.error(DOMAIN, 'InvestigationCard', 'Failed to open investigation: %{public}s', JSON.stringify(error));
    });
  }

  onForeground(): void {
    AntiPeep.setForeground(true);
    VideoShare.setForeground(true);
    InvestigationTaskCenter.start(this.context);
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    AppStorage.setOrCreate('session_check_flag', Date.now());
  }

  onBackground(): void {
    AntiPeep.setForeground(false);
    VideoShare.setForeground(false);
    InvestigationTaskCenter.setForeground(false);
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  private receiveContinuation(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const raw = this.continuationPayload(want, launchParam);
    if (raw) InvestigationHandoff.receive(raw);
  }

  private continuationPayload(want: Want, launchParam: AbilityConstant.LaunchParam): string {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) return '';
    const raw = want.parameters?.['pureyes.handoff'];
    return typeof raw === 'string' && raw.length <= 16000 ? raw : '';
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    const snapshot = InvestigationHandoff.snapshot();
    if (!snapshot) return AbilityConstant.OnContinueResult.REJECT;
    wantParam['pureyes.handoff'] = snapshot;
    wantParam['ohos.extra.param.key.supportContinuePageStack'] = false;
    wantParam['ohos.extra.param.key.supportContinueSourceExit'] = false;
    return AbilityConstant.OnContinueResult.AGREE;
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    this.onWindowStageCreate(windowStage);
  }
}
