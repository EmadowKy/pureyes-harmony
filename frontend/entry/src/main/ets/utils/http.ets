import http from '@ohos.net.http';

export const BASE_HOST = 'http://10.32.212.191:8000';
const BASE_URL = 'http://10.32.212.191:8000/api';

export class HttpResult {
  code: number = -1;
  message: string = '';
  data?: string; // stringified JSON to avoid 'any'
}

export class HttpUtil {
  static async request(url: string, method: http.RequestMethod, data?: Object): Promise<HttpResult> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(`${BASE_URL}${url}`, {
        method: method,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${AppStorage.get<string>('access_token') || ''}`
        },
        extraData: data ? JSON.stringify(data) : undefined,
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
}
