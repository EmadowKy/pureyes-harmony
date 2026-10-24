import { LiveFormExtensionAbility, LiveFormInfo } from '@kit.FormKit';
import { UIExtensionContentSession } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { InvestigationCard } from '../utils/investigationCard';

export default class InvestigationLiveFormAbility extends LiveFormExtensionAbility {
  private generation: number = 0;
  private storage?: LocalStorage;

  onLiveFormCreate(info: LiveFormInfo, session: UIExtensionContentSession): void {
    const generation = ++this.generation;
    this.load(info, session, generation).catch((): void => {
      console.warn('[InvestigationCard] Interactive card unavailable');
    });
  }

  private async load(info: LiveFormInfo, session: UIExtensionContentSession, generation: number): Promise<void> {
    const data = (await InvestigationCard.selectedBinding(this.context, info.formId)).data;
    if (generation !== this.generation) return;
    const values = (typeof data === 'string' ? JSON.parse(data) : data) as Record<string, Object>;
    let reduceMotion = true;
    try { reduceMotion = accessibility.isAnimationReduceEnabledSync(); } catch (_error) {}
    values['reduceMotion'] = reduceMotion;
    this.storage = new LocalStorage(values);
    session.loadContent('pages/InvestigationLiveCard', this.storage);
  }

  onLiveFormDestroy(_info: LiveFormInfo): void {
    this.generation++;
    // Remove displayed task identifiers when the host interrupts or finishes the effect.
    this.storage?.setOrCreate('conversationId', '');
    this.storage?.setOrCreate('title', '视频调查');
    this.storage = undefined;
  }
}
