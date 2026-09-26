import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';

const FILE_NAME = 'investigation_card';
const SNAPSHOT_KEY = 'snapshot';
const FORM_IDS_KEY = 'form_ids';

export class InvestigationCardSnapshot {
  status: string = 'idle';
  stage: string = '等待调查';
  steps: number = 0;
  updatedAt: string = '';
  workspaceId: number = 0;
  conversationId: string = '';
}

function binding(snapshot: InvestigationCardSnapshot): formBindingData.FormBindingData {
  return formBindingData.createFormBindingData({
    status: snapshot.status,
    stage: snapshot.stage,
    steps: snapshot.steps.toString(),
    updatedAt: snapshot.updatedAt,
    workspaceId: snapshot.workspaceId.toString(),
    conversationId: snapshot.conversationId
  });
}

export class InvestigationCard {
  private static pending: Promise<void> = Promise.resolve();

  static empty(): formBindingData.FormBindingData {
    return binding(new InvestigationCardSnapshot());
  }

  private static async store(context: common.Context): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, { name: FILE_NAME });
  }

  private static async ids(store: preferences.Preferences): Promise<Array<string>> {
    const serialized = await store.get(FORM_IDS_KEY, '[]') as string;
    try {
      const parsed = JSON.parse(serialized) as Array<string>;
      return Array.isArray(parsed) ? parsed.filter((id: string): boolean => typeof id === 'string') : [];
    } catch (_error) {
      return [];
    }
  }

  static async current(context: common.Context): Promise<InvestigationCardSnapshot> {
    const store = await InvestigationCard.store(context);
    const serialized = await store.get(SNAPSHOT_KEY, '') as string;
    if (!serialized) return new InvestigationCardSnapshot();
    try {
      const value = JSON.parse(serialized) as InvestigationCardSnapshot;
      return value && typeof value.status === 'string' ? value : new InvestigationCardSnapshot();
    } catch (_error) {
      return new InvestigationCardSnapshot();
    }
  }

  static async attach(context: common.Context, formId: string): Promise<void> {
    const store = await InvestigationCard.store(context);
    const ids = await InvestigationCard.ids(store);
    if (ids.indexOf(formId) < 0) {
      ids.push(formId);
      await store.put(FORM_IDS_KEY, JSON.stringify(ids));
      await store.flush();
    }
    await InvestigationCard.refresh(context, formId);
  }

  static async detach(context: common.Context, formId: string): Promise<void> {
    const store = await InvestigationCard.store(context);
    const ids = (await InvestigationCard.ids(store)).filter((id: string): boolean => id !== formId);
    await store.put(FORM_IDS_KEY, JSON.stringify(ids));
    await store.flush();
  }

  static async refresh(context: common.Context, formId: string): Promise<void> {
    const snapshot = await InvestigationCard.current(context);
    await formProvider.updateForm(formId, binding(snapshot));
  }

  static async publish(context: common.Context, snapshot: InvestigationCardSnapshot): Promise<void> {
    const write = InvestigationCard.pending.then(async (): Promise<void> => {
      await InvestigationCard.writeSnapshot(context, snapshot);
    });
    InvestigationCard.pending = write.catch((): void => {});
    await write;
  }

  private static async writeSnapshot(context: common.Context, snapshot: InvestigationCardSnapshot): Promise<void> {
    const store = await InvestigationCard.store(context);
    await store.put(SNAPSHOT_KEY, JSON.stringify(snapshot));
    await store.flush();
    const ids = await InvestigationCard.ids(store);
    for (const id of ids) {
      try {
        await formProvider.updateForm(id, binding(snapshot));
      } catch (_error) {
        // An individual card may have been removed while this update was in flight.
      }
    }
  }

  static async clear(context: common.Context): Promise<void> {
    await InvestigationCard.publish(context, new InvestigationCardSnapshot());
  }
}
