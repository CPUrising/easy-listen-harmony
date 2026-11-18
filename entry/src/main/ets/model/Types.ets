export interface MarkItem {
  id: string;
  t: number; // 标记位置，单位毫秒
}

export interface Settings {
  volume: number;
  pinned: boolean;
}

export type MarkMap = Record<string, MarkItem[]>;

export interface AudioFolder {
  uri: string;
  name: string;
  addedAt: number;
}

export interface AudioEntry {
  uri: string;
  name: string;
  folderUri: string; // 来自文件夹导入时为该文件夹 URI；单独导入的文件为 ''
  folderName: string;
  addedAt: number;
}

export interface LibraryData {
  version: number;
  folders: AudioFolder[];
  entries: AudioEntry[];
}


// AVPlayer 可稳定解码的音频后缀
export const SUPPORTED_EXT: string[] = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'];

// 已知音频后缀（含暂不支持的格式，用于给出明确提示）
export const KNOWN_EXT: string[] = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'webm'];

export const DEFAULT_VOLUME: number = 80;

export const DEFAULT_HINT: string =
  '快捷键：Space 播放/暂停，←/→ 快退/快进 5 秒，M 标记（需键盘聚焦本页）';
