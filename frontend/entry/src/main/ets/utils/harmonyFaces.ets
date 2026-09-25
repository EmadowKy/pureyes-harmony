import http from '@ohos.net.http';
import { image } from '@kit.ImageKit';
import { faceComparator } from '@kit.CoreVisionKit';
import { getBaseHost } from './http';

export class FaceQueueRecord {
  id: number = 0;
  group_id: number = 0;
  crop_url: string = '';
}

export class FaceAssignment {
  record_id: number = 0;
  target_group_id: number = 0;
}

async function loadFaceCrop(record: FaceQueueRecord): Promise<image.PixelMap> {
  const client = http.createHttp();
  try {
    const url = record.crop_url.startsWith('http') ? record.crop_url : getBaseHost() + record.crop_url;
    const response = await client.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 10000,
      readTimeout: 15000
    });
    if (response.responseCode !== 200) {
      throw new Error('无法读取人脸抓拍图');
    }
    const bytes = response.result as ArrayBuffer;
    if (!bytes || bytes.byteLength === 0) throw new Error('人脸抓拍图为空');
    const source = image.createImageSource(bytes);
    try {
      return await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    } finally {
      await source.release();
    }
  } finally {
    client.destroy();
  }
}

export async function classifyOnHarmonyPhone(pending: Array<FaceQueueRecord>,
  gallery: Array<FaceQueueRecord>): Promise<Array<FaceAssignment>> {
  if (!await faceComparator.init()) {
    throw new Error('当前设备无法初始化鸿蒙人脸比对服务');
  }
  const cache: Map<number, image.PixelMap> = new Map<number, image.PixelMap>();
  const assignments: Array<FaceAssignment> = [];
  try {
    for (const record of pending) {
      const crop = await loadFaceCrop(record);
      cache.set(record.id, crop);
      let selectedGroup: number = record.group_id;
      let highestSimilarity: number = -1;
      for (const reference of gallery) {
        let referenceCrop = cache.get(reference.id);
        if (!referenceCrop) {
          referenceCrop = await loadFaceCrop(reference);
          cache.set(reference.id, referenceCrop);
        }
        const match = await faceComparator.compareFaces({ pixelMap: crop }, { pixelMap: referenceCrop });
        if (match.isSamePerson && match.similarity > highestSimilarity) {
          selectedGroup = reference.group_id;
          highestSimilarity = match.similarity;
        }
      }
      const assignment = new FaceAssignment();
      assignment.record_id = record.id;
      assignment.target_group_id = selectedGroup;
      assignments.push(assignment);
      if (highestSimilarity < 0) {
        gallery.push(record);
      }
    }
    return assignments;
  } finally {
    for (const pixelMap of cache.values()) {
      await pixelMap.release();
    }
    await faceComparator.release();
  }
}

