import { HttpUtil, getBaseHost } from './http';

// Renew through the authenticated API, never by extending or reusing an old token.
export async function renewMediaUrl(source: string): Promise<string> {
  const marker = '/api/video/';
  const index = source.indexOf(marker);
  if (index < 0) {
    throw new Error('视频地址无效');
  }
  const path = source.substring(index + marker.length).split('?')[0];
  const result = await HttpUtil.get(`/video/access?path=${encodeURIComponent(path)}`);
  if (result.code !== 0 || !result.data) {
    throw new Error(result.message || '无法刷新视频地址，请重新登录或检查小组权限');
  }
  const data = JSON.parse(result.data) as Record<string, Object>;
  const url = (data['media_url'] as string) || '';
  if (!url) throw new Error('服务器未返回播放地址');
  return `${getBaseHost()}${url}&t=${Date.now()}`;
}
