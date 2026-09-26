export class ModelConfigOption {
  id: number = 0;
  name: string = '';
  scope: string = 'personal';
  groupId: number = 0;
  baseUrl: string = '';
  model: string = '';
  canEdit: boolean = false;
  apiKeyConfigured: boolean = false;
}

export function parseModelConfig(raw: Record<string, Object>): ModelConfigOption {
  const config = new ModelConfigOption();
  config.id = (raw['id'] as number) || 0;
  config.name = (raw['name'] as string) || '';
  config.scope = (raw['scope'] as string) || 'personal';
  config.groupId = (raw['group_id'] as number) || 0;
  config.baseUrl = (raw['base_url'] as string) || '';
  config.model = (raw['model'] as string) || '';
  config.canEdit = raw['can_edit'] === true;
  config.apiKeyConfigured = raw['api_key_configured'] === true;
  return config;
}
