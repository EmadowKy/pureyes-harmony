import { formBindingData, formInfo, FormExtensionAbility } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { InvestigationCard } from '../utils/investigationCard';

export default class InvestigationFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = (want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string) || '';
    if (formId) {
      InvestigationCard.attach(this.context, formId).catch((error: Object): void => {
        console.warn('[InvestigationCard] add failed', JSON.stringify(error));
      });
    }
    return InvestigationCard.empty();
  }

  onUpdateForm(formId: string): void {
    InvestigationCard.refresh(this.context, formId).catch((error: Object): void => {
      console.warn('[InvestigationCard] refresh failed', JSON.stringify(error));
    });
  }

  onRemoveForm(formId: string): void {
    InvestigationCard.detach(this.context, formId).catch((error: Object): void => {
      console.warn('[InvestigationCard] remove failed', JSON.stringify(error));
    });
  }
}
