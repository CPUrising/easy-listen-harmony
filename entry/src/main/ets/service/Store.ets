import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { MarkItem, MarkMap, Settings, DEFAULT_VOLUME } from '../model/Types';

const STORE_NAME: string = 'easy_listen';
const KEY_MARKS: string = 'marks';
const KEY_VOLUME: string = 'volume';
const KEY_PINNED: string = 'pinned';

export class Store {
  private static store: preferences.Preferences | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    try {
      Store.store = await preferences.getPreferences(context, STORE_NAME);
    } catch (err) {
      Store.store = null;
    }
  }

  private static marksKey(uri: string): string {
    return uri.toLowerCase();
  }

  private static async readMarkMap(): Promise<MarkMap> {
    if (Store.store === null) {
      return {};
    }
    try {
      const raw: string = await Store.store.get(KEY_MARKS, '{}') as string;
      return JSON.parse(raw) as MarkMap;
    } catch (err) {
      return {};
    }
  }

  static async getMarks(uri: string): Promise<MarkItem[]> {
    const all: MarkMap = await Store.readMarkMap();
    const list: MarkItem[] | undefined = all[Store.marksKey(uri)];
    if (list === undefined || !Array.isArray(list)) {
      return [];
    }
    return list
      .filter((item: MarkItem) => Number.isFinite(item.t))
      .sort((a: MarkItem, b: MarkItem) => a.t - b.t);
  }

  static async saveMarks(uri: string, marks: MarkItem[]): Promise<void> {
    if (Store.store === null) {
      return;
    }
    try {
      const all: MarkMap = await Store.readMarkMap();
      all[Store.marksKey(uri)] = marks;
      await Store.store.put(KEY_MARKS, JSON.stringify(all));
      await Store.store.flush();
    } catch (err) {
      // 持久化失败不影响播放
    }
  }

  static async getSettings(): Promise<Settings> {
    const result: Settings = { volume: DEFAULT_VOLUME, pinned: true };
    if (Store.store === null) {
      return result;
    }
    try {
      const volume: number = await Store.store.get(KEY_VOLUME, DEFAULT_VOLUME) as number;
      const pinned: boolean = await Store.store.get(KEY_PINNED, true) as boolean;
      if (Number.isFinite(volume)) {
        result.volume = Math.max(0, Math.min(100, volume));
      }
      result.pinned = pinned;
    } catch (err) {
      // 读取失败使用默认设置
    }
    return result;
  }

  static async saveSettings(settings: Settings): Promise<void> {
    if (Store.store === null) {
      return;
    }
    try {
      await Store.store.put(KEY_VOLUME, settings.volume);
      await Store.store.put(KEY_PINNED, settings.pinned);
      await Store.store.flush();
    } catch (err) {
      // 持久化失败不影响播放
    }
  }
}
