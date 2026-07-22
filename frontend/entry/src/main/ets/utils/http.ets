import http from '@ohos.net.http';

export const OFFICIAL_SERVER_URL = 'https://api.pureyes.top/api';
export const OFFICIAL_BASE_HOST = 'https://api.pureyes.top';

export function normalizeServerUrl(rawUrl: string): string {
  let url = rawUrl.trim();
  if (!url) {
    return OFFICIAL_SERVER_URL;
  }
  // 仅保留 http:// 或 https:// 协议头的自动补全
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = `http://${url}`;
  }
  return url;
}

export function getBaseUrl(): string {
  const custom = AppStorage.get<string>('custom_server_url');
  if (custom && custom.trim().length > 0) {
    return normalizeServerUrl(custom);
  }
  return OFFICIAL_SERVER_URL;
}

export function getBaseHost(): string {
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
  message: string = '';
  data?: string; // stringified JSON to avoid 'any'
}

export class TestServerResult {
  success: boolean = false;
  message: string = '';
}

const REQUEST_TIMEOUT = 10000;

export class HttpUtil {
  static async request(url: string, method: http.RequestMethod, data?: Object): Promise<HttpResult> {
    const httpRequest = http.createHttp();
    let currentBaseUrl = getBaseUrl().replace(/\/+$/, '');
    
    // 如果 URL 参数以 / 开头，进行拼接；如 currentBaseUrl 末尾包含 /api，直接与 /url 拼合
    let requestUrl = url.startsWith('/') ? `${currentBaseUrl}${url}` : `${currentBaseUrl}/${url}`;

    try {
      const response = await httpRequest.request(requestUrl, {
        method: method,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${AppStorage.get<string>('access_token') || ''}`
        },
        extraData: data ? JSON.stringify(data) : undefined,
        connectTimeout: REQUEST_TIMEOUT,
        readTimeout: REQUEST_TIMEOUT,
      });
      const resObj = JSON.parse(response.result as string) as Object;
      const result = new HttpResult();
      result.code = (resObj as Record<string, Object>)['code'] as number;
      result.message = (resObj as Record<string, Object>)['message'] as string;
      if ((resObj as Record<string, Object>)['data'] !== undefined) {
        result.data = JSON.stringify((resObj as Record<string, Object>)['data']);
      }
      return result;
    } catch (err) {
      console.error('HTTP Request Error', JSON.stringify(err));
      const errRes = new HttpResult();
      errRes.code = -1;
      errRes.message = 'Network Error';
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
      if (response.responseCode === 200) {
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

  static put(url: string, data?: Object): Promise<HttpResult> {
    return HttpUtil.request(url, http.RequestMethod.PUT, data);
  }

  static del(url: string, data?: Object): Promise<HttpResult> {
    return HttpUtil.request(url, http.RequestMethod.DELETE, data);
  }
}
