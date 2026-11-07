import { AbilityConstant, abilityAccessCtrl, common } from '@kit.AbilityKit';
import { getBaseUrl } from './http';

export class InvestigationHandoffState {
  version: number = 1;
  server: string = '';
  groupId: number = 0;
  workspaceId: number = 0;
  conversationId: string = '';
  segmentId: number = 0;
  seconds: number = 0;
  draft: string = '';
  createdAt: number = 0;
}

// A small, explicit contract: credentials, signed media URLs and model keys never migrate.
export function parseHandoff(raw: string, server: string, now: number): InvestigationHandoffState | undefined {
  if (!raw || raw.length > 16000) return undefined;
  try {
    const data = JSON.parse(raw) as Record<string, Object>;
    if (data['version'] !== 1 || data['server'] !== server ||
      !Number.isSafeInteger(data['workspaceId'] as number) || (data['workspaceId'] as number) <= 0 ||
      !Number.isSafeInteger(data['groupId'] as number) || (data['groupId'] as number) <= 0 ||
      typeof data['conversationId'] !== 'string' ||
      !/^[a-zA-Z0-9_-]{1,128}$/.test(data['conversationId'] as string) ||
      typeof data['createdAt'] !== 'number' || !Number.isFinite(data['createdAt'] as number) ||
      now - (data['createdAt'] as number) > 600000 || (data['createdAt'] as number) > now + 60000) return undefined;
    const state = new InvestigationHandoffState();
    state.server = server;
    state.workspaceId = data['workspaceId'] as number;
    state.groupId = data['groupId'] as number;
    state.conversationId = data['conversationId'] as string;
    const id = data['segmentId'] as number;
    state.segmentId = Number.isSafeInteger(id) && id > 0 ? id : 0;
    const seconds = data['seconds'] as number;
    state.seconds = typeof seconds === 'number' && Number.isFinite(seconds) && seconds >= 0 ? seconds : 0;
    state.draft = typeof data['draft'] === 'string' ? (data['draft'] as string).slice(0, 4000) : '';
    state.createdAt = data['createdAt'] as number;
    return state;
  } catch (_error) { return undefined; }
}

export class InvestigationHandoff {
  private static context: common.UIAbilityContext | undefined;
  private static current: InvestigationHandoffState | undefined;
  private static generation: number = 0;
  private static pending: Promise<void> = Promise.resolve();
  private static advertised: boolean = false;
  private static requested: boolean = false;
  private static enabled: boolean = false;
  private static scopeRevision: number = 0;

  static bind(context: common.UIAbilityContext): void { InvestigationHandoff.context = context; }

  static update(state: InvestigationHandoffState | undefined): void {
    const previous = InvestigationHandoff.current;
    if (!state || !previous || state.groupId !== previous.groupId || state.workspaceId !== previous.workspaceId ||
      state.conversationId !== previous.conversationId || state.server !== previous.server) {
      InvestigationHandoff.enabled = false;
      InvestigationHandoff.scopeRevision++;
    }
    InvestigationHandoff.current = state;
    InvestigationHandoff.sync();
  }

  private static sync(): void {
    const active = InvestigationHandoff.enabled && !!InvestigationHandoff.current &&
      !!AppStorage.get<string>('access_token');
    if (active === InvestigationHandoff.requested) return;
    InvestigationHandoff.requested = active;
    const generation = ++InvestigationHandoff.generation;
    InvestigationHandoff.pending = InvestigationHandoff.pending.catch((): void => {}).then(async (): Promise<void> => {
      if (generation !== InvestigationHandoff.generation || !InvestigationHandoff.context) return;
      try {
        await InvestigationHandoff.context.setMissionContinueState(active ?
          AbilityConstant.ContinueState.ACTIVE : AbilityConstant.ContinueState.INACTIVE);
        if (generation === InvestigationHandoff.generation) InvestigationHandoff.advertised = active;
      } catch (_error) {
        if (generation === InvestigationHandoff.generation) {
          InvestigationHandoff.advertised = false;
          InvestigationHandoff.requested = false;
          InvestigationHandoff.enabled = false;
        }
      }
    });
  }

  static async enable(): Promise<void> {
    const context = InvestigationHandoff.context;
    if (!context || !InvestigationHandoff.current || !AppStorage.get<string>('access_token')) return;
    const scopeRevision = InvestigationHandoff.scopeRevision;
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        context, ['ohos.permission.DISTRIBUTED_DATASYNC']);
      if (scopeRevision !== InvestigationHandoff.scopeRevision || !AppStorage.get<string>('access_token')) return;
      if (result.authResults[0] !== 0) {
        InvestigationHandoff.enabled = false;
        InvestigationHandoff.sync();
        AppStorage.setOrCreate('continuation_hint', '未允许多设备协同，可稍后重新开启');
        return;
      }
      InvestigationHandoff.enabled = true;
      InvestigationHandoff.sync();
      await InvestigationHandoff.pending;
      if (scopeRevision === InvestigationHandoff.scopeRevision)
        AppStorage.setOrCreate('continuation_hint', InvestigationHandoff.advertised ?
          '已允许接续，请在同一华为账号的附近设备使用系统接续入口' : '当前设备暂时无法开启接续');
    } catch (_error) {
      if (scopeRevision === InvestigationHandoff.scopeRevision)
        AppStorage.setOrCreate('continuation_hint', '当前设备暂时无法开启接续');
    }
  }

  static snapshot(): string {
    const state = InvestigationHandoff.current;
    if (!state || !InvestigationHandoff.enabled || !InvestigationHandoff.advertised || !AppStorage.get<string>('access_token') ||
      state.server !== getBaseUrl().replace(/\/+$/, '')) return '';
    state.createdAt = Date.now();
    return JSON.stringify(state);
  }

  static receive(raw: string): void {
    AppStorage.setOrCreate('handoff_incoming', raw.length <= 16000 ? raw : '');
  }

  static clear(): void {
    InvestigationHandoff.update(undefined);
    AppStorage.setOrCreate('handoff_incoming', '');
    AppStorage.setOrCreate('handoff_restore', '');
    AppStorage.setOrCreate('continuation_hint', '');
  }
}
