import { picker, fileShare, fileIo as fs, Filter, ListFileOptions } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { AudioEntry, SUPPORTED_EXT } from '../model/Types';

const AUDIO_SUFFIX: string[] = ['.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg'];
const AUDIO_FILTER_DESC: string = '音频|.mp3,.m4a,.aac,.wav,.flac,.ogg';

export class AudioLibrary {
  static canPickFolder(): boolean {
    return canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection');
  }

  static canPersist(): boolean {
    return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
  }

  static async pickFolder(context: common.UIAbilityContext): Promise<string[]> {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    // API 26 支持，但本方案一次只添加一个文件夹
    options.allowsMulFolderSelection = false;
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    return await documentPicker.select(options);
  }

  static async pickAudioFiles(context: common.UIAbilityContext): Promise<string[]> {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.selectMode = picker.DocumentSelectMode.FILE;
    options.maxSelectNumber = 100;
    options.fileSuffixFilters = [AUDIO_FILTER_DESC];
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      return await documentPicker.select(options);
    } catch (err) {
      // 文管选择器不可用时回退到音频选择器
      const audioOptions: picker.AudioSelectOptions = new picker.AudioSelectOptions();
      audioOptions.maxSelectNumber = 100;
      const audioPicker: picker.AudioViewPicker = new picker.AudioViewPicker(context);
      return await audioPicker.select(audioOptions);
    }
  }

  static async persistUris(uris: string[]): Promise<boolean> {
    if (!AudioLibrary.canPersist() || uris.length === 0) {
      return false;
    }
    try {
      const policies: fileShare.PolicyInfo[] = [];
      for (const uri of uris) {
        const policy: fileShare.PolicyInfo = {
          uri: uri,
          operationMode: fileShare.OperationMode.READ_MODE
        };
        policies.push(policy);
      }
      await fileShare.persistPermission(policies);
      return true;
    } catch (err) {
      return false;
    }
  }

  static async activateUris(uris: string[]): Promise<void> {
    if (!AudioLibrary.canPersist() || uris.length === 0) {
      return;
    }
    try {
      for (let start: number = 0; start < uris.length; start += 50) {
        const end: number = Math.min(start + 50, uris.length);
        const policies: fileShare.PolicyInfo[] = [];
        for (let i: number = start; i < end; i++) {
          const policy: fileShare.PolicyInfo = {
            uri: uris[i],
            operationMode: fileShare.OperationMode.READ_MODE
          };
          policies.push(policy);
        }
        await fileShare.activatePermission(policies);
      }
    } catch (err) {
      // 激活失败不阻塞启动，点播时再提示
    }
  }

  static async revokeUris(uris: string[]): Promise<void> {
    if (!AudioLibrary.canPersist() || uris.length === 0) {
      return;
    }
    try {
      const policies: fileShare.PolicyInfo[] = [];
      for (const uri of uris) {
        const policy: fileShare.PolicyInfo = {
          uri: uri,
          operationMode: fileShare.OperationMode.READ_MODE
        };
        policies.push(policy);
      }
      await fileShare.revokePermission(policies);
    } catch (err) {
      // 取消失败忽略
    }
  }

  static async scanFolder(folderUri: string): Promise<AudioEntry[]> {
    const filter: Filter = { suffix: AUDIO_SUFFIX };
    const options: ListFileOptions = {
      recursion: true,
      listNum: 0,
      filter: filter
    };

    let names: string[] = [];
    try {
      names = await fs.listFile(folderUri, options);
    } catch (err) {
      // 部分版本需要用目录 fd 的 path 再列一次
      const dir: fs.File = fs.openSync(folderUri, fs.OpenMode.READ_ONLY);
      try {
        names = await fs.listFile(dir.path, options);
      } finally {
        fs.closeSync(dir);
      }
    }

    const folderName: string = AudioLibrary.folderNameOf(folderUri);
    const now: number = Date.now();
    const entries: AudioEntry[] = [];
    for (const name of names) {
      const uri: string = AudioLibrary.joinUri(folderUri, name);
      if (!AudioLibrary.isSupported(uri)) {
        continue;
      }
      const entry: AudioEntry = {
        uri: uri,
        name: AudioLibrary.fileNameOf(uri),
        folderUri: folderUri,
        folderName: folderName,
        addedAt: now
      };
      entries.push(entry);
    }
    entries.sort((a: AudioEntry, b: AudioEntry) => a.name.localeCompare(b.name));
    return entries;
  }

  static entryFromFileUri(uri: string): AudioEntry {
    const entry: AudioEntry = {
      uri: uri,
      name: AudioLibrary.fileNameOf(uri),
      folderUri: '',
      folderName: AudioLibrary.parentFolderNameOf(uri),
      addedAt: Date.now()
    };
    return entry;
  }

  static isSupported(uri: string): boolean {
    const name: string = AudioLibrary.fileNameOf(uri);
    const index: number = name.lastIndexOf('.');
    if (index < 0) {
      return false;
    }
    const ext: string = name.substring(index + 1).toLowerCase();
    return SUPPORTED_EXT.indexOf(ext) >= 0;
  }

  static fileNameOf(uri: string): string {
    const clean: string = uri.split('?')[0];
    const index: number = clean.lastIndexOf('/');
    const raw: string = index >= 0 ? clean.substring(index + 1) : clean;
    try {
      return decodeURIComponent(raw);
    } catch (err) {
      return raw;
    }
  }

  static folderNameOf(uri: string): string {
    let clean: string = uri.split('?')[0];
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    const index: number = clean.lastIndexOf('/');
    const raw: string = index >= 0 ? clean.substring(index + 1) : clean;
    try {
      return decodeURIComponent(raw);
    } catch (err) {
      return raw;
    }
  }

  static parentFolderNameOf(fileUri: string): string {
    const clean: string = fileUri.split('?')[0];
    const index: number = clean.lastIndexOf('/');
    if (index < 0) {
      return '';
    }
    return AudioLibrary.folderNameOf(clean.substring(0, index));
  }

  static joinUri(folderUri: string, relativePath: string): string {
    let base: string = folderUri;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    let rel: string = relativePath;
    if (!rel.startsWith('/')) {
      rel = '/' + rel;
    }
    return base + rel;
  }
}
