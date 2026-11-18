import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface PlayerEvents {
  onReady: (durationMs: number) => void;
  onProgress: (ms: number) => void;
  onPlayingChange: (playing: boolean) => void;
  onCompleted: () => void;
  onError: (message: string) => void;
}

export class AudioController {
  private player: media.AVPlayer | null = null;
  private file: fs.File | null = null;
  private events: PlayerEvents;
  private durationMs: number = 0;
  private loadToken: number = 0;

  constructor(events: PlayerEvents) {
    this.events = events;
  }

  async load(uri: string): Promise<void> {
    const token: number = ++this.loadToken;
    await this.release();
    try {
      const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(file.fd).size;
      const player: media.AVPlayer = await media.createAVPlayer();
      if (token !== this.loadToken) {
        await player.release();
        fs.closeSync(file);
        return;
      }

      this.file = file;
      this.player = player;
      this.durationMs = 0;

      player.on('stateChange', (state: media.AVPlayerState) => {
        if (this.player !== player) {
          return;
        }
        if (state === 'initialized') {
          player.prepare().catch((err: BusinessError) => {
            this.events.onError('无法播放：文件可能已移动、权限失效或格式不受支持');
          });
        } else if (state === 'prepared') {
          this.durationMs = player.duration;
          this.events.onReady(player.duration);
          player.play().catch((err: BusinessError) => {
            this.events.onError('播放失败，文件可能已移动或格式不受支持');
          });
        } else if (state === 'playing') {
          this.events.onPlayingChange(true);
        } else if (state === 'paused') {
          this.events.onPlayingChange(false);
        } else if (state === 'completed') {
          this.events.onPlayingChange(false);
          this.events.onCompleted();
        }
      });

      player.on('timeUpdate', (time: number) => {
        if (this.player !== player) {
          return;
        }
        this.events.onProgress(time);
      });

      player.on('error', (err: BusinessError) => {
        if (this.player !== player) {
          return;
        }
        this.events.onError('无法播放：文件可能已移动、权限失效或格式不受支持');
      });

      player.fdSrc = { fd: file.fd, offset: 0, length: size };
    } catch (err) {
      this.events.onError('无法播放：文件可能已移动、权限失效或格式不受支持');
    }
  }

  hasTrack(): boolean {
    return this.player !== null;
  }

  isPlaying(): boolean {
    return this.player !== null && this.player.state === 'playing';
  }

  getCurrentMs(): number {
    return this.player === null ? 0 : this.player.currentTime;
  }

  getDurationMs(): number {
    return this.durationMs;
  }

  async togglePlay(): Promise<void> {
    if (this.player === null) {
      return;
    }
    const state: media.AVPlayerState = this.player.state;
    if (state === 'playing') {
      await this.player.pause();
    } else if (state === 'paused' || state === 'prepared' || state === 'completed') {
      await this.player.play();
    }
  }

  seekTo(ms: number): void {
    if (this.player === null) {
      return;
    }
    const duration: number = this.durationMs > 0 ? this.durationMs : this.player.duration;
    let target: number = ms;
    if (Number.isFinite(duration) && duration > 0) {
      target = Math.min(target, Math.max(duration - 50, 0));
    }
    target = Math.max(target, 0);
    try {
      this.player.seek(Math.floor(target), media.SeekMode.SEEK_CLOSEST);
    } catch (err) {
      // 拖动/跳转过快时忽略瞬时失败
    }
  }

  // 返回实际跳转到的位置（毫秒）
  seekBy(deltaMs: number): number {
    if (this.player === null) {
      return 0;
    }
    const duration: number = this.durationMs > 0 ? this.durationMs : this.player.duration;
    let target: number = this.player.currentTime + deltaMs;
    if (Number.isFinite(duration) && duration > 0) {
      target = Math.min(target, Math.max(duration - 50, 0));
    }
    target = Math.max(target, 0);
    try {
      this.player.seek(Math.floor(target), media.SeekMode.SEEK_CLOSEST);
    } catch (err) {
      // 忽略瞬时失败
    }
    return target;
  }

  setVolume(percent: number): void {
    if (this.player === null) {
      return;
    }
    const value: number = Math.max(0, Math.min(1, percent / 100));
    try {
      this.player.setVolume(value);
    } catch (err) {
      // 播放器尚未就绪时忽略
    }
  }

  async release(): Promise<void> {
    const player: media.AVPlayer | null = this.player;
    const file: fs.File | null = this.file;
    this.player = null;
    this.file = null;
    this.durationMs = 0;

    if (player !== null) {
      try {
        player.off('stateChange');
        player.off('timeUpdate');
        player.off('error');
        await player.release();
      } catch (err) {
        // 释放失败忽略
      }
    }
    if (file !== null) {
      try {
        fs.closeSync(file);
      } catch (err) {
        // 关闭失败忽略
      }
    }
  }
}
