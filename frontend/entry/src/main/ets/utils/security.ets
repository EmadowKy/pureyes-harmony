import asset from '@ohos.security.asset';
import util from '@ohos.util';

function stringToUint8Array(str: string): Uint8Array {
  const encoder = new util.TextEncoder();
  return encoder.encodeInto(str);
}

function uint8ArrayToString(arr: Uint8Array): string {
  const decoder = new util.TextDecoder('utf-8');
  return decoder.decodeToString(arr);
}

export class SecurityUtil {
  /**
   * 写入/更新鸿蒙 Asset Store Kit 关键资产 (硬件 TEE AES-GCM 加密存储)
   */
  static async setSecureProp(key: string, value: string): Promise<boolean> {
    try {
      let query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, stringToUint8Array(key));

      let attrToUpdate: asset.AssetMap = new Map();
      attrToUpdate.set(asset.Tag.SECRET, stringToUint8Array(value));

      try {
        await asset.update(query, attrToUpdate);
        return true;
      } catch (updateErr) {
        // 若资产尚不存在，则执行新增
        let newAttr: asset.AssetMap = new Map();
        newAttr.set(asset.Tag.ALIAS, stringToUint8Array(key));
        newAttr.set(asset.Tag.SECRET, stringToUint8Array(value));
        newAttr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
        await asset.add(newAttr);
        return true;
      }
    } catch (err) {
      console.warn(`[SecurityUtil] Asset Store Kit set fallback for ${key}: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 读取鸿蒙 Asset Store Kit 关键资产 (从芯片级安全隔离区解密读取)
   */
  static async getSecureProp(key: string): Promise<string | null> {
    try {
      let query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, stringToUint8Array(key));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);

      let res: Array<asset.AssetMap> = await asset.query(query);
      if (res && res.length > 0) {
        let secretArr = res[0].get(asset.Tag.SECRET) as Uint8Array;
        if (secretArr) {
          return uint8ArrayToString(secretArr);
        }
      }
    } catch (err) {
      console.warn(`[SecurityUtil] Asset Store Kit query fallback for ${key}: ${JSON.stringify(err)}`);
    }
    return null;
  }

  /**
   * 删除鸿蒙 Asset Store Kit 关键资产
   */
  static async removeSecureProp(key: string): Promise<boolean> {
    try {
      let query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, stringToUint8Array(key));
      await asset.remove(query);
      return true;
    } catch (err) {
      return false;
    }
  }

  /**
   * 应用启动时自动从硬件密钥库加载并同步初始化安全凭据
   */
  static async initSecureState(): Promise<void> {
    try {
      const secureToken = await SecurityUtil.getSecureProp('access_token');
      if (secureToken) {
        AppStorage.setOrCreate('access_token', secureToken);
      }

      const secureServerUrl = await SecurityUtil.getSecureProp('custom_server_url');
      if (secureServerUrl) {
        AppStorage.setOrCreate('custom_server_url', secureServerUrl);
      }

      const secureIsCustom = await SecurityUtil.getSecureProp('is_custom_server');
      if (secureIsCustom !== null) {
        AppStorage.setOrCreate('is_custom_server', secureIsCustom === 'true');
      }
    } catch (e) {
      console.warn('[SecurityUtil] initSecureState fallback:', JSON.stringify(e));
    }
  }
}
