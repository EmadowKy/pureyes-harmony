import { accessibility } from '@kit.AccessibilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';

function onReduceMotionChanged(enabled: boolean): void {
  AppStorage.setOrCreate('reduce_motion', enabled);
}

export class AppMotion {
  private static listening: boolean = false;

  static start(): void {
    try {
      onReduceMotionChanged(accessibility.isAnimationReduceEnabledSync());
      if (!AppMotion.listening) {
        accessibility.onAnimationReduceStateChange(onReduceMotionChanged);
        AppMotion.listening = true;
      }
    } catch (_error) {
      AppStorage.setOrCreate('reduce_motion', true);
    }
  }

  static stop(): void {
    if (!AppMotion.listening) return;
    try {
      accessibility.offAnimationReduceStateChange(onReduceMotionChanged);
    } catch (_error) {
      // No listener should survive the ability that owns it.
    }
    AppMotion.listening = false;
  }

  static reduced(): boolean {
    return AppStorage.get<boolean>('reduce_motion') === true;
  }

  static duration(milliseconds: number): number {
    return AppMotion.reduced() ? 0 : milliseconds;
  }

  static options(milliseconds: number = 260): AnimateParam {
    return { duration: AppMotion.duration(milliseconds), curve: Curve.Friction };
  }

  static reveal(distance: number = 10): TransitionEffect {
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: AppMotion.reduced() ? 0 : distance }))
      .animation(AppMotion.options());
  }
}

export class NativeMaterial {
  static available(): boolean {
    return deviceInfo.apiAvailable('26.0.0');
  }

  static none(): uiMaterial.Material | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return uiMaterial.Material.empty;
    }
    return undefined;
  }
}

// Apply only to a real bottom TabBar; ordinary Rows are not supported material hosts.
export class FloatingTabsStyle implements AttributeModifier<TabsAttribute> {
  private hidden: boolean;

  constructor(hidden: boolean = false) {
    this.hidden = hidden;
  }

  applyNormalAttribute(tabs: TabsAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      tabs.barFloatingStyle(this.hidden ? undefined : {
        barSideMargin: 16,
        barBottomMargin: 8,
        maskColor: Color.Transparent,
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true
        })
      });
    }
  }
}

export function navigationTab(icon: ResourceStr | TabBarSymbol, label: string): BottomTabBarStyle {
  return new BottomTabBarStyle(icon, label).labelStyle({
    font: { size: 11, weight: FontWeight.Medium },
    selectedColor: $r('app.color.app_nav_text_selected'),
    unselectedColor: $r('app.color.app_nav_text')
  });
}
