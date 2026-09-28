export class InvestigationTaskSnapshot {
  taskId: string = '';
  conversationId: string = '';
  workspaceId: number = 0;
  title: string = '视频调查';
  status: string = 'idle';
  stage: string = '等待调查';
  steps: number = 0;
  elapsedSeconds: number = 0;
  updatedAt: string = '';
}
export class InvestigationDashboard {
  tasks: Array<InvestigationTaskSnapshot> = [];
  activeCount: number = 0;
  completedCount: number = 0;
  conversationCount: number = 0;
  updatedAt: string = '';
}
export function parseInvestigationDashboard(data: Record<string, Object>): InvestigationDashboard {
  const result = new InvestigationDashboard();
  result.tasks = ((data['tasks'] as Array<Record<string, Object>>) || []).map((raw: Record<string, Object>): InvestigationTaskSnapshot => {
    const task = new InvestigationTaskSnapshot();
    task.taskId = (raw['task_id'] as string) || '';
    task.conversationId = (raw['conversation_id'] as string) || '';
    task.workspaceId = (raw['workspace_id'] as number) || 0;
    task.title = (raw['title'] as string) || '视频调查';
    task.status = (raw['status'] as string) || 'idle';
    task.stage = (raw['stage'] as string) || '等待调查';
    task.steps = (raw['steps'] as number) || 0;
    task.elapsedSeconds = Math.max(0, (raw['elapsed_seconds'] as number) || 0);
    task.updatedAt = (raw['updated_at'] as string) || '';
    return task;
  });
  result.activeCount = (data['active_count'] as number) || 0;
  result.completedCount = (data['completed_count'] as number) || 0;
  result.conversationCount = (data['conversation_count'] as number) || 0;
  result.updatedAt = new Date().toISOString();
  return result;
}
export function taskPool(dashboard: InvestigationDashboard): Array<InvestigationTaskSnapshot> {
  const active = dashboard.tasks.filter((task: InvestigationTaskSnapshot): boolean => task.status === 'processing');
  return active.length > 0 ? active : dashboard.tasks;
}
export function taskDuration(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds));
  return `${Math.floor(whole / 60).toString().padStart(2, '0')}:${(whole % 60).toString().padStart(2, '0')}`;
}
