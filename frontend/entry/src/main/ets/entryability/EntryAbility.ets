import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SecurityUtil } from '../utils/security';
import { InvestigationTaskCenter } from '../utils/investigationTasks';
import { CaptureProtection } from '../utils/captureProtection';

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
    CaptureProtection.unbind();
    this.mainStage = undefined;
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const route = this.cardTarget(want);
    if (!route || !this.mainStage) return;
    this.mainStage.getMainWindow().then((win: window.Window): void => {
      win.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' }).then((): void => {
        AppStorage.setOrCreate('widget_route', route);
      }).catch((error: Object): void => {
        hilog.error(DOMAIN, 'InvestigationCard', 'Failed to open index: %{public}s', JSON.stringify(error));
      });
    }).catch((error: Object): void => {
      hilog.error(DOMAIN, 'InvestigationCard', 'Failed to open investigation: %{public}s', JSON.stringify(error));
    });
  }

  onForeground(): void {
    InvestigationTaskCenter.start(this.context);
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    AppStorage.setOrCreate('session_check_flag', Date.now());
  }

  onBackground(): void {
    InvestigationTaskCenter.setForeground(false);
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
