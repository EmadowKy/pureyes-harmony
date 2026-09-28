import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { InvestigationDashboard, InvestigationTaskSnapshot, taskPool, taskDuration } from './investigationTaskState';

const FILE_NAME = 'investigation_card';
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
  private static async store(context: common.Context): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, { name: FILE_NAME });
  }
  private static async ids(store: preferences.Preferences): Promise<Array<string>> {
    try {
      const data = JSON.parse(await store.get(FORM_IDS_KEY, '[]') as string) as Array<string>;
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
    await store.put(FORM_IDS_KEY, JSON.stringify((await InvestigationCard.ids(store)).filter((id: string): boolean => id !== formId)));
    await store.delete(`selected_${formId}`);
    await store.flush();
  }
  static async refresh(context: common.Context, formId: string): Promise<void> {
    const store = await InvestigationCard.store(context);
    await formProvider.updateForm(formId, binding(await InvestigationCard.dashboard(context), await store.get(`selected_${formId}`, '') as string));
  }
  static async cycle(context: common.Context, formId: string, direction: number): Promise<void> {
    const pool = taskPool(await InvestigationCard.dashboard(context));
    if (pool.length === 0) return;
    const store = await InvestigationCard.store(context);
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
      for (const id of await InvestigationCard.ids(store)) {
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
