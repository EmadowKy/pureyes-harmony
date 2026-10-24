import { InvestigationDashboard, InvestigationTaskSnapshot, taskDuration } from './investigationTaskState';

// Only operational metadata is copied into the cross-application window.
export class InvestigationFloatSnapshot {
  taskId: string = '';
  conversationId: string = '';
  workspaceId: number = 0;
  groupId: number = 0;
  status: string = 'idle';
  stage: string = '暂无调查';
  steps: number = 0;
  duration: string = '00:00';
  position: string = '';
  activeCount: number = 0;
  taskCount: number = 0;
  stale: boolean = false;
  hasSnapshot: boolean = false;
  hint: string = '';
}

export function floatTaskPool(dashboard: InvestigationDashboard): Array<InvestigationTaskSnapshot> {
  const seen: Set<string> = new Set();
  const valid = dashboard.tasks.filter((task: InvestigationTaskSnapshot): boolean => {
    if (!task.taskId || !task.conversationId || !Number.isSafeInteger(task.workspaceId) || task.workspaceId <= 0 ||
      !Number.isSafeInteger(task.groupId) || task.groupId <= 0 || seen.has(task.taskId)) return false;
    seen.add(task.taskId);
    return true;
  });
  return [...valid.filter((task: InvestigationTaskSnapshot): boolean => task.status === 'processing'),
    ...valid.filter((task: InvestigationTaskSnapshot): boolean => task.status !== 'processing')];
}

export function selectFloatTask(dashboard: InvestigationDashboard, selected: string,
  conversationId: string = '', workspaceId: number = 0): string {
  const pool = floatTaskPool(dashboard);
  const preferred = pool.find((task: InvestigationTaskSnapshot): boolean =>
    task.conversationId === conversationId && task.workspaceId === workspaceId);
  if (preferred) return preferred.taskId;
  if (pool.some((task: InvestigationTaskSnapshot): boolean => task.taskId === selected)) return selected;
  return pool.length > 0 ? pool[0].taskId : '';
}

export function nextFloatTask(dashboard: InvestigationDashboard, selected: string, direction: number): string {
  const pool = floatTaskPool(dashboard);
  if (pool.length === 0) return '';
  const index = pool.findIndex((task: InvestigationTaskSnapshot): boolean => task.taskId === selected);
  return pool[(Math.max(0, index) + direction + pool.length) % pool.length].taskId;
}

export function floatSnapshot(dashboard: InvestigationDashboard, selected: string,
  synchronizedAt: number, now: number, failed: boolean, frozenAt: number = 0): InvestigationFloatSnapshot {
  const result = new InvestigationFloatSnapshot();
  const pool = floatTaskPool(dashboard);
  result.taskCount = pool.length;
  result.activeCount = pool.filter((task: InvestigationTaskSnapshot): boolean => task.status === 'processing').length;
  result.hasSnapshot = synchronizedAt > 0;
  result.stale = failed || synchronizedAt <= 0;
  const index = pool.findIndex((task: InvestigationTaskSnapshot): boolean => task.taskId === selected);
  if (index < 0) {
    result.stage = result.hasSnapshot ? '暂无调查' : '正在同步';
    return result;
  }
  const task = pool[index];
  result.stale = result.stale || (task.status === 'processing' && now - synchronizedAt > 20000);
  result.taskId = task.taskId;
  result.conversationId = task.conversationId;
  result.workspaceId = task.workspaceId;
  result.groupId = task.groupId;
  result.status = task.status;
  // Stage is supplied by our task API; never copy the question, answer, or tool arguments.
  result.stage = task.stage.slice(0, 36) || '正在调查';
  result.steps = Number.isFinite(task.steps) ? Math.max(0, Math.floor(task.steps)) : 0;
  // Freeze at the last known display time on failure, instead of jumping back to the server baseline.
  const displayTime = Math.min(now, synchronizedAt + 20000, frozenAt > 0 ? frozenAt : now);
  const increment = task.status === 'processing' && synchronizedAt > 0 ?
    Math.max(0, Math.floor((displayTime - synchronizedAt) / 1000)) : 0;
  result.duration = taskDuration((Number.isFinite(task.elapsedSeconds) ? task.elapsedSeconds : 0) + increment);
  result.position = `${index + 1} / ${pool.length}`;
  return result;
}

export interface FloatWindowSize { width: number; height: number; }
export interface FloatWindowRatio { minRatio: number; maxRatio: number; }
export interface FloatWindowBounds {
  minSize: FloatWindowSize;
  maxSize: FloatWindowSize;
  ratioLimits: Array<FloatWindowRatio>;
}

export function floatWindowSize(limits: FloatWindowBounds, density: number): FloatWindowSize {
  const scale = Number.isFinite(density) && density > 0 ? density : 1;
  const idealWidth = 280 * scale;
  const idealHeight = 220 * scale;
  let best: FloatWindowSize = { width: limits.minSize.width, height: limits.minSize.height };
  let distance = Number.POSITIVE_INFINITY;
  for (const range of limits.ratioLimits) {
    const low = Math.max(range.minRatio, limits.minSize.width / limits.maxSize.height);
    const high = Math.min(range.maxRatio, limits.maxSize.width / limits.minSize.height);
    if (low > high || low <= 0) continue;
    const ratio = Math.min(high, Math.max(low, idealWidth / idealHeight));
    const height = Math.min(limits.maxSize.height, limits.maxSize.width / ratio,
      Math.max(limits.minSize.height, limits.minSize.width / ratio, idealHeight));
    const candidate: FloatWindowSize = { width: Math.round(height * ratio), height: Math.round(height) };
    const roundedRatio = candidate.width / candidate.height;
    if (candidate.width < limits.minSize.width || candidate.width > limits.maxSize.width ||
      candidate.height < limits.minSize.height || candidate.height > limits.maxSize.height ||
      roundedRatio < range.minRatio || roundedRatio > range.maxRatio) continue;
    const score = Math.abs(candidate.width - idealWidth) + Math.abs(candidate.height - idealHeight);
    if (score < distance) { best = candidate; distance = score; }
  }
  return best;
}

export function floatStatusLabel(status: string): string {
  if (status === 'processing') return '调查进行中';
  if (status === 'completed') return '调查已完成';
  if (status === 'failed') return '调查失败';
  if (status === 'cancelled' || status === 'stopped') return '调查已停止';
  return '清眸调查';
}

// Clock ticks and step counts must not replay a task-switch animation.
export function floatMotionKey(task: InvestigationFloatSnapshot): string {
  return `${task.taskId}:${task.status}:${task.stage}:${task.stale}`;
}

export function floatErrorHint(code: number): string {
  if (code === 201) return '未获得闪控权限，请在系统设置中允许；若未显示权限入口，需检查应用签名授权。';
  if (code === 801) return '当前设备不支持闪控，请使用应用内进度或任务通知。';
  if (code === 1300034) return '请先关闭本应用的画中画或其他悬浮窗口，再开启闪控。';
  if (code === 1300033) return '请保持清眸在前台，然后重新开启闪控。';
  if (code === 1300032) return '暂时无法返回应用，请从桌面打开清眸。';
  return '闪控暂不可用，请重试；调查仍在服务器继续。';
}
