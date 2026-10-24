import { common, scriptManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { InvestigationSkill, InvestigationSkillResult } from '../../../src/main/ets/utils/investigationSkill';

export default class PureyesInvestigationSkill {
  public async getInvestigationProgress(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    if (deviceInfo.apiAvailable('26.0.0')) {
      const result = await InvestigationSkill.execute(info.context as common.UIAbilityContext, 'progress', argv);
      await this.report(info, result);
    }
  }

  public async openInvestigation(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    if (deviceInfo.apiAvailable('26.0.0')) {
      const result = await InvestigationSkill.execute(info.context as common.UIAbilityContext, 'open', argv);
      await this.report(info, result);
    }
  }

  private async report(info: scriptManager.ArkTSScriptInfo, result: InvestigationSkillResult): Promise<void> {
    if (deviceInfo.apiAvailable('26.0.0')) {
      try {
        await scriptManager.completeArkTSScriptInApp(info.context, info.requestCode, result);
      } catch (_error) {
        console.warn('[InvestigationSkill] Unable to deliver the invocation result');
      }
    }
  }
}
