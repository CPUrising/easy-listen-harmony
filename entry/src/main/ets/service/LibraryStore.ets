import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { AudioEntry, AudioFolder, LibraryData } from '../model/Types';

const LIBRARY_FILE: string = 'library.json';
const MAX_ENTRIES: number = 1000;

export class LibraryStore {
  private static path: string = '';
  private static data: LibraryData = { version: 1, folders: [], entries: [] };

  static init(context: common.UIAbilityContext): void {
    LibraryStore.path = context.filesDir + '/' + LIBRARY_FILE;
    LibraryStore.data = LibraryStore.load();
  }

  static getFolders(): AudioFolder[] {
    return LibraryStore.data.folders;
  }

  static getEntries(): AudioEntry[] {
    return LibraryStore.data.entries;
  }

  // 添加/刷新文件夹，返回实际写入的条目数量
  static saveFolder(folder: AudioFolder, entries: AudioEntry[]): number {
    const folders: AudioFolder[] = LibraryStore.data.folders
      .filter((item: AudioFolder) => item.uri !== folder.uri);
    folders.push(folder);

    const others: AudioEntry[] = LibraryStore.data.entries
      .filter((item: AudioEntry) => item.folderUri !== folder.uri);
    let room: number = MAX_ENTRIES - others.length;
    if (room < 0) {
      room = 0;
    }
    const kept: AudioEntry[] = entries.slice(0, room);

    LibraryStore.data.folders = folders;
    LibraryStore.data.entries = others.concat(kept);
    LibraryStore.persist();
    return kept.length;
  }

  // 批量添加单独导入的文件，返回实际新增数量
  static addEntries(entries: AudioEntry[]): number {
    const existing: string[] = [];
    for (const item of LibraryStore.data.entries) {
      existing.push(item.uri);
    }

    const added: AudioEntry[] = [];
    for (const item of entries) {
      if (existing.indexOf(item.uri) >= 0) {
        continue;
      }
      if (LibraryStore.data.entries.length + added.length >= MAX_ENTRIES) {
        break;
      }
      existing.push(item.uri);
      added.push(item);
    }

    if (added.length > 0) {
      LibraryStore.data.entries = LibraryStore.data.entries.concat(added);
      LibraryStore.persist();
    }
    return added.length;
  }

  static removeFolder(uri: string): void {
    LibraryStore.data.folders = LibraryStore.data.folders
      .filter((item: AudioFolder) => item.uri !== uri);
    LibraryStore.data.entries = LibraryStore.data.entries
      .filter((item: AudioEntry) => item.folderUri !== uri);
    LibraryStore.persist();
  }

  static removeEntry(uri: string): void {
    LibraryStore.data.entries = LibraryStore.data.entries
      .filter((item: AudioEntry) => item.uri !== uri);
    LibraryStore.persist();
  }

  private static load(): LibraryData {
    const empty: LibraryData = { version: 1, folders: [], entries: [] };
    if (LibraryStore.path === '') {
      return empty;
    }
    try {
      if (!fs.accessSync(LibraryStore.path)) {
        return empty;
      }
      const text: string = fs.readTextSync(LibraryStore.path);
      const parsed: LibraryData = JSON.parse(text) as LibraryData;
      if (parsed === null || !Array.isArray(parsed.folders) || !Array.isArray(parsed.entries)) {
        return empty;
      }
      parsed.version = 1;
      return parsed;
    } catch (err) {
      return empty;
    }
  }

  private static persist(): void {
    if (LibraryStore.path === '') {
      return;
    }
    try {
      const file: fs.File = fs.openSync(
        LibraryStore.path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      fs.writeSync(file.fd, JSON.stringify(LibraryStore.data));
      fs.closeSync(file);
    } catch (err) {
      // 音频库写入失败不影响播放
    }
  }
}
