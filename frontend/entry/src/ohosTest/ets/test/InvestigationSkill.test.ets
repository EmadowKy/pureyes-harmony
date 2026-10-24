import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { InvestigationSkill } from '../../../main/ets/utils/investigationSkill';

// Explicit device integration run only; ordinary test runs never require a server or saved login.
export default function investigationSkillIntegration(): void {
  const args = abilityDelegatorRegistry.getArguments();
  if (args.parameters['-s pureyesSkillIntegration'] !== 'true') return;
  describe('InvestigationSkillDevice', (): void => {
    it('readsFreshAuthorizedProgressAndOpensExistingConversation', 0, async (): Promise<void> => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: args.bundleName, abilityName: 'EntryAbility' });
      let entryContext: common.UIAbilityContext | undefined = undefined;
      for (let attempt = 0; attempt < 30; attempt++) {
        try {
          const ability = await delegator.getCurrentTopAbility();
          if (ability.context.abilityInfo.name === 'EntryAbility') {
            entryContext = ability.context;
            break;
          }
        } catch (_error) {}
        await new Promise<void>((resolve): void => { setTimeout((): void => resolve(), 100); });
      }
      if (!entryContext) throw new Error('EntryAbility did not reach the foreground');
      const context = entryContext;
      const progress = await InvestigationSkill.execute(context, 'progress', []);
      if (progress.code !== 0) console.info(`[SkillDevice] Progress failed: ${progress.result['errCode']}`);
      expect(progress.code).assertEqual(0);
      const data = progress.result['data'] as Record<string, Object>;
      const tasks = data['tasks'] as Array<Record<string, Object>>;
      expect(Array.isArray(tasks)).assertTrue();
      expect(tasks.length > 0).assertTrue();
      const id = tasks[0]['conversationId'] as string;
      const selected = await InvestigationSkill.execute(context, 'progress', [id]);
      expect(selected.code).assertEqual(0);
      const opened = await InvestigationSkill.execute(context, 'open', [id]);
      expect(opened.code).assertEqual(0);
      const result = opened.result['data'] as Record<string, Object>;
      expect(result['opened'] as boolean).assertTrue();
      const missing = await InvestigationSkill.execute(context, 'open', ['integration-missing-conversation']);
      expect(missing.result['errCode'] as string).assertEqual('ERR_NOT_FOUND');
    });
  });
}
