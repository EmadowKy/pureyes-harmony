import { common } from '@kit.AbilityKit'

export const DOCUMENTATION_URL = 'http://116.62.178.139/'

export async function openDocumentation(context: common.UIAbilityContext): Promise<void> {
  await context.startAbility({
    action: 'ohos.want.action.viewData',
    entities: ['entity.system.browsable'],
    uri: DOCUMENTATION_URL
  })
}
