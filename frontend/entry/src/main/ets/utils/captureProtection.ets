import { window } from '@kit.ArkUI';

export class CaptureProtection {
  private static mainWindow: window.Window | undefined = undefined;
  private static generation: number = 0;
  private static pending: Promise<void> = Promise.resolve();

  static async bind(win: window.Window): Promise<void> {
    CaptureProtection.mainWindow = win;
    await CaptureProtection.apply(false);
  }

  static async apply(allowed: boolean): Promise<void> {
    const generation = ++CaptureProtection.generation;
    const win = CaptureProtection.mainWindow;
    const operation = CaptureProtection.pending.catch((): void => {}).then(async (): Promise<void> => {
      if (generation !== CaptureProtection.generation) return;
      if (win) await win.setWindowPrivacyMode(!allowed);
      if (generation === CaptureProtection.generation) {
        AppStorage.setOrCreate('screen_capture_allowed', allowed);
      }
    });
    CaptureProtection.pending = operation;
    await operation;
  }

  static unbind(): void {
    CaptureProtection.mainWindow = undefined;
    CaptureProtection.generation += 1;
    AppStorage.setOrCreate('screen_capture_allowed', false);
  }
}
