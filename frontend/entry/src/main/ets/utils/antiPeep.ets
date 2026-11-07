import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

// Detection belongs to the system. The application never opens a camera or stores faces.
export class AntiPeep {
  private static win: window.Window | undefined = undefined;
  private static context: common.UIAbilityContext | undefined = undefined;
  private static epoch: number = 0;
  private static statusRevision: number = 0;
  private static listening: boolean = false;
  private static foreground: boolean = true;
  private static callback = (status: dlpAntiPeep.DlpAntiPeepStatus): void => {
    AntiPeep.onStatus(status);
  };

  static bind(win: window.Window, context: common.UIAbilityContext): void {
    AntiPeep.win = win;
    AntiPeep.context = context;
    AntiPeep.foreground = true;
    AntiPeep.refresh();
  }

  static setForeground(value: boolean): void {
    AntiPeep.foreground = value;
    if (value) AntiPeep.refresh(); else AntiPeep.unsubscribe();
  }

  private static unsubscribe(): void {
    AntiPeep.epoch++;
    if (AntiPeep.listening) {
      try { dlpAntiPeep.off('dlpAntiPeep', AntiPeep.callback); } catch (_error) {}
    }
    AntiPeep.listening = false;
  }

  static async refresh(): Promise<void> {
    AntiPeep.unsubscribe();
    const epoch = AntiPeep.epoch;
    if (!AntiPeep.foreground || !AntiPeep.win) return;
    if (!canIUse('SystemCapability.Security.DlpAntiPeep')) {
      AppStorage.setOrCreate('anti_peep_state', 'unsupported');
      return;
    }
    try {
      const enabled = await dlpAntiPeep.isDlpAntiPeepSwitchOn();
      if (epoch !== AntiPeep.epoch || !AntiPeep.foreground) return;
      if (!enabled) {
        AppStorage.setOrCreate('anti_peep_state', 'disabled');
        return;
      }
      dlpAntiPeep.on('dlpAntiPeep', AntiPeep.callback);
      AntiPeep.listening = true;
      AntiPeep.onStatus(dlpAntiPeep.getDlpAntiPeepInfo());
    } catch (error) {
      if (epoch !== AntiPeep.epoch) return;
      AntiPeep.unsubscribe();
      const code = (error as BusinessError).code;
      AppStorage.setOrCreate('anti_peep_state', code === 801 ? 'unsupported' :
        code === 201 ? 'permission' : 'error');
    }
  }

  private static onStatus(status: dlpAntiPeep.DlpAntiPeepStatus): void {
    if (!AntiPeep.foreground || !AntiPeep.listening || !AntiPeep.win) return;
    const revision = ++AntiPeep.statusRevision;
    if (status === dlpAntiPeep.DlpAntiPeepStatus.PASS) {
      AppStorage.setOrCreate('anti_peep_state', 'active');
      return;
    }
    if (status !== dlpAntiPeep.DlpAntiPeepStatus.HIDE) return;
    const epoch = AntiPeep.epoch;
    AppStorage.setOrCreate('anti_peep_state', 'shielded');
    // The system mask also covers dialogs, native video and web-rendered answers.
    dlpAntiPeep.setAntiPeepMaskLayer(AntiPeep.win.getWindowProperties().id).catch((): void => {
      if (epoch === AntiPeep.epoch && revision === AntiPeep.statusRevision) {
        AppStorage.setOrCreate('anti_peep_state', 'error');
      }
    });
  }

  static async enable(): Promise<void> {
    if (!AntiPeep.context || !canIUse('SystemCapability.Security.DlpAntiPeep')) {
      AppStorage.setOrCreate('anti_peep_state', 'unsupported');
      return;
    }
    try {
      await dlpAntiPeep.requestAntiPeepOptions(AntiPeep.context);
      await AntiPeep.refresh();
    } catch (error) {
      const code = (error as BusinessError).code;
      AppStorage.setOrCreate('anti_peep_state', code === 801 ? 'unsupported' :
        code === 201 ? 'permission' : code === 1020600004 ? 'face_required' : 'error');
    }
  }

  static clear(): void {
    AntiPeep.unsubscribe();
    AntiPeep.win = undefined;
    AntiPeep.context = undefined;
    AppStorage.setOrCreate('anti_peep_state', 'checking');
  }
}
