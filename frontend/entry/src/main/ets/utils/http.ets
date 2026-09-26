import http from '@ohos.net.http';

export const OFFICIAL_SERVER_URL = 'http://116.62.178.139:8000/api';
export const OFFICIAL_BASE_HOST = 'http://116.62.178.139:8000';

// 初始化持久化存储，确保跨应用退出/重启仍然保留服务器地址偏好
try {
  PersistentStorage.persistProp('custom_server_url', '');
  PersistentStorage.persistProp('is_custom_server', false);
} catch (e) {
  console.error('Failed to initialize PersistentStorage', JSON.stringify(e));
}

export function normalizeServerUrl(rawUrl: string): string {
  let url = rawUrl.trim().replace(/\/+$/, '');
  if (!url) {
    return OFFICIAL_SERVER_URL;
  }
  // 仅保留 http:// 或 https:// 协议头的自动补全
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = `http://${url}`;
  }
  return url.endsWith('/api') ? url : `${url}/api`;
}

export function getBaseUrl(): string {
  const isCustom = AppStorage.get<boolean>('is_custom_server');
  const custom = AppStorage.get<string>('custom_server_url');
  if (isCustom === true && custom && custom.trim().length > 0) {
    return normalizeServerUrl(custom);
  }
  return OFFICIAL_SERVER_URL;
}

export function getBaseHost(): string {
  const isCustom = AppStorage.get<boolean>('is_custom_server');
  if (isCustom !== true) {
    return OFFICIAL_BASE_HOST;
  }
  const baseUrl = getBaseUrl();
  if (baseUrl.endsWith('/api')) {
    return baseUrl.substring(0, baseUrl.length - 4);
  }
  return baseUrl;
}

export let BASE_HOST = getBaseHost();

export function updateBaseHost(): void {
  BASE_HOST = getBaseHost();
}

export class HttpResult {
  code: number = -1;
  httpStatus: number = 0;
  message: string = '';
  data?: string; // stringified JSON to avoid 'any'
}

export class TestServerResult {
  success: boolean = false;
  message: string = '';
}

const REQUEST_TIMEOUT = 10000;

export class HttpUtil {
  static async request(url: string, method: http.RequestMethod, data?: Object,
    authToken?: string): Promise<HttpResult> {
    const httpRequest = http.createHttp();
    let currentBaseUrl = getBaseUrl().replace(/\/+$/, '');
    
    let requestUrl = url.startsWith('/') ? `${currentBaseUrl}${url}` : `${currentBaseUrl}/${url}`;

    try {
      const response = await httpRequest.request(requestUrl, {
        method: method,
        header: {
          'Content-Type': 'application/json',
          'Authorization': url === '/auth/login' ? '' :
            `Bearer ${authToken !== undefined ? authToken : (AppStorage.get<string>('access_token') || '')}`
        },
        extraData: data ? JSON.stringify(data) : undefined,
        connectTimeout: REQUEST_TIMEOUT,
        readTimeout: REQUEST_TIMEOUT,
      });
      const result = new HttpResult();
      result.httpStatus = response.responseCode;
      let resObj: Record<string, Object>;
      try {
        resObj = JSON.parse(response.result as string) as Record<string, Object>;
      } catch (parseError) {
        result.message = `服务器响应异常（HTTP ${response.responseCode}）`;
        return result;
      }
      result.code = typeof resObj['code'] === 'number' ? resObj['code'] as number : -1;
      result.message = (resObj['message'] as string) || '';
      if (resObj['data'] !== undefined) {
        result.data = JSON.stringify(resObj['data']);
      }
      return result;
    } catch (err) {
      console.error('HTTP Request Error', JSON.stringify(err));
      const errRes = new HttpResult();
      errRes.code = -1;
      errRes.message = '无法连接服务器，请检查网络或服务器地址';
      return errRes;
    } finally {
      httpRequest.destroy();
    }
  }

  static async testServerUrl(targetUrl: string): Promise<TestServerResult> {
    const normalizedUrl = normalizeServerUrl(targetUrl).replace(/\/+$/, '');
    let healthUrl = normalizedUrl;
    if (!healthUrl.endsWith('/health')) {
      if (healthUrl.endsWith('/api')) {
        healthUrl = `${healthUrl}/health`;
      } else {
        healthUrl = `${healthUrl}/api/health`;
      }
    }
    const httpRequest = http.createHttp();
    const res = new TestServerResult();
    try {
      const response = await httpRequest.request(healthUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 5000,
      });
      let validBackend = false;
      try {
        const body = JSON.parse(response.result as string) as Record<string, Object>;
        const data = body['data'] as Record<string, Object>;
        validBackend = body['code'] === 0 && !!data && data['service'] === 'backend';
      } catch (parseError) {
        validBackend = false;
      }
      if (response.responseCode === 200 && validBackend) {
        res.success = true;
        res.message = '服务器连接成功';
      } else {
        res.success = false;
        res.message = '服务器连接失败';
      }
      return res;
    } catch (err) {
      res.success = false;
      res.message = '服务器连接失败';
      return res;
    } finally {
      httpRequest.destroy();
    }
  }

  static get(url: string): Promise<HttpResult> {
    return HttpUtil.request(url, http.RequestMethod.GET);
  }

  static post(url: string, data?: Object): Promise<HttpResult> {
    return HttpUtil.request(url, http.RequestMethod.POST, data);
  }

  static postWithToken(url: string, token: string): Promise<HttpResult> {
    return HttpUtil.request(url, http.RequestMethod.POST, undefined, token);
  }

  static put(url: string, data?: Object): Promise<HttpResult> {
    return HttpUtil.request(url, http.RequestMethod.PUT, data);
  }

  static del(url: string, data?: Object): Promise<HttpResult> {
    return HttpUtil.request(url, http.RequestMethod.DELETE, data);
  }
}
