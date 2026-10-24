import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HttpUtil, getBaseUrl } from './http';
import { SecurityUtil } from './security';
import { InvestigationDashboard, InvestigationTaskSnapshot, parseInvestigationDashboard, taskDuration } from './investigationTaskState';

export class InvestigationSkillResult {
  code: number = -1;
  result: Record<string, Object> = {};
}

export function skillFailure(code: string, suggestion: string): InvestigationSkillResult {
  const result = new InvestigationSkillResult();
  const payload: Record<string, Object> = { 'type': 'result', 'status': 'failed', 'errCode': code, 'suggestion': suggestion };
  result.result = payload;
  return result;
}

function success(data: Record<string, Object>): InvestigationSkillResult {
  const result = new InvestigationSkillResult();
  result.code = 0;
  const payload: Record<string, Object> = { 'type': 'result', 'status': 'success', 'data': data };
  result.result = payload;
  return result;
}

export function matchSkillTasks(dashboard: InvestigationDashboard, query: string): Array<InvestigationTaskSnapshot> {
  const valid = dashboard.tasks.filter((task: InvestigationTaskSnapshot): boolean =>
    Number.isSafeInteger(task.workspaceId) && task.workspaceId > 0 &&
    Number.isSafeInteger(task.groupId) && task.groupId > 0 &&
    /^[a-zA-Z0-9_-]{1,128}$/.test(task.conversationId));
  if (!query) return valid;
  const exact = valid.filter((task: InvestigationTaskSnapshot): boolean =>
    task.conversationId === query || task.title === query);
  if (exact.length > 0) return exact;
  return valid.filter((task: InvestigationTaskSnapshot): boolean =>
    task.title.toLocaleLowerCase().includes(query.toLocaleLowerCase()));
}

function taskSummary(task: InvestigationTaskSnapshot): Record<string, Object> {
  const summary: Record<string, Object> = { 'conversationId': task.conversationId, 'title': task.title, 'status': task.status,
    'stage': task.stage, 'steps': task.steps, 'elapsed': taskDuration(task.elapsedSeconds) };
  return summary;
}

export class InvestigationSkill {
  static async execute(context: common.UIAbilityContext, action: string, argv: Array<string>): Promise<InvestigationSkillResult> {
    if ((action !== 'progress' && action !== 'open') || argv.length > 1 ||
        (argv.length === 1 && typeof argv[0] !== 'string')) {
      return skillFailure('ERR_INVALID_PARAMS', '请提供一项调查名称或编号，也可以查询整体进度');
    }
    const query = (argv[0] || '').trim();
    if (query.length > 160 || /[\u0000-\u001f]/.test(query)) {
      return skillFailure('ERR_INVALID_PARAMS', '调查名称或编号应为 160 字以内的文本');
    }
    try {
      await SecurityUtil.initSecureState();
      const token = AppStorage.get<string>('access_token') || '';
      const server = getBaseUrl().replace(/\/+$/, '');
      const sessionServer = AppStorage.get<string>('session_server_url') || '';
      if (!token || server !== sessionServer) {
        return skillFailure('ERR_LOGIN_REQUIRED', '请先打开清眸，登录当前服务器后再试');
      }
      // Always obtain a fresh permission-filtered response; never answer from a desktop snapshot.
      const response = await HttpUtil.get('/workspaces/agent/tasks');
      if (token !== AppStorage.get<string>('access_token') || server !== getBaseUrl().replace(/\/+$/, '') ||
          sessionServer !== AppStorage.get<string>('session_server_url')) {
        return skillFailure('ERR_LOGIN_REQUIRED', '账号或服务器已切换，请在清眸中确认登录状态');
      }
      if (response.httpStatus === 401 || response.httpStatus === 403) {
        return skillFailure('ERR_LOGIN_REQUIRED', '登录已失效或没有访问权限，请在清眸中重新确认');
      }
      if (response.code !== 0 || !response.data) {
        return skillFailure('ERR_UNAVAILABLE', '暂时无法读取调查进度，请检查网络后重试');
      }
      const raw = JSON.parse(response.data) as Record<string, Object>;
      if (!Array.isArray(raw['tasks']) || typeof raw['active_count'] !== 'number' ||
          typeof raw['completed_count'] !== 'number' || typeof raw['conversation_count'] !== 'number') {
        return skillFailure('ERR_UNAVAILABLE', '调查状态格式异常，请稍后重试');
      }
      const dashboard = parseInvestigationDashboard(raw);
      const matches = matchSkillTasks(dashboard, query);
      if (query && matches.length === 0) {
        return skillFailure('ERR_NOT_FOUND', '最近调查中没有找到这项记录，请打开清眸确认调查名称');
      }
      if (action === 'progress' && !query) {
        const data: Record<string, Object> = { 'activeCount': dashboard.activeCount, 'completedCount': dashboard.completedCount,
          'conversationCount': dashboard.conversationCount, 'checkedAt': dashboard.updatedAt,
          'scope': '当前账号可访问的运行中调查和最近结束记录',
          'tasks': matches.slice(0, 20).map((task: InvestigationTaskSnapshot): Record<string, Object> => taskSummary(task)) };
        return success(data);
      }
      if (matches.length === 0) return skillFailure('ERR_NOT_FOUND', '还没有可继续的调查，请先在清眸中选择片段并提问');
      if (matches.length > 1) {
        const result = skillFailure('ERR_AMBIGUOUS', '有多项调查符合要求，请选择具体调查后再试');
        const data: Record<string, Object> = { 'candidates': matches.slice(0, 20).map((task: InvestigationTaskSnapshot): Record<string, Object> => taskSummary(task)) };
        result.result['data'] = data;
        return result;
      }
      const task = matches[0];
      if (action === 'progress') {
        const data: Record<string, Object> = { 'task': taskSummary(task), 'checkedAt': dashboard.updatedAt };
        return success(data);
      }
      try {
        await context.startAbility({
          bundleName: context.applicationInfo.name,
          abilityName: 'EntryAbility',
          parameters: { fromInvestigationCard: 'true', workspaceId: task.workspaceId.toString(),
            groupId: task.groupId.toString(), conversationId: task.conversationId }
        });
      } catch (error) {
        console.warn(`[InvestigationSkill] Unable to open investigation, code=${(error as BusinessError).code}`);
        return skillFailure('ERR_OPEN_FAILED', '未能打开调查，请打开清眸后重试');
      }
      const data: Record<string, Object> = { 'task': taskSummary(task), 'opened': true };
      return success(data);
    } catch (_error) {
      return skillFailure('ERR_UNAVAILABLE', '暂时无法读取调查进度，请稍后重试');
    }
  }
}
