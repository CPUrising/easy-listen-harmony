import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { AudioController, PlayerEvents } from '../service/AudioController';
import { Store } from '../service/Store';
import { AudioLibrary } from '../service/AudioLibrary';
import { LibraryStore } from '../service/LibraryStore';
import {
  MarkItem,
  Settings,
  AudioFolder,
  AudioEntry,
  SUPPORTED_EXT,
  KNOWN_EXT,
  DEFAULT_HINT,
  DEFAULT_VOLUME
} from '../model/Types';
import { formatTime } from '../utils/TimeFormat';

@Entry
@Component
struct Index {
  @State trackUri: string = '';
  @State trackName: string = '点 ＋ 打开音频库';
  @State currentMs: number = 0;
  @State durationMs: number = 0;
  @State playing: boolean = false;
  @State volume: number = DEFAULT_VOLUME;
  @State pinned: boolean = true;
  @State marks: MarkItem[] = [];
  @State marksOpen: boolean = false;
  @State hintText: string = DEFAULT_HINT;
  @State isSeeking: boolean = false;
  @State seekValue: number = 0;
  @State libraryOpen: boolean = false;
  @State libraryBusy: boolean = false;
  @State libraryQuery: string = '';
  @State activeFolderUri: string = '';
  @State libraryFolders: AudioFolder[] = [];
  @State libraryEntries: AudioEntry[] = [];

  private controller: AudioController | null = null;
  private hintTimer: number = -1;

  aboutToAppear(): void {
    this.controller = new AudioController({
      onReady: (durationMs: number) => {
        this.durationMs = durationMs;
        this.currentMs = 0;
        this.seekValue = 0;
        if (this.controller !== null) {
          this.controller.setVolume(this.volume);
        }
      },
      onProgress: (ms: number) => {
        this.currentMs = ms;
        if (!this.isSeeking && this.durationMs > 0) {
          this.seekValue = (ms / this.durationMs) * 100;
        }
      },
      onPlayingChange: (playing: boolean) => {
        this.playing = playing;
      },
      onCompleted: () => {
        this.showHint('播放结束');
      },
      onError: (message: string) => {
        this.showHint(message);
      }
    });
    this.initPage();
  }

  aboutToDisappear(): void {
    if (this.hintTimer >= 0) {
      clearTimeout(this.hintTimer);
      this.hintTimer = -1;
    }
    if (this.controller !== null) {
      this.controller.release();
      this.controller = null;
    }
  }

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async initPage(): Promise<void> {
    await Store.init(this.abilityContext());
    LibraryStore.init(this.abilityContext());
    this.refreshLibrary();
    const settings: Settings = await Store.getSettings();
    this.volume = settings.volume;
    this.pinned = settings.pinned;
    if (this.controller !== null) {
      this.controller.setVolume(this.volume);
    }
    this.activateLibrary();
  }

  /* ---------- 提示 ---------- */

  private showHint(message: string): void {
    this.hintText = message;
    if (this.hintTimer >= 0) {
      clearTimeout(this.hintTimer);
    }
    this.hintTimer = setTimeout(() => {
      this.hintText = DEFAULT_HINT;
      this.hintTimer = -1;
    }, 2600);
  }

  /* ---------- 音频库 ---------- */

  private refreshLibrary(): void {
    this.libraryFolders = LibraryStore.getFolders().slice();
    this.libraryEntries = LibraryStore.getEntries().slice();
    if (this.activeFolderUri !== '') {
      const exists: boolean = this.libraryFolders
        .some((folder: AudioFolder) => folder.uri === this.activeFolderUri);
      if (!exists) {
        this.activeFolderUri = '';
      }
    }
  }

  private async activateLibrary(): Promise<void> {
    const uris: string[] = [];
    for (const folder of this.libraryFolders) {
      uris.push(folder.uri);
    }
    for (const entry of this.libraryEntries) {
      if (entry.folderUri === '') {
        uris.push(entry.uri);
      }
    }
    if (uris.length > 0) {
      await AudioLibrary.activateUris(uris);
    }
  }

  private openLibrary(): void {
    this.refreshLibrary();
    this.libraryQuery = '';
    this.libraryOpen = true;
  }

  private async addFolder(): Promise<void> {
    if (!AudioLibrary.canPickFolder()) {
      this.showHint('当前设备不支持文件夹导入，请使用「导入音频文件」');
      return;
    }
    if (this.libraryBusy) {
      return;
    }
    try {
      const uris: string[] = await AudioLibrary.pickFolder(this.abilityContext());
      if (uris.length === 0) {
        return;
      }
      const folderUri: string = uris[0];
      this.libraryBusy = true;
      const persisted: boolean = await AudioLibrary.persistUris([folderUri]);

      let entries: AudioEntry[] = [];
      try {
        entries = await AudioLibrary.scanFolder(folderUri);
      } catch (err) {
        this.showHint('无法读取该文件夹，请改用「导入音频文件」');
        return;
      }
      if (entries.length === 0) {
        this.showHint('该文件夹里没有可播放的音频');
        return;
      }

      const folder: AudioFolder = {
        uri: folderUri,
        name: AudioLibrary.folderNameOf(folderUri),
        addedAt: Date.now()
      };
      const saved: number = LibraryStore.saveFolder(folder, entries);
      this.refreshLibrary();
      this.activeFolderUri = folderUri;
      const extra: string = persisted ? '' : '（重启后如提示无权限，请重新添加）';
      this.showHint(`已添加文件夹：${folder.name}（${saved} 个音频）${extra}`);
    } catch (err) {
      this.showHint('打开文件夹失败');
    } finally {
      this.libraryBusy = false;
    }
  }

  private async importFiles(): Promise<void> {
    if (this.libraryBusy) {
      return;
    }
    this.libraryBusy = true;
    try {
      const uris: string[] = await AudioLibrary.pickAudioFiles(this.abilityContext());
      if (uris.length === 0) {
        return;
      }
      const supported: string[] = [];
      for (const uri of uris) {
        if (AudioLibrary.isSupported(uri)) {
          supported.push(uri);
        }
      }
      if (supported.length === 0) {
        this.showHint('所选文件不是受支持的音频格式');
        return;
      }
      await AudioLibrary.persistUris(supported);
      const entries: AudioEntry[] = [];
      for (const uri of supported) {
        entries.push(AudioLibrary.entryFromFileUri(uri));
      }
      const added: number = LibraryStore.addEntries(entries);
      this.refreshLibrary();
      this.showHint(added > 0 ? `已导入 ${added} 个音频` : '这些音频已经在库中了');
    } catch (err) {
      this.showHint('导入音频失败');
    } finally {
      this.libraryBusy = false;
    }
  }

  private async removeFolder(folder: AudioFolder): Promise<void> {
    LibraryStore.removeFolder(folder.uri);
    this.refreshLibrary();
    await AudioLibrary.revokeUris([folder.uri]);
    this.showHint(`已移除文件夹：${folder.name}`);
  }

  private removeEntry(entry: AudioEntry): void {
    LibraryStore.removeEntry(entry.uri);
    this.refreshLibrary();
  }

  private async playFromLibrary(entry: AudioEntry): Promise<void> {
    this.libraryOpen = false;
    await this.loadTrack(entry.uri);
  }

  private filteredEntries(): AudioEntry[] {
    const query: string = this.libraryQuery.trim().toLowerCase();
    const result: AudioEntry[] = [];
    for (const entry of this.libraryEntries) {
      if (this.activeFolderUri !== '' && entry.folderUri !== this.activeFolderUri) {
        continue;
      }
      if (query !== '' && entry.name.toLowerCase().indexOf(query) < 0) {
        continue;
      }
      result.push(entry);
    }
    result.sort((a: AudioEntry, b: AudioEntry) => {
      if (a.folderName !== b.folderName) {
        return a.folderName.localeCompare(b.folderName);
      }
      return a.name.localeCompare(b.name);
    });
    return result;
  }

  /* ---------- 打开与播放 ---------- */

  private async loadTrack(uri: string): Promise<void> {
    const ext: string = this.extensionOf(uri);
    if (ext !== '' && KNOWN_EXT.indexOf(ext) < 0) {
      this.showHint('只支持音频文件（mp3 / m4a / wav / flac 等）');
      return;
    }
    if (ext !== '' && SUPPORTED_EXT.indexOf(ext) < 0) {
      this.showHint('鸿蒙暂不支持该格式（支持 mp3 / m4a / aac / wav / flac / ogg）');
      return;
    }

    this.trackUri = uri;
    this.trackName = this.fileNameOf(uri);
    this.currentMs = 0;
    this.durationMs = 0;
    this.seekValue = 0;
    this.marks = await Store.getMarks(uri);
    this.marksOpen = false;

    if (this.controller !== null) {
      await this.controller.load(uri);
    }
    this.showHint(`正在播放：${this.trackName}`);
  }

  private fileNameOf(uri: string): string {
    const clean: string = uri.split('?')[0];
    const index: number = clean.lastIndexOf('/');
    const raw: string = index >= 0 ? clean.substring(index + 1) : clean;
    try {
      return decodeURIComponent(raw);
    } catch (err) {
      return raw;
    }
  }

  private extensionOf(uri: string): string {
    const name: string = this.fileNameOf(uri);
    const index: number = name.lastIndexOf('.');
    return index >= 0 ? name.substring(index + 1).toLowerCase() : '';
  }

  private async togglePlay(): Promise<void> {
    if (this.trackUri === '') {
      this.openLibrary();
      return;
    }
    if (this.controller === null) {
      return;
    }
    await this.controller.togglePlay();
  }

  private seekBy(seconds: number): void {
    if (this.trackUri === '') {
      this.showHint('请先打开一个音频文件');
      return;
    }
    if (this.controller === null || this.durationMs <= 0) {
      this.showHint('音频还没加载好，稍后再试');
      return;
    }
    const target: number = this.controller.seekBy(seconds * 1000);
    this.currentMs = target;
    this.seekValue = this.durationMs > 0 ? (target / this.durationMs) * 100 : 0;
    this.showHint(`${seconds > 0 ? '前进' : '后退'} ${Math.abs(seconds)} 秒 → ${formatTime(target)}`);
  }

  private seekToPercent(percent: number): void {
    if (this.controller === null || this.durationMs <= 0) {
      return;
    }
    const ms: number = (percent / 100) * this.durationMs;
    this.controller.seekTo(ms);
    this.currentMs = ms;
  }

  /* ---------- 标记 ---------- */

  private newId(): string {
    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  }

  private async addMark(): Promise<void> {
    if (this.trackUri === '') {
      this.showHint('请先打开一个音频文件');
      return;
    }
    if (this.durationMs <= 0) {
      this.showHint('音频还没加载好，稍后再试');
      return;
    }
    const t: number = Math.floor(this.currentMs);
    const duplicated: boolean = this.marks.some((mark: MarkItem) => Math.abs(mark.t - t) < 1000);
    if (duplicated) {
      this.showHint('当前位置附近已经有标记了');
      return;
    }
    const mark: MarkItem = { id: this.newId(), t: t };
    const next: MarkItem[] = this.marks
      .concat([mark])
      .sort((a: MarkItem, b: MarkItem) => a.t - b.t);
    this.marks = next;
    await Store.saveMarks(this.trackUri, next);
    this.showHint(`已在 ${formatTime(t)} 添加标记`);
  }

  private jumpToMark(mark: MarkItem): void {
    if (this.controller === null) {
      return;
    }
    this.controller.seekTo(mark.t);
    this.currentMs = mark.t;
    this.seekValue = this.durationMs > 0 ? (mark.t / this.durationMs) * 100 : 0;
    this.showHint(`跳到 ${formatTime(mark.t)}`);
  }

  private jumpToNextMark(): void {
    if (this.marks.length === 0) {
      this.showHint('还没有标记');
      return;
    }
    const now: number = this.currentMs;
    const next: MarkItem | undefined = this.marks.find((mark: MarkItem) => mark.t > now + 300);
    if (next === undefined) {
      this.showHint('后面没有标记了');
      return;
    }
    this.jumpToMark(next);
  }

  private jumpToPrevMark(): void {
    if (this.marks.length === 0) {
      this.showHint('还没有标记');
      return;
    }
    const now: number = this.currentMs;
    let prev: MarkItem | undefined = undefined;
    for (let i: number = this.marks.length - 1; i >= 0; i--) {
      if (this.marks[i].t < now - 300) {
        prev = this.marks[i];
        break;
      }
    }
    if (prev === undefined) {
      this.showHint('前面没有标记了');
      return;
    }
    this.jumpToMark(prev);
  }

  private async removeMark(id: string): Promise<void> {
    const next: MarkItem[] = this.marks.filter((mark: MarkItem) => mark.id !== id);
    this.marks = next;
    await Store.saveMarks(this.trackUri, next);
  }

  /* ---------- 音量与置顶 ---------- */

  private onVolumeChange(value: number): void {
    this.volume = value;
    if (this.controller !== null) {
      this.controller.setVolume(value);
    }
    const settings: Settings = { volume: value, pinned: this.pinned };
    Store.saveSettings(settings);
  }

  private async togglePin(): Promise<void> {
    this.pinned = !this.pinned;
    const settings: Settings = { volume: this.volume, pinned: this.pinned };
    Store.saveSettings(settings);
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.abilityContext());
      await mainWindow.setWindowTopmost(this.pinned);
      this.showHint(this.pinned ? '已置顶' : '已取消置顶');
    } catch (err) {
      this.showHint('当前设备不支持窗口置顶（手机/平板系统限制）');
    }
  }

  private closeApp(): void {
    this.abilityContext().terminateSelf();
  }

  /* ---------- 快捷键 ---------- */

  private handleKey(event: KeyEvent): void {
    if (this.libraryOpen) {
      return;
    }
    if (event.type !== KeyType.Down) {
      return;
    }
    const code: number = event.keyCode;
    if (code === KeyCode.KEYCODE_SPACE) {
      this.togglePlay();
    } else if (code === KeyCode.KEYCODE_DPAD_LEFT) {
      this.seekBy(-5);
    } else if (code === KeyCode.KEYCODE_DPAD_RIGHT) {
      this.seekBy(5);
    } else if (code === KeyCode.KEYCODE_M) {
      this.addMark();
    }
  }

  /* ---------- UI ---------- */

  @Builder
  IconButton(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(15)
      .fontColor(active ? '#5EEAD4' : '#8B919A')
      .textAlign(TextAlign.Center)
      .width(34)
      .height(30)
      .borderRadius(6)
      .backgroundColor('#20242B')
      .margin({ left: 4 })
      .onClick(() => {
        action();
      })
  }

  @Builder
  SkipButton(label: string, delta: number) {
    Text(label)
      .fontSize(12)
      .fontColor('#C3C8D0')
      .textAlign(TextAlign.Center)
      .height(36)
      .layoutWeight(1)
      .borderRadius(6)
      .backgroundColor('#20242B')
      .margin({ left: 2, right: 2 })
      .onClick(() => {
        this.seekBy(delta);
      })
  }

  @Builder
  GhostButton(label: string, action: () => void) {
    Text(label)
      .fontSize(12)
      .fontColor('#AAB0B9')
      .textAlign(TextAlign.Center)
      .height(32)
      .padding({ left: 10, right: 10 })
      .borderRadius(6)
      .border({ width: 1, color: '#2A2E36' })
      .margin({ right: 6 })
      .onClick(() => {
        action();
      })
  }

  @Builder
  MarksPanel() {
    Column() {
      Row() {
        Text('标记列表')
          .fontSize(12)
          .fontColor('#8B919A')
        Blank()
        Text('收起')
          .fontSize(11)
          .fontColor('#AAB0B9')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(5)
          .border({ width: 1, color: '#2A2E36' })
          .onClick(() => {
            this.marksOpen = false;
          })
      }
      .width('100%')
      .height(32)

      if (this.marks.length === 0) {
        Text('还没有标记。播放到需要记住的位置，点「＋ 标记」。')
          .fontSize(12)
          .fontColor('#6B7280')
          .lineHeight(20)
          .width('100%')
          .padding({ top: 8 })
      } else {
        List({ space: 2 }) {
          ForEach(this.marks, (mark: MarkItem) => {
            ListItem() {
              Row() {
                Text(formatTime(mark.t))
                  .fontSize(13)
                  .fontColor('#5EEAD4')
                  .width(64)
                Text('点击跳转')
                  .fontSize(12)
                  .fontColor('#8B919A')
                Blank()
                Text('×')
                  .fontSize(15)
                  .fontColor('#6B7280')
                  .width(32)
                  .height(28)
                  .textAlign(TextAlign.Center)
                  .borderRadius(4)
                  .onClick(() => {
                    this.removeMark(mark.id);
                  })
              }
              .width('100%')
              .height(40)
              .padding({ left: 6, right: 4 })
              .borderRadius(5)
              .onClick(() => {
                this.jumpToMark(mark);
              })
            }
          }, (mark: MarkItem) => mark.id)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 2 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ top: 6 })
    .margin({ top: 6 })
    .border({ width: { top: 1 }, color: '#2A2E36' })
  }

  @Builder
  PlayerPage() {
    Column() {
      Column() {
        // 标题栏
        Row() {
          Text('Easy Listen')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#5EEAD4')
          Text(this.trackName)
            .fontSize(13)
            .fontColor('#8B919A')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 8, right: 4 })
          this.IconButton('＋', false, (): void => {
            this.openLibrary();
          })
          this.IconButton('📌', this.pinned, (): void => {
            this.togglePin();
          })
          this.IconButton('×', false, (): void => {
            this.closeApp();
          })
        }
        .width('100%')
        .height(38)
        .alignItems(VerticalAlign.Center)

        // 进度
        Row() {
          Text(formatTime(this.currentMs))
            .fontSize(12)
            .fontColor('#8B919A')
            .width(52)
            .textAlign(TextAlign.Center)
          Slider({
            value: this.seekValue,
            min: 0,
            max: 100,
            step: 0.1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .selectedColor('#5EEAD4')
            .trackColor('#2B303A')
            .blockColor('#5EEAD4')
            .enabled(this.durationMs > 0)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.seekValue = value;
              if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                this.isSeeking = true;
                this.currentMs = (value / 100) * this.durationMs;
              } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.isSeeking = false;
                this.seekToPercent(value);
              }
            })
          Text(formatTime(this.durationMs))
            .fontSize(12)
            .fontColor('#8B919A')
            .width(52)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(42)

        // 播放控制
        Row() {
          this.SkipButton('-30', -30)
          this.SkipButton('-10', -10)
          this.SkipButton('-5', -5)
          Button(this.playing ? '⏸' : '▶')
            .fontSize(17)
            .fontColor('#0B1210')
            .width(50)
            .height(50)
            .borderRadius(25)
            .backgroundColor('#5EEAD4')
            .margin({ left: 5, right: 5 })
            .onClick(() => {
              this.togglePlay();
            })
          this.SkipButton('+5', 5)
          this.SkipButton('+10', 10)
          this.SkipButton('+30', 30)
        }
        .width('100%')
        .height(52)
        .margin({ top: 4 })

        // 音量
        Row() {
          Text('🔊')
            .fontSize(13)
            .fontColor('#8B919A')
            .width(26)
            .textAlign(TextAlign.Center)
          Slider({
            value: this.volume,
            min: 0,
            max: 100,
            step: 1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .selectedColor('#5EEAD4')
            .trackColor('#2B303A')
            .blockColor('#5EEAD4')
            .onChange((value: number) => {
              this.onVolumeChange(value);
            })
          Text(`${Math.round(this.volume)}%`)
            .fontSize(11)
            .fontColor('#8B919A')
            .width(42)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .height(32)
        .margin({ top: 2 })

        // 标记栏
        Row() {
          Text('＋ 标记')
            .fontSize(12)
            .fontColor('#5EEAD4')
            .textAlign(TextAlign.Center)
            .height(32)
            .padding({ left: 12, right: 12 })
            .borderRadius(6)
            .border({ width: 1, color: '#5EEAD4' })
            .backgroundColor('rgba(94, 234, 212, 0.12)')
            .margin({ right: 6 })
            .onClick(() => {
              this.addMark();
            })
          this.GhostButton('◀｜', (): void => {
            this.jumpToPrevMark();
          })
          this.GhostButton('｜▶', (): void => {
            this.jumpToNextMark();
          })
          Blank()
          Text(`标记 ${this.marks.length} ${this.marksOpen ? '▴' : '▾'}`)
            .fontSize(12)
            .fontColor('#AAB0B9')
            .textAlign(TextAlign.Center)
            .height(32)
            .padding({ left: 10, right: 10 })
            .borderRadius(6)
            .border({ width: 1, color: '#2A2E36' })
            .onClick(() => {
              this.marksOpen = !this.marksOpen;
            })
        }
        .width('100%')
        .height(36)
        .margin({ top: 10 })

        if (this.marksOpen) {
          this.MarksPanel()
        } else {
          Blank()
        }

        Text(this.hintText)
          .fontSize(10)
          .fontColor(this.hintText === DEFAULT_HINT ? '#646B75' : '#5EEAD4')
          .width('100%')
          .height(16)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#14161A')
      .border({ width: 1, color: '#2A2E36' })
      .borderRadius(12)
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .backgroundColor('#0D0F12')
  }

  @Builder
  LibraryPage() {
    Column() {
      Row() {
        Text('音频库')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E6E8EB')
        Blank()
        Text('完成')
          .fontSize(13)
          .fontColor('#5EEAD4')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor('#20242B')
          .onClick(() => {
            this.libraryOpen = false;
          })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)

      Row() {
        if (AudioLibrary.canPickFolder()) {
          Text('＋ 添加文件夹')
            .fontSize(12)
            .fontColor('#5EEAD4')
            .textAlign(TextAlign.Center)
            .height(36)
            .layoutWeight(1)
            .borderRadius(6)
            .border({ width: 1, color: '#5EEAD4' })
            .backgroundColor('rgba(94, 234, 212, 0.12)')
            .margin({ right: 8 })
            .onClick(() => {
              this.addFolder();
            })
        }
        Text('导入音频文件')
          .fontSize(12)
          .fontColor('#AAB0B9')
          .textAlign(TextAlign.Center)
          .height(36)
          .layoutWeight(1)
          .borderRadius(6)
          .border({ width: 1, color: '#2A2E36' })
          .onClick(() => {
            this.importFiles();
          })
      }
      .width('100%')
      .margin({ top: 4 })

      TextInput({ placeholder: '搜索音频文件名', text: this.libraryQuery })
        .placeholderColor('#646B75')
        .fontSize(13)
        .fontColor('#E6E8EB')
        .height(38)
        .backgroundColor('#20242B')
        .borderRadius(8)
        .margin({ top: 10 })
        .onChange((value: string) => {
          this.libraryQuery = value;
        })

      Scroll() {
        Row() {
          Text('全部')
            .fontSize(12)
            .fontColor(this.activeFolderUri === '' ? '#0B1210' : '#AAB0B9')
            .height(30)
            .padding({ left: 12, right: 12 })
            .borderRadius(15)
            .backgroundColor(this.activeFolderUri === '' ? '#5EEAD4' : '#20242B')
            .margin({ right: 8 })
            .onClick(() => {
              this.activeFolderUri = '';
            })
          ForEach(this.libraryFolders, (folder: AudioFolder) => {
            Row() {
              Text(folder.name)
                .fontSize(12)
                .fontColor(this.activeFolderUri === folder.uri ? '#0B1210' : '#AAB0B9')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 140 })
              Text(' ×')
                .fontSize(12)
                .fontColor(this.activeFolderUri === folder.uri ? '#0B1210' : '#8B919A')
                .onClick(() => {
                  this.removeFolder(folder);
                })
            }
            .height(30)
            .padding({ left: 12, right: 10 })
            .borderRadius(15)
            .backgroundColor(this.activeFolderUri === folder.uri ? '#5EEAD4' : '#20242B')
            .margin({ right: 8 })
            .onClick(() => {
              this.activeFolderUri = folder.uri;
            })
          }, (folder: AudioFolder) => folder.uri)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(38)
      .margin({ top: 8 })

      if (this.libraryBusy) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#5EEAD4')
          Text('正在扫描文件夹…')
            .fontSize(12)
            .fontColor('#8B919A')
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.filteredEntries().length === 0) {
        Text(this.libraryEntries.length === 0
          ? '还没有导入音频。先添加一个文件夹，一次导入其中的全部音频；也可以直接导入文件。'
          : '没有匹配的音频')
          .fontSize(12)
          .fontColor('#6B7280')
          .lineHeight(22)
          .width('100%')
          .layoutWeight(1)
          .padding({ top: 24, left: 4, right: 4 })
      } else {
        List({ space: 2 }) {
          ForEach(this.filteredEntries(), (entry: AudioEntry) => {
            ListItem() {
              Row() {
                Column() {
                  Text(entry.name)
                    .fontSize(13)
                    .fontColor(entry.uri === this.trackUri ? '#5EEAD4' : '#E6E8EB')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(entry.folderName === '' ? '单独导入' : entry.folderName)
                    .fontSize(10)
                    .fontColor('#6B7280')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (entry.uri === this.trackUri) {
                  Text('正在播放')
                    .fontSize(10)
                    .fontColor('#5EEAD4')
                    .margin({ left: 8 })
                }
                Text('×')
                  .fontSize(15)
                  .fontColor('#6B7280')
                  .width(32)
                  .height(32)
                  .textAlign(TextAlign.Center)
                  .borderRadius(4)
                  .onClick(() => {
                    this.removeEntry(entry);
                  })
              }
              .width('100%')
              .height(52)
              .padding({ left: 8, right: 4 })
              .borderRadius(6)
              .backgroundColor('#1B1E24')
              .onClick(() => {
                this.playFromLibrary(entry);
              })
            }
          }, (entry: AudioEntry) => entry.uri)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 6 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#14161A')
    .zIndex(10)
  }

  build() {
    Stack() {
      this.PlayerPage()
      if (this.libraryOpen) {
        this.LibraryPage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0D0F12')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handleKey(event);
    })
  }
}
