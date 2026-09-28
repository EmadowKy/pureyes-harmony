import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { InvestigationDashboard, InvestigationTaskSnapshot, taskPool, taskDuration } from './investigationTaskState';

const FILE_NAME = 'investigation_card';
const REGISTRY_FILE = 'investigation_card_registry';
const SELECTION_FILE = 'investigation_card_selection';
const FORM_IDS_KEY = 'form_ids';
export class InvestigationCardSnapshot extends InvestigationTaskSnapshot {}

function binding(dashboard: InvestigationDashboard, selectedId: string = ''): formBindingData.FormBindingData {
  const pool = taskPool(dashboard);
  const index = Math.max(0, pool.findIndex((task: InvestigationTaskSnapshot): boolean => task.taskId === selectedId));
  const task = pool[index] || new InvestigationTaskSnapshot();
  return formBindingData.createFormBindingData({
    status: task.status, stage: task.stage, steps: task.steps.toString(),
    title: task.title, elapsed: taskDuration(task.elapsedSeconds),
    updatedAt: dashboard.updatedAt ? `${new Date(dashboard.updatedAt).getHours().toString().padStart(2, '0')}:${new Date(dashboard.updatedAt).getMinutes().toString().padStart(2, '0')}` : '',
    workspaceId: task.workspaceId.toString(), groupId: task.groupId.toString(), conversationId: task.conversationId,
    activeCount: dashboard.activeCount.toString(), completedCount: dashboard.completedCount.toString(),
    conversationCount: dashboard.conversationCount.toString(),
    taskPosition: pool.length > 0 ? (index + 1).toString() : '0', taskCount: pool.length.toString()
  });
}
export class InvestigationCard {
  private static pending: Promise<void> = Promise.resolve();
  static empty(): formBindingData.FormBindingData { return binding(new InvestigationDashboard()); }
  private static async store(context: common.Context, name: string = FILE_NAME): Promise<preferences.Preferences> {
    // UIAbility and FormExtension run in separate processes. Reload committed data,
    // and keep their independently owned registry/selection outside the dashboard.
    await preferences.removePreferencesFromCache(context, { name });
    return preferences.getPreferences(context, { name });
  }
  private static async ids(context: common.Context): Promise<Array<string>> {
    try {
      const registry = await InvestigationCard.store(context, REGISTRY_FILE);
      let serialized = await registry.get(FORM_IDS_KEY, '') as string;
      if (!serialized) serialized = await (await InvestigationCard.store(context)).get(FORM_IDS_KEY, '[]') as string;
      const data = JSON.parse(serialized) as Array<string>;
      return Array.isArray(data) ? data : [];
    } catch (_error) { return []; }
  }
  static async dashboard(context: common.Context): Promise<InvestigationDashboard> {
    const store = await InvestigationCard.store(context);
    try {
      const data = JSON.parse(await store.get('dashboard', '{}') as string) as InvestigationDashboard;
      return Array.isArray(data.tasks) ? data : new InvestigationDashboard();
    } catch (_error) { return new InvestigationDashboard(); }
  }
  static async attach(context: common.Context, formId: string): Promise<void> {
    const ids = await InvestigationCard.ids(context);
    const store = await InvestigationCard.store(context, REGISTRY_FILE);
    if (ids.indexOf(formId) < 0) {
      ids.push(formId);
      await store.put(FORM_IDS_KEY, JSON.stringify(ids));
      await store.flush();
    }
    await InvestigationCard.refresh(context, formId);
  }
  static async detach(context: common.Context, formId: string): Promise<void> {
    const ids = await InvestigationCard.ids(context);
    const store = await InvestigationCard.store(context, REGISTRY_FILE);
    await store.put(FORM_IDS_KEY, JSON.stringify(ids.filter((id: string): boolean => id !== formId)));
    await store.flush();
    const selection = await InvestigationCard.store(context, SELECTION_FILE);
    await selection.delete(`selected_${formId}`);
    await selection.flush();
  }
  static async refresh(context: common.Context, formId: string): Promise<void> {
    const store = await InvestigationCard.store(context, SELECTION_FILE);
    await formProvider.updateForm(formId, binding(await InvestigationCard.dashboard(context), await store.get(`selected_${formId}`, '') as string));
  }
  static async cycle(context: common.Context, formId: string, direction: number): Promise<void> {
    const pool = taskPool(await InvestigationCard.dashboard(context));
    if (pool.length === 0) return;
    const store = await InvestigationCard.store(context, SELECTION_FILE);
    const selected = await store.get(`selected_${formId}`, '') as string;
    const current = Math.max(0, pool.findIndex((task: InvestigationTaskSnapshot): boolean => task.taskId === selected));
    await store.put(`selected_${formId}`, pool[(current + direction + pool.length) % pool.length].taskId);
    await store.flush();
    await InvestigationCard.refresh(context, formId);
  }
  static async publishDashboard(context: common.Context, dashboard: InvestigationDashboard): Promise<void> {
    const write = InvestigationCard.pending.then(async (): Promise<void> => {
      const store = await InvestigationCard.store(context);
      await store.put('dashboard', JSON.stringify(dashboard));
      await store.flush();
      for (const id of await InvestigationCard.ids(context)) {
        try { await InvestigationCard.refresh(context, id); } catch (_error) {}
      }
    });
    InvestigationCard.pending = write.catch((): void => {});
    await write;
  }
  static async publish(context: common.Context, snapshot: InvestigationCardSnapshot): Promise<void> {
    const dashboard = new InvestigationDashboard();
    if (snapshot.conversationId) dashboard.tasks = [snapshot];
    dashboard.activeCount = snapshot.status === 'processing' ? 1 : 0;
    await InvestigationCard.publishDashboard(context, dashboard);
  }
  static async clear(context: common.Context): Promise<void> {
    await InvestigationCard.publishDashboard(context, new InvestigationDashboard());
  }
}
