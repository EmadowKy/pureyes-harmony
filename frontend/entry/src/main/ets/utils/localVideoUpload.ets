import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { HttpUtil, HttpResult } from './http';

export function videoContentType(filename: string): string {
  const ext = filename.split('.').pop()?.toLowerCase() || '';
  if (ext === 'mp4') return 'video/mp4';
  if (ext === 'mov') return 'video/quicktime';
  if (ext === 'avi') return 'video/x-msvideo';
  if (ext === 'mkv') return 'video/x-matroska';
  if (ext === 'webm') return 'video/webm';
  return '';
}

// Picker URIs are read through the granted descriptor; HTTP reads a private cache copy.
// Never load the entire video into an ArrayBuffer or delete the user's original file.
export async function uploadLocalVideo(workspaceId: number, uri: string, cacheDir: string,
  onProgress: (percent: number) => void): Promise<HttpResult> {
  const result = new HttpResult();
  let source: fs.File | undefined = undefined;
  let cachePath = '';
  try {
    const originalName = new fileUri.FileUri(uri).name;
    const contentType = videoContentType(originalName);
    if (!contentType) {
      result.message = '请选择 MP4、AVI、MOV、MKV 或 WebM 视频';
      return result;
    }
    // The server source listing matches lowercase extensions.
    const dot = originalName.lastIndexOf('.');
    const filename = originalName.substring(0, dot) + originalName.substring(dot).toLowerCase();
    source = await fs.open(uri, fs.OpenMode.READ_ONLY);
    const stat = await fs.stat(source.fd);
    if (stat.size <= 0 || stat.size > 2 * 1024 * 1024 * 1024) {
      result.message = stat.size <= 0 ? '所选视频为空，请重新选择' : '请选择不超过 2 GB 的视频';
      return result;
    }
    cachePath = `${cacheDir}/video-upload-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    await fs.copyFile(source.fd, cachePath);
    return await HttpUtil.uploadFile(`/workspaces/${workspaceId}/upload-video`, cachePath,
      filename, contentType, onProgress);
  } catch (error) {
    result.message = '无法读取或准备视频，请检查文件权限与手机剩余空间后重试';
    return result;
  } finally {
    if (source) {
      try { await fs.close(source.fd); } catch (error) { /* Best-effort descriptor cleanup. */ }
    }
    if (cachePath) {
      try { await fs.unlink(cachePath); } catch (error) { /* Only our private temporary copy. */ }
    }
  }
}
