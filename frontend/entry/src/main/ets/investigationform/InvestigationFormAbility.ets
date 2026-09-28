import { formBindingData, formInfo, FormExtensionAbility } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { InvestigationCard } from '../utils/investigationCard';
import { HttpUtil } from '../utils/http';
import { SecurityUtil } from '../utils/security';
import { parseInvestigationDashboard } from '../utils/investigationTaskState';

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
    InvestigationCard.attach(this.context, formId).catch((error: Object): void => {
      console.warn('[InvestigationCard] refresh failed', JSON.stringify(error));
    });
  }

  onRemoveForm(formId: string): void {
    InvestigationCard.detach(this.context, formId).catch((error: Object): void => {
      console.warn('[InvestigationCard] remove failed', JSON.stringify(error));
    });
  }

  onFormEvent(formId: string, message: string): void {
    this.handleEvent(formId, message).catch((error: Object): void => {
      console.warn('[InvestigationCard] event failed', JSON.stringify(error));
    });
  }

  private async handleEvent(formId: string, message: string): Promise<void> {
    await InvestigationCard.attach(this.context, formId);
    const value = JSON.parse(message) as Record<string, Object>;
    const params = (value['params'] as Record<string, Object>) || value;
    const command = params['command'] as string;
    if (command === 'next' || command === 'previous') {
      await InvestigationCard.cycle(this.context, formId, command === 'next' ? 1 : -1);
    } else if (command === 'refresh') {
      await SecurityUtil.initSecureState();
      if (!AppStorage.get<string>('access_token')) {
        await InvestigationCard.clear(this.context);
      } else {
        const res = await HttpUtil.get('/workspaces/agent/tasks');
        if (res.code === 0 && res.data) {
          await InvestigationCard.publishDashboard(this.context,
            parseInvestigationDashboard(JSON.parse(res.data) as Record<string, Object>));
        }
      }
      await InvestigationCard.refresh(this.context, formId);
    }
  }
}
