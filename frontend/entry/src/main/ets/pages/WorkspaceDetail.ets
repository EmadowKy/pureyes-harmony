import { HttpUtil, BASE_HOST } from '../utils/http'
import { QARecordInfo } from './tabs/WorkspaceTab'

interface ToastOptions {
  message: string;
  duration?: number;
}

export class WorkspaceVideoSegment {
  id: number = 0;
  workspace_id: number = 0;
  video_name: string = '';
  start_offset: number = 0;
  end_offset: number = 0;
  duration: number = 0;
  remark: string = '';
  filepath: string = '';
  media_url: string = '';
  thumbnail_url: string = '';
  created_at: string = '';
  isSelected: boolean = false; // UI selection state
  status: string = 'pending';
  progress: number = 0;
  error_msg: string = '';
  sample_fps: number = 1.0;
  resolution: string = '1080P';
  orig_resolution: string = '1080P';
}

export class TextChunk {
  content: string = '';
  isBold: boolean = false;
  isTimestamp: boolean = false;
  videoNum: number = 0;
  timeStr: string = '';
}

export function timeToSeconds(timeStr: string): number {
  if (!timeStr) {
    return 0;
  }
  const parts = timeStr.split(':').map(x => parseInt(x) || 0);
  if (parts.length === 2) {
    return parts[0] * 60 + parts[1];
  } else if (parts.length === 3) {
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  }
  return 0;
}

export function parseAnswerToChunks(answerText: string): Array<Array<TextChunk>> {
  if (!answerText) {
    return [];
  }
  const paragraphs = answerText.split('\n');
  const result: Array<Array<TextChunk>> = [];
  const tsRegex = /\[video:\s*["']?([^"',\]]+)["']?\s*,\s*time:\s*["']?([^"',\s\]\*]+)["']?\]?/g;
  const boldRegex = /\*\*([^*]+)\*\*/g;

  for (let i = 0; i < paragraphs.length; i++) {
    let paraText = paragraphs[i];
    if (!paraText) {
      const emptyChunk = new TextChunk();
      emptyChunk.content = '';
      result.push([emptyChunk]);
      continue;
    }

    let isBullet = false;
    const bulletMatch = paraText.match(/^(\s*[*•-]\s+)/);
    if (bulletMatch) {
      isBullet = true;
      paraText = paraText.substring(bulletMatch[0].length);
    }

    const paraChunks: Array<TextChunk> = [];
    
    // Phase 1: Parse bold first
    const boldChunks: Array<Record<string, Object>> = [];
    let lastIdx = 0;
    let boldMatch: RegExpExecArray | null = null;
    boldRegex.lastIndex = 0;

    while ((boldMatch = boldRegex.exec(paraText)) !== null) {
      if (boldMatch.index > lastIdx) {
        boldChunks.push({
          "content": paraText.substring(lastIdx, boldMatch.index),
          "isBold": false
        });
      }
      boldChunks.push({
        "content": boldMatch[1],
        "isBold": true
      });
      lastIdx = boldRegex.lastIndex;
    }

    if (lastIdx < paraText.length) {
      boldChunks.push({
        "content": paraText.substring(lastIdx),
        "isBold": false
      });
    }

    if (boldChunks.length === 0) {
      boldChunks.push({ "content": paraText, "isBold": false });
    }

    // Phase 2: For each bold chunk, parse timestamps
    let isFirst = true;
    for (let j = 0; j < boldChunks.length; j++) {
      const bc = boldChunks[j];
      const isBold = bc["isBold"] as boolean;
      const textToParse = bc["content"] as string;

      tsRegex.lastIndex = 0;
      let tsLastIdx = 0;
      let tsMatch: RegExpExecArray | null = null;

      while ((tsMatch = tsRegex.exec(textToParse)) !== null) {
        if (tsMatch.index > tsLastIdx) {
          let contentStr = textToParse.substring(tsLastIdx, tsMatch.index);
          if (isFirst && isBullet) {
            contentStr = "•  " + contentStr;
            isFirst = false;
          }
          const chunk = new TextChunk();
          chunk.content = contentStr;
          chunk.isBold = isBold;
          paraChunks.push(chunk);
        }

        const vNumStr = tsMatch[1].trim();
        const tStr = tsMatch[2].trim();
        
        let videoNum = parseInt(vNumStr);
        if (isNaN(videoNum)) {
          const code = vNumStr.toUpperCase().charCodeAt(0);
          if (code >= 65 && code <= 90) {
            videoNum = code - 65 + 1;
          } else {
            videoNum = 1;
          }
        }

        let contentStr = `视频${videoNum}(${tStr})`;
        if (isFirst && isBullet) {
          contentStr = "•  " + contentStr;
          isFirst = false;
        }

        const chunk = new TextChunk();
        chunk.content = contentStr;
        chunk.isBold = isBold;
        chunk.isTimestamp = true;
        chunk.videoNum = videoNum;
        chunk.timeStr = tStr;
        paraChunks.push(chunk);

        tsLastIdx = tsRegex.lastIndex;
      }

      if (tsLastIdx < textToParse.length) {
        let contentStr = textToParse.substring(tsLastIdx);
        if (isFirst && isBullet) {
          contentStr = "•  " + contentStr;
          isFirst = false;
        }
        const chunk = new TextChunk();
        chunk.content = contentStr;
        chunk.isBold = isBold;
        paraChunks.push(chunk);
      }
    }

    result.push(paraChunks);
  }

  return result;
}

export function formatAnswerToPlainText(answerText: string): string {
  if (!answerText) {
    return '';
  }
  const tsRegex = /\[video:\s*["']?([^"',\]]+)["']?\s*,\s*time:\s*["']?([^"',\s\]\*]+)["']?\]?/g;
  let formatted = answerText.replace(tsRegex, (match: string, vNumStr: string, tStr: string): string => {
    let videoNum = parseInt(vNumStr.trim());
    if (isNaN(videoNum)) {
      const code = vNumStr.trim().toUpperCase().charCodeAt(0);
      if (code >= 65 && code <= 90) {
        videoNum = code - 65 + 1;
      } else {
        videoNum = 1;
      }
    }
    return `视频${videoNum}(${tStr.trim()})`;
  });
  
  const lines = formatted.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const bulletMatch = lines[i].match(/^(\s*[*•-]\s+)/);
    if (bulletMatch) {
      lines[i] = "•  " + lines[i].substring(bulletMatch[0].length);
    }
  }
  formatted = lines.join('\n');
  formatted = formatted.replace(/\*\*([^*]+)\*\*/g, '$1');
  return formatted;
}

export class ExampleVideoInfo {
  id: string = '';
  name: string = '';
  url: string = '';
  media_url: string = '';
  filepath: string = '';
  duration: number = 0;
  source_type: string = 'monitor';
  monitor_id: number = 0;
  monitor_name: string = '';
  has_recordings: boolean = false;
  earliest_time: string = '';
  latest_time: string = '';
  isSelected: boolean = false;
  startOffset: number = 0;
  endOffset: number = 0;
}

export class WorkspaceFaceGroupInfo {
  id: number = 0;
  workspace_id: number = 0;
  name: string = '';
  avatar_path: string = '';
  avatar_url: string = '';
  record_count: number = 0;
}

export class WorkspaceFaceRecordInfo {
  id: number = 0;
  workspace_id: number = 0;
  group_id: number = 0;
  segment_id: number = 0;
  segment_filepath: string = '';
  segment_media_url: string = '';
  crop_path: string = '';
  crop_url: string = '';
  video_name: string = '';
  start_time_offset: number = 0;
  end_time_offset: number = 0;
  time_range_str: string = '';
}

export class ProgressGroup {
  id: string = '';
  title: string = '';
  isCompleted: boolean = false;
  isFailed: boolean = false;
  isCollapsed: boolean = false;
  details: Array<string> = [];
  badgeText: string = '';
}

@CustomDialog
struct MonitorTimeRangeDialog {
  controller: CustomDialogController
  activeVideo: ExampleVideoInfo = new ExampleVideoInfo();
  @State startTimeText: string = '';
  @State endTimeText: string = '';
  @State remarkText: string = '';
  @State enablePreprocess: boolean = true;
  @State selectedFps: number = 1.0;
  @State selectedResolution: string = '1080P';

  confirm: (startTime: string, endTime: string, remark: string, enablePreprocess: boolean, sampleFps: number, resolution: string) => void =
    (_start: string, _end: string, _remark: string, _enable: boolean, _fps: number, _res: string): void => {};

  aboutToAppear(): void {
    if (this.activeVideo.latest_time && this.activeVideo.latest_time.length > 10 && this.activeVideo.latest_time.indexOf(':') !== -1) {
      this.endTimeText = this.activeVideo.latest_time;
      this.startTimeText = this.computeShiftedTime(this.activeVideo.latest_time, -3);
    } else {
      const now = new Date();
      this.endTimeText = this.formatDateTime(now);
      now.setMinutes(now.getMinutes() - 3);
      this.startTimeText = this.formatDateTime(now);
    }
    this.enablePreprocess = true;
    this.selectedFps = 1.0;
    this.selectedResolution = '1080P';
  }

  computeShiftedTime(baseStr: string, minutes: number): string {
    const match = baseStr.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/);
    if (!match) return baseStr;
    const d = new Date(
      Number(match[1]), Number(match[2]) - 1, Number(match[3]),
      Number(match[4]), Number(match[5]), Number(match[6])
    );
    d.setMinutes(d.getMinutes() + minutes);
    return this.formatDateTime(d);
  }

  formatDateTime(d: Date): string {
    const pad = (n: number): string => n.toString().padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  @Builder ParameterOption(label: string, isSelected: boolean, action: () => void) {
    Button(label)
      .height(32)
      .layoutWeight(1)
      .fontSize(11)
      .fontWeight(isSelected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(isSelected ? $r('app.color.app_text_primary') : $r('app.color.app_text_secondary'))
      .backgroundColor(Color.Transparent)
      .border({
        width: { bottom: isSelected ? 3 : 1 },
        color: isSelected ? $r('app.color.app_accent') : $r('app.color.app_border')
      })
      .borderRadius(0)
      .onClick(action)
  }

  @Builder QuickRange(label: string, minutes: number) {
    Button(label)
      .fontSize(11)
      .fontColor($r('app.color.app_text_primary'))
      .height(28)
      .backgroundColor(Color.Transparent)
      .border({ width: { bottom: 1 }, color: $r('app.color.app_border') })
      .borderRadius(0)
      .onClick((): void => {
        const base = (this.activeVideo.latest_time && this.activeVideo.latest_time.indexOf(':') !== -1) ?
          this.activeVideo.latest_time : this.formatDateTime(new Date());
        this.endTimeText = base;
        this.startTimeText = this.computeShiftedTime(base, -minutes);
      })
  }

  build() {
    Column({ space: 12 }) {
      Text(`截取监控视频 (${this.activeVideo.monitor_name || this.activeVideo.name})`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      Scroll() {
        Column({ space: 14 }) {
          Row() {
            Text('录像可用时间段:')
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
            Text(`${this.activeVideo.earliest_time} ~ ${this.activeVideo.latest_time}`)
              .fontSize(11)
              .fontColor('#1E40AF')
              .fontWeight(FontWeight.Medium)
              .margin({ left: 6 })
          }
          .width('100%')

          Row({ space: 6 }) {
            Text('快捷填充:')
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))

            this.QuickRange('最近 1 分钟', 1)
            this.QuickRange('最近 3 分钟', 3)
            this.QuickRange('最近 5 分钟', 5)
          }
          .width('100%')

          Column({ space: 6 }) {
            Text('起始日期时间 (YYYY-MM-DD HH:mm:ss):')
              .fontSize(12)
              .fontColor($r('app.color.app_text_primary'))
              .alignSelf(ItemAlign.Start)

            TextInput({ text: this.startTimeText, placeholder: '2026-07-25 10:00:00' })
              .height(40)
              .fontSize(13)
              .onChange((val: string): void => {
                this.startTimeText = val;
              })

            Text('结束日期时间 (YYYY-MM-DD HH:mm:ss):')
              .fontSize(12)
              .fontColor($r('app.color.app_text_primary'))
              .alignSelf(ItemAlign.Start)
              .margin({ top: 6 })

            TextInput({ text: this.endTimeText, placeholder: '2026-07-25 10:05:00' })
              .height(40)
              .fontSize(13)
              .onChange((val: string): void => {
                this.endTimeText = val;
              })
          }
          .width('100%')

          // AI 预处理设置板块 (浅蓝色背景卡片)
          Column({ space: 10 }) {
            Row() {
              Column({ space: 2 }) {
                Text('开启 AI 特征提取与识别预处理')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1E40AF')
                Text('截取后将在后台自动识别图像物体及行为')
                  .fontSize(11)
                  .fontColor('#3B82F6')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.enablePreprocess })
                .selectedColor($r('app.color.app_primary'))
                .onChange((isOn: boolean): void => {
                  this.enablePreprocess = isOn;
                })
            }
            .width('100%')

            if (this.enablePreprocess) {
              // 采样帧率设置
              Column({ space: 8 }) {
                Row() {
                  Text('预处理采样帧率 (FPS):')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1E3A8A')
                  Blank()
                  Text(`${this.selectedFps.toFixed(1)} FPS`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#2563EB')
                }
                .width('100%')

                Row({ space: 6 }) {
                  this.ParameterOption('0.5 FPS', this.selectedFps === 0.5, (): void => { this.selectedFps = 0.5; })
                  this.ParameterOption('1.0 FPS · 推荐', this.selectedFps === 1.0, (): void => { this.selectedFps = 1.0; })
                  this.ParameterOption('2.0 FPS', this.selectedFps === 2.0, (): void => { this.selectedFps = 2.0; })
                }
                .width('100%')
              }
              .width('100%')

              // 预处理画质清晰度选择 (480P, 720P, 1080P, 4K)
              Column({ space: 8 }) {
                Row() {
                  Text('预处理画质清晰度:')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1E3A8A')
                  Blank()
                  Text(this.selectedResolution)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#2563EB')
                }
                .width('100%')

                Row({ space: 6 }) {
                  this.ParameterOption('480P', this.selectedResolution === '480P', (): void => { this.selectedResolution = '480P'; })
                  this.ParameterOption('720P', this.selectedResolution === '720P', (): void => { this.selectedResolution = '720P'; })
                  this.ParameterOption('1080P · 推荐', this.selectedResolution === '1080P', (): void => { this.selectedResolution = '1080P'; })
                  this.ParameterOption('4K', this.selectedResolution === '4K', (): void => { this.selectedResolution = '4K'; })
                }
                .width('100%')
              }
              .width('100%')
              .margin({ top: 2 })
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.app_border') })

          Column({ space: 4 }) {
            Text('片段备注/说明 (可选):')
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
              .alignSelf(ItemAlign.Start)

            TextInput({ text: this.remarkText, placeholder: '请输入片段备注/说明' })
              .height(40)
              .fontSize(13)
              .onChange((val: string): void => {
                this.remarkText = val;
              })
          }
          .width('100%')
        }
      }
      .constraintSize({ maxHeight: '75%' })

      Row({ space: 12 }) {
        Button('取消')
          .fontSize(13)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.app_text_primary'))
          .border({ width: 1, color: $r('app.color.app_border') })
          .borderRadius(8)
          .onClick((): void => {
            this.controller.close();
          })

        Button('确认拼接截取')
          .fontSize(13)
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.app_surface_inverted'))
          .fontColor($r('app.color.app_text_on_inverted'))
          .borderRadius(8)
          .onClick((): void => {
            this.confirm(
              this.startTimeText,
              this.endTimeText,
              this.remarkText,
              this.enablePreprocess,
              this.selectedFps,
              this.selectedResolution
            );
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(16)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(12)
  }
}

@CustomDialog
struct FaceImagePreviewDialog {
  controller: CustomDialogController
  imageUrl: string = '';

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('查看高清人脸特写')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Blank()
        Button('✕')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: '#80FFFFFF' })
          .width(30)
          .height(30)
          .borderRadius(7)
          .onClick((): void => {
            this.controller.close();
          })
      }
      .width('100%')

      Image(this.imageUrl)
        .width('95%')
        .objectFit(ImageFit.Contain)
        .borderRadius(8)
    }
    .padding(16)
    .backgroundColor('rgba(0, 0, 0, 0.88)')
    .borderRadius(12)
  }
}

@CustomDialog
struct FaceDetailDialog {
  controller: CustomDialogController
  group: WorkspaceFaceGroupInfo = new WorkspaceFaceGroupInfo();
  records: Array<WorkspaceFaceRecordInfo> = [];
  onRecordClick: (record: WorkspaceFaceRecordInfo) => void = (_r): void => {};
  onPreviewImage: (imageUrl: string) => void = (_url): void => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Image(this.group.avatar_url ? (BASE_HOST + this.group.avatar_url) : $r('app.media.business_face_library'))
          .width(42)
          .height(42)
          .borderRadius(21)
          .objectFit(ImageFit.Cover)

        Column({ space: 2 }) {
          Text(this.group.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
          Text(`在当前工作区共识别到 ${this.records.length} 条时间段记录`)
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })

        Blank()

        Button('关闭')
          .fontSize(12)
          .height(30)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.app_text_secondary'))
          .border({ width: 1, color: $r('app.color.app_border') })
          .borderRadius(7)
          .onClick((): void => {
            this.controller.close();
          })
      }
      .width('100%')
      .padding({ bottom: 6 })

      Divider().color($r('app.color.app_border'))

      if (this.records.length > 0) {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.records, (rec: WorkspaceFaceRecordInfo): void => {
              Row({ space: 12 }) {
                // 左边：这个人脸在这一段的图片，点击可以查看大图
                Image(rec.crop_url ? (BASE_HOST + rec.crop_url) : $r('app.media.business_face_library'))
                  .width(64)
                  .height(64)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .border({ width: 1, color: $r('app.color.app_border') })
                  .onClick((): void => {
                    if (rec.crop_url) {
                      this.onPreviewImage(BASE_HOST + rec.crop_url);
                    }
                  })

                // 右边：显示了视频备注和时间段，点击可以展示视频并跳转到起始时间
                Column({ space: 5 }) {
                  Text(rec.video_name || '未命名视频片段')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row() {
                    Text('出现时间段: ')
                      .fontSize(12)
                      .fontColor($r('app.color.app_text_secondary'))
                    Text(rec.time_range_str)
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.app_selection'))
                  }

                  Text('点击播放视频并精准跳转到起始时间 ➔')
                    .fontSize(10)
                    .fontColor($r('app.color.app_text_muted'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .onClick((): void => {
                  this.onRecordClick(rec);
                  this.controller.close();
                })
              }
              .width('100%')
              .padding(10)
              .backgroundColor($r('app.color.app_card_subtle_bg'))
              .borderRadius(8)
              .border({ width: 1, color: $r('app.color.app_border') })
            })
          }
        }
        .constraintSize({ maxHeight: '70%' })
      } else {
        Text('暂无识别记录')
          .fontSize(13)
          .fontColor($r('app.color.app_text_muted'))
          .margin(20)
      }
    }
    .padding(16)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(12)
  }
}

@CustomDialog
struct VideoRangeDialog {
  controller: CustomDialogController
  activeVideo: ExampleVideoInfo = new ExampleVideoInfo();
  @State startOffset: number = 0;
  @State endOffset: number = 0;
  @State remarkText: string = '';
  @State enablePreprocess: boolean = true;
  @State selectedFps: number = 1.0;
  @State selectedResolution: string = '1080P';

  confirm: (start: number, end: number, remark: string, enablePreprocess: boolean, sampleFps: number, resolution: string) => void =
    (_start: number, _end: number, _remark: string, _enable: boolean, _fps: number, _res: string): void => {};
  
  videoController: VideoController = new VideoController();

  aboutToAppear(): void {
    this.startOffset = this.activeVideo.startOffset;
    this.endOffset = this.activeVideo.endOffset > 0 ? this.activeVideo.endOffset : this.activeVideo.duration;
    this.enablePreprocess = true;
    this.selectedFps = 1.0;
    this.selectedResolution = '1080P';
  }

  @Builder ParameterOption(label: string, isSelected: boolean, action: () => void) {
    Button(label)
      .height(32)
      .layoutWeight(1)
      .fontSize(11)
      .fontWeight(isSelected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(isSelected ? $r('app.color.app_text_primary') : $r('app.color.app_text_secondary'))
      .backgroundColor(Color.Transparent)
      .border({
        width: { bottom: isSelected ? 3 : 1 },
        color: isSelected ? $r('app.color.app_accent') : $r('app.color.app_border')
      })
      .borderRadius(0)
      .onClick(action)
  }

  build() {
    Column({ space: 12 }) {
      Text('截取视频片段')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      Scroll() {
        Column({ space: 14 }) {
          Text(this.activeVideo.name)
            .fontSize(14)
            .fontColor($r('app.color.app_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Video({
            src: this.activeVideo.url,
            controller: this.videoController
          })
            .width('100%')
            .height(180)
            .autoPlay(true)
            .controls(true)
            .borderRadius(8)

          Column({ space: 8 }) {
            Row() {
              Text(`开始: ${this.startOffset.toFixed(1)}s`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.app_text_primary'))
              Blank()
              Text(`结束: ${this.endOffset.toFixed(1)}s`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.app_text_primary'))
            }
            .width('100%')

            Text('拖动选择起始时间:')
              .fontSize(11)
              .fontColor($r('app.color.app_text_secondary'))
              .alignSelf(ItemAlign.Start)
            Slider({
              value: this.startOffset,
              min: 0,
              max: this.activeVideo.duration,
              step: 0.1
            })
              .blockColor($r('app.color.app_primary'))
              .trackColor($r('app.color.app_text_muted'))
              .selectedColor($r('app.color.app_primary'))
              .width('100%')
              .onChange((val: number): void => {
                this.startOffset = Math.min(val, this.endOffset - 0.5);
                this.videoController.setCurrentTime(this.startOffset);
              })

            Text('拖动选择截止时间:')
              .fontSize(11)
              .fontColor($r('app.color.app_text_secondary'))
              .alignSelf(ItemAlign.Start)
            Slider({
              value: this.endOffset,
              min: 0,
              max: this.activeVideo.duration,
              step: 0.1
            })
              .blockColor($r('app.color.app_primary'))
              .trackColor($r('app.color.app_text_muted'))
              .selectedColor($r('app.color.app_primary'))
              .width('100%')
              .onChange((val: number): void => {
                this.endOffset = Math.max(val, this.startOffset + 0.5);
                this.videoController.setCurrentTime(this.endOffset);
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.app_page_bg'))
          .borderRadius(8)

          TextInput({ placeholder: '请输入片段备注', text: this.remarkText })
            .width('100%')
            .height(45)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((value: string): void => {
              this.remarkText = value;
            })

          // 视频特征预处理设置板块 (浅蓝色背景卡片)
          Column({ space: 10 }) {
            Row() {
              Column({ space: 2 }) {
                Text('开启 AI 特征提取与识别预处理')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1E40AF')
                Text('截取后将在后台自动识别图像物体及行为')
                  .fontSize(11)
                  .fontColor('#3B82F6')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.enablePreprocess })
                .selectedColor($r('app.color.app_primary'))
                .onChange((isOn: boolean): void => {
                  this.enablePreprocess = isOn;
                })
            }
            .width('100%')

            if (this.enablePreprocess) {
              // 采样帧率
              Column({ space: 8 }) {
                Row() {
                  Text('预处理采样帧率 (FPS):')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1E3A8A')
                  Blank()
                  Text(`${this.selectedFps.toFixed(1)} FPS`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#2563EB')
                }
                .width('100%')

                Row({ space: 6 }) {
                  this.ParameterOption('0.5 FPS', this.selectedFps === 0.5, (): void => { this.selectedFps = 0.5; })
                  this.ParameterOption('1.0 FPS · 推荐', this.selectedFps === 1.0, (): void => { this.selectedFps = 1.0; })
                  this.ParameterOption('2.0 FPS', this.selectedFps === 2.0, (): void => { this.selectedFps = 2.0; })
                }
                .width('100%')
              }
              .width('100%')

              // 预处理画质清晰度
              Column({ space: 8 }) {
                Row() {
                  Text('预处理画质清晰度:')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1E3A8A')
                  Blank()
                  Text(this.selectedResolution)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#2563EB')
                }
                .width('100%')

                Row({ space: 6 }) {
                  this.ParameterOption('480P', this.selectedResolution === '480P', (): void => { this.selectedResolution = '480P'; })
                  this.ParameterOption('720P', this.selectedResolution === '720P', (): void => { this.selectedResolution = '720P'; })
                  this.ParameterOption('1080P · 推荐', this.selectedResolution === '1080P', (): void => { this.selectedResolution = '1080P'; })
                  this.ParameterOption('4K', this.selectedResolution === '4K', (): void => { this.selectedResolution = '4K'; })
                }
                .width('100%')
              }
              .width('100%')
              .margin({ top: 2 })
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.app_border') })

          Row({ space: 20 }) {
            Button('取消')
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.app_text_primary'))
              .border({ width: 1, color: $r('app.color.app_border') })
              .borderRadius(8)
              .width(100)
              .height(40)
              .onClick((): void => {
                this.controller.close();
              })

            Button('确认')
              .backgroundColor($r('app.color.app_surface_inverted'))
              .fontColor($r('app.color.app_text_on_inverted'))
              .borderRadius(8)
              .width(100)
              .height(40)
              .onClick((): void => {
                this.confirm(this.startOffset, this.endOffset, this.remarkText, this.enablePreprocess, this.selectedFps, this.selectedResolution);
                this.controller.close();
              })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .width('100%')
    }
    .padding(16)
    .width('95%')
    .constraintSize({ maxHeight: '85%' })
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(12)
  }
}

@CustomDialog
struct SegmentDetailDialog {
  controller: CustomDialogController
  @Prop segment: WorkspaceVideoSegment = new WorkspaceVideoSegment();
  @State remarkText: string = '';
  @State isEditingRemark: boolean = false;
  @State showDeleteConfirm: boolean = false;
  @State selectedFps: number = 1.0;
  @State selectedResolution: string = '1080P';
  showSelectionActions: boolean = false;
  @Prop jumpSeconds: number = 0;
  onUpdate: (remark: string) => void = (_remark: string): void => {};
  onDelete: () => void = (): void => {};
  onConfirmSelection: () => void = (): void => {};
  onPreprocess: (sampleFps: number, resolution: string) => void = (_fps: number, _res: string): void => {};
  onDeleteFeatures: () => void = (): void => {};

  videoController: VideoController = new VideoController();

  aboutToAppear(): void {
    this.remarkText = this.segment.remark;
    this.isEditingRemark = false;
    this.showDeleteConfirm = false;
    this.selectedFps = this.segment.sample_fps || 1.0;
    this.selectedResolution = this.segment.resolution || '1080P';
  }

  isResAllowed(resOption: string, origRes: string): boolean {
    const resMap: Record<string, number> = {
      '480P': 1,
      '720P': 2,
      '1080P': 3,
      '4K': 4
    };
    const optLevel = resMap[resOption] || 1;
    const origLevel = resMap[origRes || '1080P'] || 3;
    return optLevel <= origLevel;
  }

  @Builder ParameterOption(label: string, isSelected: boolean, isEnabled: boolean, action: () => void) {
    Button(label)
      .height(32)
      .layoutWeight(1)
      .fontSize(11)
      .fontWeight(isSelected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(isSelected ? $r('app.color.app_text_primary') : $r('app.color.app_text_secondary'))
      .backgroundColor(Color.Transparent)
      .border({
        width: { bottom: isSelected ? 3 : 1 },
        color: isSelected ? $r('app.color.app_accent') : $r('app.color.app_border')
      })
      .borderRadius(0)
      .enabled(isEnabled)
      .opacity(isEnabled ? 1 : 0.35)
      .onClick(action)
  }

  build() {
    Column({ space: 12 }) {
      // 1. 顶部 Header 行 (固定在顶部)
      Row() {
        // 左上角返回/关闭图标
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('app.color.app_text_primary')])
        }
        .width(36)
        .height(36)
        .borderRadius(8)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: $r('app.color.app_border') })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.controller.close();
        })

        Text('片段详情')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 右上角垃圾桶删除图标（非选择模式下显示）
        if (!this.showSelectionActions) {
          Row() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(18)
              .fontColor(['#EF4444'])
          }
          .width(36)
          .height(36)
          .borderRadius(8)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.app_danger') })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.showDeleteConfirm = true;
          })
        } else {
          Blank().width(36)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 2. 可平滑上下滚动的主体内容区域
      Scroll() {
        Column({ space: 14 }) {
          // 删除确认弹框 / 提示条
          if (this.showDeleteConfirm) {
            Column({ space: 10 }) {
              Text('确认要删除该视频片段吗？')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor('#EF4444')
              
              Row({ space: 12 }) {
                Button('确定删除')
                  .backgroundColor('#EF4444')
                  .fontColor(Color.White)
                  .borderRadius(8)
                  .height(34)
                  .fontSize(13)
                  .layoutWeight(1)
                  .onClick((): void => {
                    this.onDelete();
                    this.controller.close();
                  })

                Button('取消')
                  .backgroundColor(Color.Transparent)
                  .fontColor($r('app.color.app_text_primary'))
                  .border({ width: 1, color: $r('app.color.app_border') })
                  .borderRadius(8)
                  .height(34)
                  .fontSize(13)
                  .layoutWeight(1)
                  .onClick((): void => {
                    this.showDeleteConfirm = false;
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FEF2F2')
            .borderRadius(10)
            .border({ width: 1, color: '#FCA5A5' })
          }

          // 视频播放器
          Video({
            src: BASE_HOST + this.segment.media_url,
            controller: this.videoController
          })
            .width('100%')
            .height(180)
            .autoPlay(true)
            .controls(true)
            .borderRadius(8)
            .onPrepared((event) => {
              if (this.jumpSeconds > 0) {
                this.videoController.setCurrentTime(this.jumpSeconds);
              }
            })

          // 视频信息：监控名称及时间范围
          Text(`${this.segment.video_name} (${this.segment.start_offset.toFixed(1)}s - ${this.segment.end_offset.toFixed(1)}s)`)
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          // 视频下方直接显示备注及修改逻辑
          Column({ space: 8 }) {
            if (!this.isEditingRemark) {
              // 展示模式：备注内容 + 铅笔修改图标
              Row() {
                Column({ space: 2 }) {
                  Text('片段备注')
                    .fontSize(11)
                    .fontColor('#9CA3AF')
                  Text(this.remarkText ? this.remarkText : '暂无备注')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.remarkText ? $r('app.color.app_text_primary') : '#9CA3AF')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                // 铅笔图标（点击变成可编辑文本框）
                if (!this.showSelectionActions) {
                  Row() {
                    SymbolGlyph($r('sys.symbol.square_and_pencil'))
                      .fontSize(18)
                      .fontColor([$r('app.color.app_text_primary')])
                  }
                  .width(32)
                  .height(32)
                  .borderRadius(8)
                  .backgroundColor(Color.Transparent)
                  .border({ width: 1, color: $r('app.color.app_border') })
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                  .onClick((): void => {
                    this.isEditingRemark = true;
                  })
                }
              }
              .width('100%')
              .padding(10)
              .backgroundColor($r('app.color.app_card_subtle_bg'))
              .borderRadius(8)
              .alignItems(VerticalAlign.Center)
            } else {
              // 编辑模式：可修改的文本框 + 保存/取消操作按钮
              Column({ space: 8 }) {
                Text('编辑片段备注')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.app_text_primary'))
                  .width('100%')

                TextInput({ placeholder: '请输入新备注', text: this.remarkText })
                  .width('100%')
                  .height(42)
                  .fontColor($r('app.color.app_text_primary'))
                  .backgroundColor($r('app.color.app_input_bg'))
                  .onChange((value: string): void => {
                    this.remarkText = value;
                  })

                Row({ space: 10 }) {
                  Button('保存备注')
                    .backgroundColor($r('app.color.app_surface_inverted'))
                    .fontColor($r('app.color.app_text_on_inverted'))
                    .borderRadius(8)
                    .height(36)
                    .fontSize(13)
                    .layoutWeight(1)
                    .onClick((): void => {
                      this.onUpdate(this.remarkText);
                      this.isEditingRemark = false;
                    })

                  Button('取消')
                    .backgroundColor(Color.Transparent)
                    .fontColor($r('app.color.app_text_primary'))
                    .border({ width: 1, color: $r('app.color.app_border') })
                    .borderRadius(8)
                    .height(36)
                    .fontSize(13)
                    .layoutWeight(1)
                    .onClick((): void => {
                      this.remarkText = this.segment.remark;
                      this.isEditingRemark = false;
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(10)
              .backgroundColor($r('app.color.app_card_subtle_bg'))
              .borderRadius(8)
            }
          }
          .width('100%')

          // 预处理部分（位于备注正下方）
          Column({ space: 10 }) {
            Text('视频特征预处理')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
              .width('100%')

            if (this.segment.status === 'completed') {
              // 1. 已预处理状态：展示精度信息，并提供删除预处理按钮
              Row() {
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text('已预处理')
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.app_success'))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .border({ width: 1, color: $r('app.color.app_success') })
                      .borderRadius(4)
                    Text('特征提炼就绪')
                      .fontSize(12)
                      .fontColor($r('app.color.app_text_secondary'))
                  }

                  Text(`帧采样率: ${this.segment.sample_fps || 1} 帧/秒  |  画质: ${this.segment.resolution || '1080P'}`)
                    .fontSize(12)
                    .fontColor($r('app.color.app_text_primary'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (!this.showSelectionActions) {
                  Button('删除预处理')
                    .fontSize(12)
                    .fontColor($r('app.color.app_danger'))
                    .backgroundColor(Color.Transparent)
                    .border({ width: 1, color: $r('app.color.app_danger') })
                    .borderRadius(8)
                    .height(32)
                    .onClick((): void => {
                      this.onDeleteFeatures();
                    })
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.app_card_subtle_bg'))
              .borderRadius(8)
              .border({ width: { left: 3, right: 1, top: 1, bottom: 1 }, color: $r('app.color.app_success') })
              .alignItems(VerticalAlign.Center)

            } else if (this.segment.status === 'processing' || this.segment.status === 'pending') {
              // 2. 正在预处理状态：显示当前设置的精度与进度条
              Column({ space: 8 }) {
                Row() {
                  Text(`正在预处理 (${this.segment.sample_fps || 1} 帧/秒, ${this.segment.resolution || '1080P'})`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_selection'))
                    .layoutWeight(1)
                  Text(`${this.segment.progress}%`)
                    .fontSize(12)
                    .fontColor($r('app.color.app_selection'))
                }
                .width('100%')

                Progress({ value: this.segment.progress, total: 100, type: ProgressType.Linear })
                  .width('100%')
                  .height(8)
                  .color($r('app.color.app_primary'))
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.app_card_subtle_bg'))
              .borderRadius(8)
              .border({ width: { left: 3, right: 1, top: 1, bottom: 1 }, color: $r('app.color.app_selection') })

            } else {
              // 3. 失败或未预处理状态：展示失败原因（若失败） + 精度选择器 + 开始/重新预处理按钮
              Column({ space: 10 }) {
                if (this.segment.status === 'failed') {
                  Text('预处理失败原因: ' + (this.segment.error_msg || '未知错误'))
                    .fontSize(12)
                    .fontColor($r('app.color.app_danger'))
                    .backgroundColor($r('app.color.app_card_subtle_bg'))
                    .padding(8)
                    .borderRadius(6)
                    .width('100%')
                }

                // A. 采样率选择 (0.5, 1, 2)
                Column({ space: 4 }) {
                  Text('帧采样率')
                    .fontSize(11)
                    .fontColor($r('app.color.app_text_secondary'))
                    .width('100%')

                  Row({ space: 8 }) {
                    this.ParameterOption('0.5 帧/秒', this.selectedFps === 0.5, true, (): void => { this.selectedFps = 0.5; })
                    this.ParameterOption('1 帧/秒 · 推荐', this.selectedFps === 1.0, true, (): void => { this.selectedFps = 1.0; })
                    this.ParameterOption('2 帧/秒', this.selectedFps === 2.0, true, (): void => { this.selectedFps = 2.0; })
                  }
                  .width('100%')
                }

                // B. 画质清晰度选择 (480P, 720P, 1080P, 4K)，约束不超过原画
                Column({ space: 4 }) {
                  Text(`画质清晰度 (原画: ${this.segment.orig_resolution || '1080P'})`)
                    .fontSize(11)
                    .fontColor($r('app.color.app_text_secondary'))
                    .width('100%')

                  Row({ space: 6 }) {
                    this.ParameterOption('480P', this.selectedResolution === '480P', true, (): void => { this.selectedResolution = '480P'; })
                    this.ParameterOption('720P', this.selectedResolution === '720P', this.isResAllowed('720P', this.segment.orig_resolution), (): void => { this.selectedResolution = '720P'; })
                    this.ParameterOption('1080P', this.selectedResolution === '1080P', this.isResAllowed('1080P', this.segment.orig_resolution), (): void => { this.selectedResolution = '1080P'; })
                    this.ParameterOption('4K', this.selectedResolution === '4K', this.isResAllowed('4K', this.segment.orig_resolution), (): void => { this.selectedResolution = '4K'; })
                  }
                  .width('100%')
                }

                // C. 灰色提示文字
                Text('提示：精度越高/视频越长，预处理时间将会越长')
                  .fontSize(11)
                  .fontColor($r('app.color.app_text_muted'))
                  .width('100%')

                // D. 开始/重新预处理按钮
                if (!this.showSelectionActions) {
                  Button(this.segment.status === 'failed' ? '重新预处理' : '开始预处理')
                    .fontSize(13)
                    .backgroundColor($r('app.color.app_surface_inverted'))
                    .fontColor($r('app.color.app_text_on_inverted'))
                    .width('100%')
                    .height(36)
                    .borderRadius(8)
                    .onClick((): void => {
                      this.onPreprocess(this.selectedFps, this.selectedResolution);
                    })
                }
              }
              .width('100%')
              .padding(10)
              .backgroundColor($r('app.color.app_card_subtle_bg'))
              .borderRadius(8)
              .border({ width: 1, color: $r('app.color.app_border') })
            }
          }
          .width('100%')

          // 问答选框选择模式的确认/取消按键
          if (this.showSelectionActions) {
            Row({ space: 10 }) {
              Button('确认选择')
                .backgroundColor($r('app.color.app_surface_inverted'))
                .fontColor($r('app.color.app_text_on_inverted'))
                .borderRadius(8)
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .padding({ left: 0, right: 0 })
                .onClick((): void => {
                  this.onConfirmSelection();
                  this.controller.close();
                })

              Button('取消')
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.app_text_primary'))
                .border({ width: 1, color: $r('app.color.app_border') })
                .borderRadius(8)
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .padding({ left: 0, right: 0 })
                .onClick((): void => {
                  this.controller.close();
                })
            }
            .width('100%')
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .width('100%')
    }
    .padding(16)
    .width('95%')
    .constraintSize({ maxHeight: '85%' })
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(12)
  }
}

@Entry
@Component
struct WorkspaceDetail {
  workspaceId: number = 0;
  workspaceName: string = '';

  @State currentSubTab: number = 0; // 0: 片段, 1: 人脸, 2: 问答
  @State segments: Array<WorkspaceVideoSegment> = [];
  @State exampleVideos: Array<ExampleVideoInfo> = [];
  @State showSelectExampleVideo: boolean = false;
  @State activeVideo: ExampleVideoInfo = new ExampleVideoInfo();
  @State activeIndex: number = 0;

  @State faceGroups: Array<WorkspaceFaceGroupInfo> = [];
  @State selectedFaceGroup: WorkspaceFaceGroupInfo = new WorkspaceFaceGroupInfo();
  @State activeFaceGroupRecords: Array<WorkspaceFaceRecordInfo> = [];
  @State previewImageUrl: string = '';

  @State qaRecords: Array<QARecordInfo> = [];
  @State showCreateQA: boolean = false;
  @State questionText: string = '';
  @State aiProgressText: string = '';
  @State pollIntervalId: number = 0;
  private isPollingStatus: boolean = false;

  @State activeTaskId: string = '';
  @State activeTaskQuestion: string = '';
  @State activeTaskAnswer: string = '';
  @State activeTaskStatus: string = '';
  @State activeTaskProgress: Array<Record<string, Object>> = [];
  @State progressGroups: Array<ProgressGroup> = [];
  @State manualCollapsedState: Record<string, boolean> = {};
  scroller: Scroller = new Scroller();

  // Active segment for detail view
  @State selectedSegment: WorkspaceVideoSegment = new WorkspaceVideoSegment();
  @State selectedSegmentIndex: number = 0;
  @State activeTaskVideoPaths: Array<string> = [];
  @State isVideosCollapsed: boolean = false;
  @State @Watch('onJumpSecondsChange') jumpSeconds: number = 0;

  showToast(options: ToastOptions): void {
    try {
      this.getUIContext().getPromptAction().showToast(options);
    } catch (error) {
      console.warn('[UI] Toast display failed:', JSON.stringify(error));
    }
  }

  onJumpSecondsChange(): void {
    // Watcher to force recreate or pass value if needed, but in ArkTS @Prop will handle it
  }

  rangeDialogController: CustomDialogController = new CustomDialogController({
    builder: VideoRangeDialog({
      activeVideo: this.activeVideo,
      confirm: (start: number, end: number, remark: string, enablePreprocess: boolean, sampleFps: number, resolution: string): void => {
        this.submitCreateSegment(this.activeIndex, start, end, remark, enablePreprocess, sampleFps, resolution);
      }
    }),
    autoCancel: true
  })

  monitorRangeDialogController: CustomDialogController = new CustomDialogController({
    builder: MonitorTimeRangeDialog({
      activeVideo: this.activeVideo,
      confirm: (start: string, end: string, remark: string, enablePreprocess: boolean, sampleFps: number, resolution: string): void => {
        this.submitCreateMonitorSegment(start, end, remark, enablePreprocess, sampleFps, resolution);
      }
    }),
    customStyle: true,
    autoCancel: true
  })

  faceDetailDialogController: CustomDialogController = new CustomDialogController({
    builder: FaceDetailDialog({
      group: this.selectedFaceGroup,
      records: this.activeFaceGroupRecords,
      onRecordClick: (rec: WorkspaceFaceRecordInfo): void => {
        this.jumpToFaceRecordVideo(rec);
      },
      onPreviewImage: (url: string): void => {
        this.previewImageUrl = url;
        this.faceImagePreviewDialogController.open();
      }
    }),
    autoCancel: true
  })

  faceImagePreviewDialogController: CustomDialogController = new CustomDialogController({
    builder: FaceImagePreviewDialog({
      imageUrl: this.previewImageUrl
    }),
    autoCancel: true
  })

  detailDialogController: CustomDialogController = new CustomDialogController({
    builder: SegmentDetailDialog({
      segment: this.selectedSegment,
      onUpdate: (remark: string): void => {
        this.submitUpdateSegment(this.selectedSegment.id, remark);
      },
      onDelete: (): void => {
        this.submitDeleteSegment(this.selectedSegment.id);
      },
      onPreprocess: (sampleFps: number, resolution: string): void => {
        this.submitPreprocessSegment(this.selectedSegment.id, sampleFps, resolution);
      },
      onDeleteFeatures: (): void => {
        this.submitDeleteSegmentFeatures(this.selectedSegment.id);
      }
    }),
    autoCancel: true
  })

  qaSegmentPreviewDialogController: CustomDialogController = new CustomDialogController({
    builder: SegmentDetailDialog({
      segment: this.selectedSegment,
      showSelectionActions: true,
      onConfirmSelection: (): void => {
        this.toggleSegmentSelection(this.selectedSegmentIndex, true);
      }
    }),
    autoCancel: true
  })

  timestampPreviewDialogController: CustomDialogController = new CustomDialogController({
    builder: SegmentDetailDialog({
      segment: this.selectedSegment,
      showSelectionActions: false,
      jumpSeconds: this.jumpSeconds
    }),
    autoCancel: true
  })

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
    if (params) {
      this.workspaceId = params['workspaceId'] as number;
      this.workspaceName = params['workspaceName'] as string;
    }
    this.loadSegments();
    this.loadFaceGroups();
    this.loadQARecords();
  }

  async loadFaceGroups(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/faces`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<WorkspaceFaceGroupInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const g = new WorkspaceFaceGroupInfo();
        g.id = item['id'] as number;
        g.workspace_id = item['workspace_id'] as number;
        g.name = (item['name'] as string) || '';
        g.avatar_path = (item['avatar_path'] as string) || '';
        g.avatar_url = (item['avatar_url'] as string) || '';
        g.record_count = (item['record_count'] as number) || 0;
        mapped.push(g);
      }
      this.faceGroups = mapped;
    } else {
      this.faceGroups = [];
    }
  }

  async openFaceGroupDetail(group: WorkspaceFaceGroupInfo): Promise<void> {
    this.selectedFaceGroup = group;
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/faces/${group.id}/records`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<WorkspaceFaceRecordInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const r = new WorkspaceFaceRecordInfo();
        r.id = item['id'] as number;
        r.workspace_id = item['workspace_id'] as number;
        r.group_id = item['group_id'] as number;
        r.segment_id = (item['segment_id'] as number) || 0;
        r.segment_filepath = (item['segment_filepath'] as string) || '';
        r.segment_media_url = (item['segment_media_url'] as string) || '';
        r.crop_path = (item['crop_path'] as string) || '';
        r.crop_url = (item['crop_url'] as string) || '';
        r.video_name = (item['video_name'] as string) || '';
        r.start_time_offset = (item['start_time_offset'] as number) || 0;
        r.end_time_offset = (item['end_time_offset'] as number) || 0;
        r.time_range_str = (item['time_range_str'] as string) || '';
        mapped.push(r);
      }
      this.activeFaceGroupRecords = mapped;
      this.faceDetailDialogController.open();
    } else {
      this.showToast({ message: '获取人脸识别轨迹失败', duration: 1500 });
    }
  }

  jumpToFaceRecordVideo(rec: WorkspaceFaceRecordInfo): void {
    if (!rec.segment_filepath) {
      this.showToast({ message: '对应视频文件已不存在', duration: 2000 });
      return;
    }

    const s = new WorkspaceVideoSegment();
    s.id = rec.segment_id;
    s.video_name = rec.video_name;
    s.filepath = rec.segment_filepath;
    s.media_url = rec.segment_media_url;
    s.start_offset = 0;
    s.end_offset = rec.end_time_offset + 5;
    s.duration = rec.end_time_offset + 5;

    this.selectedSegment = s;
    this.jumpSeconds = rec.start_time_offset;
    this.timestampPreviewDialogController.open();
  }

  aboutToDisappear(): void {
    if (this.pollIntervalId) {
      clearInterval(this.pollIntervalId);
    }
  }

  async loadSegments(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/segments`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<WorkspaceVideoSegment> = [];
      let hasProcessing = false;
      
      const selectedIds = new Set<number>();
      for (let i = 0; i < this.segments.length; i++) {
        if (this.segments[i].isSelected) {
          selectedIds.add(this.segments[i].id);
        }
      }

      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const s = new WorkspaceVideoSegment();
        s.id = item['id'] as number;
        s.workspace_id = item['workspace_id'] as number;
        s.video_name = item['video_name'] as string;
        s.start_offset = item['start_offset'] as number;
        s.end_offset = item['end_offset'] as number;
        s.duration = item['duration'] as number;
        s.remark = (item['remark'] as string) || '';
        s.filepath = item['filepath'] as string;
        s.media_url = (item['media_url'] as string) || '';
        s.thumbnail_url = (item['thumbnail_url'] as string) || '';
        s.created_at = item['created_at'] as string;
        s.status = (item['status'] as string) || 'pending';
        s.progress = (item['progress'] as number) || 0;
        s.error_msg = (item['error_msg'] as string) || '';
        s.sample_fps = (item['sample_fps'] as number) || 1.0;
        s.resolution = (item['resolution'] as string) || '1080P';
        s.orig_resolution = (item['orig_resolution'] as string) || '1080P';
        
        if (selectedIds.has(s.id)) {
          s.isSelected = true;
        }

        if (this.selectedSegment && this.selectedSegment.id === s.id) {
          this.selectedSegment = s;
        }

        if (s.status === 'processing' || s.status === 'pending') {
          hasProcessing = true;
        }
        mapped.push(s);
      }
      this.segments = mapped;
      this.loadFaceGroups();
      
      if (hasProcessing) {
        setTimeout(() => {
          this.loadSegments();
        }, 1500);
      }
    } else {
      this.segments = [];
    }
  }

  async loadExampleVideos(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/video-sources`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<ExampleVideoInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const v = new ExampleVideoInfo();
        v.id = (item['id'] as string) || '';
        v.name = item['name'] as string;
        v.url = item['url'] as string;
        v.media_url = (item['media_url'] as string) || '';
        v.filepath = (item['filepath'] as string) || '';
        v.duration = (item['duration'] as number) || 0;
        v.source_type = (item['source_type'] as string) || 'monitor';
        v.monitor_id = (item['monitor_id'] as number) || 0;
        v.monitor_name = (item['monitor_name'] as string) || '';
        v.has_recordings = (item['has_recordings'] as boolean) || false;
        v.earliest_time = (item['earliest_time'] as string) || '';
        v.latest_time = (item['latest_time'] as string) || '';
        v.isSelected = false;
        v.startOffset = 0;
        v.endOffset = v.duration;
        mapped.push(v);
      }
      this.exampleVideos = mapped;
    } else {
      this.exampleVideos = [];
    }
  }

  handleExampleVideoClick(index: number): void {
    const video = this.exampleVideos[index];
    this.activeIndex = index;
    this.activeVideo = video;
    
    if (video.source_type === 'monitor') {
      this.monitorRangeDialogController.open();
    } else {
      const path = video.filepath || video.url;
      this.activeVideo.url = BASE_HOST + video.media_url;
      this.activeVideo.filepath = path;
      this.activeVideo.duration = video.duration;
      this.activeVideo.startOffset = 0;
      this.activeVideo.endOffset = video.duration;
      this.rangeDialogController.open();
    }
  }

  async submitCreateMonitorSegment(startTime: string, endTime: string, remark: string, enablePreprocess: boolean = true, sampleFps: number = 1.0, resolution: string = '1080P'): Promise<void> {
    class MonitorSegmentPayload {
      source_type: string = 'monitor';
      monitor_id: number = 0;
      start_time: string = '';
      end_time: string = '';
      remark: string = '';
      enable_preprocess: boolean = true;
      sample_fps: number = 1.0;
      resolution: string = '1080P';
    }
    const payload = new MonitorSegmentPayload();
    payload.source_type = 'monitor';
    payload.monitor_id = this.activeVideo.monitor_id;
    payload.start_time = startTime;
    payload.end_time = endTime;
    payload.remark = remark;
    payload.enable_preprocess = enablePreprocess;
    payload.sample_fps = sampleFps;
    payload.resolution = resolution;

    this.showToast({ message: '正在校验录像完整性并拼接截取...', duration: 2000 });
    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/segments`, payload);
    if (res.code === 0) {
      this.showToast({ message: '监控片段拼接截取成功', duration: 1500 });
      this.showSelectExampleVideo = false;
      this.loadSegments();
    } else {
      this.showToast({ message: res.message || '截取失败，请检查录像完整性', duration: 3500 });
    }
  }

  async submitCreateSegment(index: number, start: number, end: number, remark: string, enablePreprocess: boolean = true, sampleFps: number = 1.0, resolution: string = '1080P'): Promise<void> {
    const video = this.exampleVideos[index];
    
    class SegmentPayload {
      video_name: string = '';
      filepath: string = '';
      start_offset: number = 0;
      end_offset: number = 0;
      remark: string = '';
      enable_preprocess: boolean = true;
      sample_fps: number = 1.0;
      resolution: string = '1080P';
    }
    const payload = new SegmentPayload();
    payload.video_name = video.name;
    payload.filepath = video.filepath || video.url;
    payload.start_offset = start;
    payload.end_offset = end;
    payload.remark = remark;
    payload.enable_preprocess = enablePreprocess;
    payload.sample_fps = sampleFps;
    payload.resolution = resolution;

    this.showToast({ message: '正在物理裁剪并保存片段...', duration: 1500 });
    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/segments`, payload);
    if (res.code === 0) {
      this.showToast({ message: '片段添加成功', duration: 1500 });
      this.showSelectExampleVideo = false;
      this.loadSegments();
    } else {
      this.showToast({ message: '保存失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  showSegmentDetail(seg: WorkspaceVideoSegment): void {
    this.selectedSegment = seg;
    this.detailDialogController.open();
  }

  showQASegmentPreview(seg: WorkspaceVideoSegment, index: number): void {
    this.selectedSegment = seg;
    this.selectedSegmentIndex = index;
    this.qaSegmentPreviewDialogController.open();
  }

  findSegmentByFilepath(filepath: string): WorkspaceVideoSegment | null {
    for (let i = 0; i < this.segments.length; i++) {
      if (this.segments[i].filepath === filepath) {
        return this.segments[i];
      }
    }
    return null;
  }

  handleTimestampClick(videoNumber: number, timeStr: string): void {
    if (!this.activeTaskVideoPaths || this.activeTaskVideoPaths.length < videoNumber) {
      this.showToast({ message: '找不到对应的视频文件', duration: 1500 });
      return;
    }
    const filepath = this.activeTaskVideoPaths[videoNumber - 1];
    const realSeg = this.findSegmentByFilepath(filepath);
    if (realSeg === null) {
      this.showToast({ message: '该视频片段已删除，无法跳转播放', duration: 1500 });
      return;
    }
    
    this.selectedSegment = realSeg;
    this.selectedSegmentIndex = videoNumber - 1;
    this.jumpSeconds = timeToSeconds(timeStr);
    
    this.timestampPreviewDialogController.open();
    this.showToast({ message: `已跳转到视频 ${videoNumber} 的 ${timeStr}`, duration: 1500 });
  }

  async submitUpdateSegment(segmentId: number, remark: string): Promise<void> {
    class UpdatePayload {
      remark: string = '';
    }
    const payload = new UpdatePayload();
    payload.remark = remark;

    const res = await HttpUtil.put(`/workspaces/segments/${segmentId}`, payload);
    if (res.code === 0) {
      this.showToast({ message: '备注修改成功', duration: 1500 });
      this.loadSegments();
    } else {
      this.showToast({ message: '修改失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  async submitDeleteSegment(segmentId: number): Promise<void> {
    const res = await HttpUtil.del(`/workspaces/segments/${segmentId}`);
    if (res.code === 0) {
      this.showToast({ message: '片段删除成功', duration: 1500 });
      this.loadSegments();
    } else {
      this.showToast({ message: '删除失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  async submitPreprocessSegment(segmentId: number, sampleFps: number, resolution: string): Promise<void> {
    class PreprocessPayload {
      sample_fps: number = 1.0;
      resolution: string = '1080P';
    }
    const payload = new PreprocessPayload();
    payload.sample_fps = sampleFps;
    payload.resolution = resolution;

    const res = await HttpUtil.post(`/workspaces/segments/${segmentId}/preprocess`, payload);
    if (res.code === 0) {
      this.showToast({ message: '已开始预处理', duration: 1500 });
      this.loadSegments();
    } else {
      this.showToast({ message: '启动预处理失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  async submitDeleteSegmentFeatures(segmentId: number): Promise<void> {
    const res = await HttpUtil.del(`/workspaces/segments/${segmentId}/features`);
    if (res.code === 0) {
      this.showToast({ message: '预处理特征已删除', duration: 1500 });
      this.loadSegments();
    } else {
      this.showToast({ message: '删除特征失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  async loadQARecords(): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/qa`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const mapped: Array<QARecordInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const r = new QARecordInfo();
        r.id = item['id'] as string;
        r.question = item['question'] as string;
        r.answer = (item['answer'] as string) || '';
        r.status = item['status'] as string;
        r.created_at = item['created_at'] as string;
        mapped.push(r);
      }
      this.qaRecords = mapped;
    } else {
      this.qaRecords = [];
    }
  }

  // ===== 确认并删除问答记录 =====
  confirmDeleteQARecord(taskId: string): void {
    this.getUIContext().showAlertDialog({
      title: '确认删除问答记录',
      message: '删除后该问答记录及其关联的推理结果将无法恢复，是否确认删除？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: Color.Red,
        action: (): void => {
          this.executeDeleteQARecord(taskId);
        }
      }
    });
  }

  async executeDeleteQARecord(taskId: string): Promise<void> {
    try {
      const res = await HttpUtil.del('/workspaces/qa/' + taskId);
      if (res.code === 0 || res.code === 200) {
        this.showToast({ message: '问答记录已成功删除' });
        if (this.pollIntervalId) {
          clearInterval(this.pollIntervalId);
          this.pollIntervalId = 0;
        }
        this.activeTaskId = '';
        this.activeTaskQuestion = '';
        this.activeTaskAnswer = '';
        this.activeTaskStatus = '';
        this.activeTaskProgress = [];
        this.progressGroups = [];
        this.loadQARecords();
      } else {
        this.showToast({ message: res.message || '删除失败' });
      }
    } catch (err) {
      this.showToast({ message: '删除网络请求异常: ' + String(err) });
    }
  }

  async fetchSingleStatus(taskId: string): Promise<void> {
    const res = await HttpUtil.get(`/workspaces/qa/${taskId}/status`);
    if (res.code === 0 && res.data) {
      const statusObj = JSON.parse(res.data) as Record<string, Object>;
      const progressList = statusObj['progress'] as Array<Record<string, Object>>;
      const videoPaths = (statusObj['video_paths'] as Array<string>) || [];
      this.activeTaskVideoPaths = videoPaths;
      this.updateProgress(progressList);
    }
  }

  updateProgress(progressList: Array<Record<string, Object>>): void {
    this.activeTaskProgress = progressList || [];
    this.progressGroups = this.parseProgressToGroups(this.activeTaskProgress);
    // Smoothly scroll to bottom
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  getFriendlyVideoName(videoKey: string): string {
    if (!videoKey) {
      return '当前视频';
    }
    const filename = videoKey.split('/').pop() || videoKey;
    for (let i = 0; i < this.segments.length; i++) {
      const seg = this.segments[i];
      if (seg.filepath.indexOf(filename) !== -1) {
        return seg.remark ? `${seg.remark} (监控: ${seg.video_name})` : `片段-${seg.id} (${seg.video_name})`;
      }
    }
    return filename;
  }

  parseProgressToGroups(progressList: Array<Record<string, Object>>): Array<ProgressGroup> {
    const groups: Array<ProgressGroup> = [];
    
    for (let i = 0; i < progressList.length; i++) {
      const item = progressList[i];
      const stage = (item['stage'] as string) || '';
      const status = (item['status'] as string) || '';
      const msg = (item['message'] as string) || '';
      const data = (item['data'] as Record<string, Object>) || {};

      // 1. MVA V2 reasoning (ReAct Loop) 拆解
      if (stage === 'reasoning') {
        const iter = (data['iteration'] as number) || 1;
        const phase = (data['phase'] as string) || 'thinking';
        const id = 'reasoning_iter_' + iter;
        
        let g = groups.find(x => x.id === id);
        if (!g) {
          g = new ProgressGroup();
          g.id = id;
          g.title = '正在决策';
          g.badgeText = `第 ${iter} 轮`;
          groups.push(g);
        }
        g.badgeText = `第 ${iter} 轮`;

        if (phase === 'thinking') {
          g.title = '正在决策';
          g.isCompleted = false;
          g.isFailed = false;
          const thought = (data['thought'] as string) || '';
          g.details = [`思考过程: ${thought || '大模型正在审视当前已有的证据与问题，思考下一步行动...'}`];
        } 
        else if (phase === 'action') {
          const toolName = (data['tool_name'] as string) || '';
          const toolParams = (data['tool_params'] as Record<string, Object>) || {};
          const thought = (data['thought'] as string) || '正在搜寻线索';
          
          let friendlyTool = '调用工具';
          if (toolName === 'spatiotemporal_search') {
            friendlyTool = '检索时空特征';
          } else if (toolName === 'read_frame_image') {
            friendlyTool = '提取并阅读监控画面';
          } else if (toolName === 'get_video_metadata') {
            friendlyTool = '查询视频元数据';
          }
          
          g.title = friendlyTool;
          g.isCompleted = true;
          g.isFailed = false;
          
          const details: Array<string> = [];
          details.push(`思考过程: ${thought}`);
          
          if (toolName === 'spatiotemporal_search') {
            const qType = (toolParams['query_type'] as string) || 'semantic';
            const qText = (toolParams['query_text'] as string) || '';
            const vId = (toolParams['video_id'] as string) || '';
            details.push(`检索类型: ${qType === 'semantic' ? '场景动作语义分析' : '特定人物目标追踪'}`);
            details.push(`搜索目标: ${qText}`);
            details.push(`选中视频: ${this.getFriendlyVideoName(vId)}`);
          } 
          else if (toolName === 'read_frame_image') {
            const vPath = (toolParams['video_path'] as string) || '';
            const tSec = (toolParams['timestamp_sec'] as number) || 0.0;
            details.push(`查看画面时间点: ${tSec.toFixed(2)} 秒`);
            details.push(`选中视频: ${this.getFriendlyVideoName(vPath)}`);
          } 
          else if (toolName === 'get_video_metadata') {
            const vPath = (toolParams['video_path'] as string) || '';
            details.push(`查询视频路径: ${this.getFriendlyVideoName(vPath)}`);
          }
          
          g.details = details;
        }
        else if (phase === 'completed') {
          const thought = (data['thought'] as string) || '锁定了完整的事件证据链';
          g.title = '推理结论达成';
          g.isCompleted = true;
          g.isFailed = false;
          g.details = [`思考总结: ${thought}`];
        }
      }
      // 2. 最终答复阶段
      else if (stage === 'answering') {
        let g = groups.find(x => x.id === 'answering');
        if (!g) {
          g = new ProgressGroup();
          g.id = 'answering';
          g.title = '生成最终回答';
          groups.push(g);
        }
        g.isCompleted = (status === 'completed');
        g.details = [];
      }
      // 3. 系统错误阶段
      else if (stage === 'system') {
        const id = 'sys_error';
        let g = groups.find(x => x.id === id);
        if (!g) {
          g = new ProgressGroup();
          g.id = id;
          g.title = '系统执行错误';
          groups.push(g);
        }
        g.isFailed = true;
        g.details = [msg];
      }
    }

    const isFinished = (this.activeTaskStatus === 'completed' || this.activeTaskStatus === 'failed');
    
    for (let i = 0; i < groups.length; i++) {
      const g = groups[i];
      if (this.manualCollapsedState[g.id] !== undefined) {
        g.isCollapsed = this.manualCollapsedState[g.id];
      } else {
        if (isFinished) {
          g.isCollapsed = true;
        } else {
          g.isCollapsed = (g.isCompleted && i < groups.length - 1);
        }
      }
    }

    return groups;
  }

  startPollingStatus(taskId: string): void {
    this.aiProgressText = '正在连接 AI 推理引擎...';
    if (this.pollIntervalId) {
      clearInterval(this.pollIntervalId);
    }
    this.pollIntervalId = setInterval(async (): Promise<void> => {
      if (this.isPollingStatus) {
        return;
      }
      this.isPollingStatus = true;
      try {
        const res = await HttpUtil.get(`/workspaces/qa/${taskId}/status`);
        if (res.code === 0 && res.data) {
          const statusObj = JSON.parse(res.data) as Record<string, Object>;
          const status = statusObj['status'] as string;
          const answer = (statusObj['answer'] as string) || '';
          const error = (statusObj['error'] as string) || '';
          const progressList = statusObj['progress'] as Array<Record<string, Object>>;
          const videoPaths = (statusObj['video_paths'] as Array<string>) || [];

          this.activeTaskStatus = status;
          this.activeTaskAnswer = answer ? answer : (error ? '错误: ' + error : '');
          this.activeTaskVideoPaths = videoPaths;
          this.updateProgress(progressList);

          if (progressList && progressList.length > 0) {
            const latestItem = progressList[progressList.length - 1];
            this.aiProgressText = latestItem['message'] as string;
          }
          if (status === 'completed') {
            clearInterval(this.pollIntervalId);
            this.pollIntervalId = 0;
            this.aiProgressText = '分析完成：' + answer;
            this.questionText = '';
            this.showToast({ message: 'AI 分析已完成', duration: 2000 });
            this.loadQARecords();
          } else if (status === 'failed') {
            clearInterval(this.pollIntervalId);
            this.pollIntervalId = 0;
            this.aiProgressText = '分析失败：' + error;
            this.showToast({ message: 'AI 分析发生错误', duration: 2000 });
            this.loadQARecords();
          }
        } else {
          clearInterval(this.pollIntervalId);
          this.pollIntervalId = 0;
          this.aiProgressText = '获取分析进度失败: ' + (res.message || '网络连接异常');
        }
      } finally {
        this.isPollingStatus = false;
      }
    }, 1000);
  }

  async submitQA(): Promise<void> {
    if (!this.questionText) {
      this.showToast({ message: '请输入问题', duration: 1500 });
      return;
    }
    
    const selectedList = this.segments.filter(v => v.isSelected);
    if (selectedList.length === 0) {
      this.showToast({ message: '请至少选择一个视频片段', duration: 1500 });
      return;
    }
    
    this.aiProgressText = '正在提交任务...';

    class SubmitPayload {
      question: string = '';
      segment_ids: Array<number> = [];
    }

    const payload = new SubmitPayload();
    payload.question = this.questionText;
    
    for (let i = 0; i < selectedList.length; i++) {
      payload.segment_ids.push(selectedList[i].id);
    }

    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/qa`, payload);

    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      const taskId = dataObj['task_id'] as string;
      
      // Direct transition to analysis process timeline view
      this.activeTaskId = taskId;
      this.activeTaskQuestion = this.questionText;
      this.activeTaskAnswer = '';
      this.activeTaskStatus = 'processing';
      this.activeTaskProgress = [];
      this.progressGroups = [];
      this.showCreateQA = false;
      this.questionText = '';
      
      const paths: Array<string> = [];
      for (let i = 0; i < selectedList.length; i++) {
        paths.push(selectedList[i].filepath);
      }
      this.activeTaskVideoPaths = paths;
      this.isVideosCollapsed = false;
      
      this.loadQARecords();
      this.startPollingStatus(taskId);
    } else {
      this.aiProgressText = '提交失败: ' + (res.message || '未知异常');
    }
  }

  toggleSegmentSelection(index: number, forceSelect?: boolean): void {
    const s = this.segments[index];
    if (forceSelect !== undefined) {
      s.isSelected = forceSelect;
    } else {
      s.isSelected = !s.isSelected;
    }
    this.segments = [...this.segments];
  }

  @Builder WorkspaceSubTabIcon(index: number, isSelected: boolean) {
    if (index === 0) {
      Image($r('app.media.business_clip_trim'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .opacity(isSelected ? 1 : 0.52)
    } else if (index === 1) {
      Image($r('app.media.business_face_library'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .opacity(isSelected ? 1 : 0.52)
    } else {
      Image($r('app.media.business_ai_qa'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .opacity(isSelected ? 1 : 0.52)
    }
  }

  @Builder WorkspaceSubTabItem(index: number, label: string) {
    Column({ space: 2 }) {
      Row()
        .width(38)
        .height(3)
        .backgroundColor(this.currentSubTab === index ? $r('app.color.app_accent') : Color.Transparent)

      Stack() {
        this.WorkspaceSubTabIcon(index, this.currentSubTab === index)
      }
      .width(46)
      .height(32)

      Text(label)
        .fontSize(11)
        .fontWeight(this.currentSubTab === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentSubTab === index ? $r('app.color.app_nav_text_selected') : $r('app.color.app_nav_text'))
    }
    .height(60)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      this.currentSubTab = index;
      this.showCreateQA = false;
      this.showSelectExampleVideo = false;
      if (index === 0) {
        this.loadSegments();
      } else if (index === 1) {
        this.loadFaceGroups();
      } else {
        this.loadQARecords();
      }
    })
  }

  @Builder WorkspaceHeaderButton(name: string, action: () => void) {
    Button() {
      if (name === 'back') {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([$r('app.color.app_text_primary')])
      } else {
        SymbolGlyph($r('sys.symbol.house'))
          .fontSize(18)
          .fontColor([$r('app.color.app_text_primary')])
      }
    }
    .width(36)
    .height(36)
    .padding(0)
    .backgroundColor($r('app.color.app_card_subtle_bg'))
    .border({ width: 1, color: $r('app.color.app_border') })
    .borderRadius(8)
    .onClick(action)
  }

  build() {
    Column() {
      // ===== Top Bar =====
      Row() {
        if (this.activeTaskId !== '') {
          Row({ space: 8 }) {
            this.WorkspaceHeaderButton('back', (): void => {
              if (this.pollIntervalId) {
                clearInterval(this.pollIntervalId);
                this.pollIntervalId = 0;
              }
              this.activeTaskId = '';
              this.aiProgressText = '';
              this.questionText = '';
              this.loadQARecords();
            })

            this.WorkspaceHeaderButton('home', (): void => {
              if (this.pollIntervalId) {
                clearInterval(this.pollIntervalId);
                this.pollIntervalId = 0;
              }
              this.getUIContext().getRouter().back();
            })
          }
          .margin({ right: 12 })
        } else {
          this.WorkspaceHeaderButton('home', (): void => {
            if (this.pollIntervalId) {
              clearInterval(this.pollIntervalId);
              this.pollIntervalId = 0;
            }
            this.getUIContext().getRouter().back();
          })
        }

        // Title: "问答详情" or workspaceName
        Text(this.activeTaskId !== '' ? '问答详情' : this.workspaceName)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .layoutWeight(1)

        if (this.activeTaskId !== '') {
          Row({ space: 8 }) {
            // Status Badge on the right
            Text(this.activeTaskStatus === 'completed' ? '已完成' : (this.activeTaskStatus === 'failed' ? '失败' : '分析中'))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.activeTaskStatus === 'completed' ? '#10B981' : (this.activeTaskStatus === 'failed' ? '#EF4444' : '#3B82F6'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .border({
                width: 1,
                color: this.activeTaskStatus === 'completed' ? '#10B981' : (this.activeTaskStatus === 'failed' ? '#EF4444' : '#3B82F6')
              })
              .borderRadius(5)

            // 🗑️ 删除图标按钮
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(16)
                .fontColor([Color.Red])
            }
            .width(30)
            .height(30)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.app_danger') })
            .borderRadius(7)
            .onClick((): void => {
              this.confirmDeleteQARecord(this.activeTaskId);
            })
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: $r('app.color.app_border') })

      if (this.activeTaskId !== '') {
        // ===== Q&A Analysis Process / Detail View =====
        Column({ space: 15 }) {

          Scroll(this.scroller) {
            Column({ space: 15 }) {
              Column({ space: 8 }) {
                Text('问题')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.app_text_muted'))
                  .alignSelf(ItemAlign.Start)
                
                Text(this.activeTaskQuestion)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.app_text_primary'))
                  .width('100%')
              }
              .width('100%')
              .padding(15)
              .backgroundColor($r('app.color.app_card_bg'))
              .border({ width: 1, color: $r('app.color.app_border') })
              .borderRadius(10)

              // ===== Selected Videos Panel (collapsible) =====
              if (this.activeTaskVideoPaths && this.activeTaskVideoPaths.length > 0) {
                Column() {
                  Row() {
                    Text(`关联视频片段 (${this.activeTaskVideoPaths.length})`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.app_text_secondary'))
                      .layoutWeight(1)
                    Text(this.isVideosCollapsed ? '展开 ▼' : '收起 ▲')
                      .fontSize(12)
                      .fontColor($r('app.color.app_text_muted'))
                  }
                  .width('100%')
                  .padding({ top: 5, bottom: 5 })
                  .onClick((): void => {
                    this.isVideosCollapsed = !this.isVideosCollapsed;
                  })

                  if (!this.isVideosCollapsed) {
                    Column() {
                      ForEach(this.activeTaskVideoPaths, (filepath: string, index: number): void => {
                        Stack({ alignContent: Alignment.TopEnd }) {
                          Row() {
                            if (this.findSegmentByFilepath(filepath) !== null) {
                              Image(BASE_HOST + this.findSegmentByFilepath(filepath)!.thumbnail_url)
                                .width(100)
                                .height(60)
                                .borderRadius(6)
                                .objectFit(ImageFit.Cover)
                                .margin({ right: 12 })

                              Column({ space: 4 }) {
                                Text(this.findSegmentByFilepath(filepath)!.remark ? this.findSegmentByFilepath(filepath)!.remark : '未命名片段')
                                  .fontSize(15)
                                  .fontWeight(FontWeight.Bold)
                                  .fontColor($r('app.color.app_text_primary'))
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                                Text('来自监控：' + this.findSegmentByFilepath(filepath)!.video_name)
                                  .fontSize(12)
                                  .fontColor($r('app.color.app_text_muted'))
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                                Text(`时间段：${this.findSegmentByFilepath(filepath)!.start_offset.toFixed(1)}s - ${this.findSegmentByFilepath(filepath)!.end_offset.toFixed(1)}s`)
                                  .fontSize(12)
                                  .fontColor($r('app.color.app_text_muted'))
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                              }
                              .alignItems(HorizontalAlign.Start)
                              .layoutWeight(1)
                            } else {
                              Column({ space: 5 }) {
                                Text('该片段已删除')
                                  .fontSize(15)
                                  .fontWeight(FontWeight.Bold)
                                  .fontColor('#EF4444')
                              }
                              .alignItems(HorizontalAlign.Start)
                              .layoutWeight(1)
                              .padding({ left: 10, right: 10, top: 15, bottom: 15 })
                            }
                          }
                          .width('100%')
                          .padding(12)
                          .backgroundColor($r('app.color.app_card_bg'))
                          .borderRadius(10)
                          .border({ width: 1, color: $r('app.color.app_border') })
                          .onClick((): void => {
                            const seg = this.findSegmentByFilepath(filepath);
                            if (seg !== null) {
                              this.showSegmentDetail(seg);
                            } else {
                              this.showToast({ message: '该片段已删除，无法查看', duration: 1500 });
                            }
                          })

                          Text(`视频 ${index + 1}`)
                            .fontSize(10)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.app_text_on_inverted'))
                            .backgroundColor($r('app.color.app_surface_inverted'))
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .borderRadius({ bottomLeft: 8, topRight: 8 })
                        }
                        .width('100%')
                        .margin({ bottom: 8 })
                      }, (filepath: string, idx: number): string => idx.toString())
                    }
                    .width('100%')
                    .margin({ top: 10 })
                  }
                }
                .width('100%')
                .padding(10)
                .backgroundColor($r('app.color.app_card_bg'))
                .border({ width: 1, color: $r('app.color.app_border') })
                .borderRadius(10)
              }

              if (this.progressGroups.length > 0) {
                ForEach(this.progressGroups, (group: ProgressGroup, idx: number): void => {
                  Column() {
                    Row() {
                      Blank()
                        .width(10)
                        .height(10)
                        .backgroundColor(group.isFailed ? $r('app.color.app_danger') : (group.isCompleted ? $r('app.color.app_success') : $r('app.color.app_selection')))
                        .borderRadius(5)
                        .margin({ right: 10 })

                      Row() {
                        Text(group.title)
                          .fontSize(14)
                          .fontWeight(FontWeight.Bold)
                          .fontColor($r('app.color.app_text_primary'))

                        if (group.badgeText) {
                          Text(group.badgeText)
                            .fontSize(10)
                            .fontColor($r('app.color.app_selection'))
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .border({ width: 1, color: $r('app.color.app_selection') })
                            .borderRadius(4)
                            .margin({ left: 6 })
                        }
                      }
                      .layoutWeight(1)

                      if (group.isFailed) {
                        Text('失败')
                          .fontSize(12)
                          .fontColor($r('app.color.app_danger'))
                          .margin({ right: 10 })
                      } else if (group.isCompleted) {
                        Text('已完成')
                          .fontSize(12)
                          .fontColor($r('app.color.app_success'))
                          .margin({ right: 10 })
                      } else {
                        Text('运行中')
                          .fontSize(12)
                          .fontColor($r('app.color.app_selection'))
                          .margin({ right: 10 })
                      }

                      if (group.id !== 'answering') {
                        Text(group.isCollapsed ? '▼' : '▲')
                          .fontSize(12)
                          .fontColor($r('app.color.app_text_muted'))
                      }
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12, left: 15, right: 15 })
                    .backgroundColor($r('app.color.app_card_subtle_bg'))
                    .borderRadius(8)
                    .onClick((): void => {
                      if (group.id !== 'answering') {
                        const newState = !group.isCollapsed;
                        this.manualCollapsedState[group.id] = newState;
                        this.progressGroups = this.parseProgressToGroups(this.activeTaskProgress);
                      }
                    })

                    if (!group.isCollapsed && group.id !== 'answering') {
                      Column({ space: 8 }) {
                        ForEach(group.details, (detail: string): void => {
                          Row() {
                            Text('•')
                              .fontSize(14)
                              .fontColor($r('app.color.app_text_secondary'))
                              .margin({ right: 8 })
                            Text(detail)
                              .fontSize(13)
                              .fontColor($r('app.color.app_text_secondary'))
                              .lineHeight(18)
                              .layoutWeight(1)
                          }
                          .width('100%')
                          .alignItems(VerticalAlign.Top)
                        })
                      }
                      .width('100%')
                      .padding({ left: 30, right: 15, top: 10, bottom: 10 })
                      .backgroundColor($r('app.color.app_card_bg'))
                      .borderWidth({ left: 2, right: 0, top: 0, bottom: 0 })
                      .borderColor($r('app.color.app_border'))
                    }
                  }
                  .width('100%')
                  .borderRadius(8)
                  .clip(true)
                  .border({ width: 1, color: $r('app.color.app_border') })
                })
              } else {
                Text('等待分析任务启动...')
                  .fontSize(13)
                  .fontColor($r('app.color.app_text_muted'))
                  .padding(15)
              }

              if (this.activeTaskAnswer || this.activeTaskStatus === 'completed' || this.activeTaskStatus === 'failed') {
                Column({ space: 8 }) {
                  Text('AI 回答')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_muted'))
                    .alignSelf(ItemAlign.Start)

                  if (this.activeTaskAnswer) {
                    Column({ space: 6 }) {
                      ForEach(parseAnswerToChunks(this.activeTaskAnswer), (paraChunks: Array<TextChunk>): void => {
                        Text() {
                          ForEach(paraChunks, (chunk: TextChunk): void => {
                            Span(chunk.content)
                              .fontWeight(chunk.isBold ? FontWeight.Bold : FontWeight.Normal)
                              .fontColor(chunk.isTimestamp ? $r('app.color.app_selection') : (this.activeTaskStatus === 'failed' ? $r('app.color.app_danger') : $r('app.color.app_text_primary')))
                              .decoration(chunk.isTimestamp ? { type: TextDecorationType.Underline, color: $r('app.color.app_selection') } : { type: TextDecorationType.None })
                              .onClick((): void => {
                                if (chunk.isTimestamp) {
                                  this.handleTimestampClick(chunk.videoNum, chunk.timeStr);
                                }
                              })
                          }, (chunk: TextChunk, idx: number): string => idx.toString())
                        }
                        .width('100%')
                        .fontSize(14)
                        .lineHeight(20)
                        .padding({ left: (paraChunks.length > 0 && paraChunks[0].content.startsWith('•  ')) ? 16 : 0 })
                      }, (paraChunks: Array<TextChunk>, idx: number): string => idx.toString())
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                  } else {
                    Text('思考中...')
                      .fontSize(14)
                      .fontColor($r('app.color.app_text_muted'))
                      .width('100%')
                      .lineHeight(20)
                  }
                }
                .width('100%')
                .padding(15)
                .backgroundColor($r('app.color.app_card_bg'))
                .border({ width: 1, color: $r('app.color.app_border') })
                .borderRadius(10)
              }
            }
            .width('100%')
          }
          .width('90%')
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)

      } else {
        // ===== Workspace Internal Tab View =====
        Column() {
          if (this.currentSubTab === 0) {
            // ================== "片段" Tab Content ==================
            if (this.showSelectExampleVideo) {
              // Video Selection grid for adding fragment
              Column({ space: 10 }) {
                Row({ space: 8 }) {
                  Text('选择视频源（监控录像 / 上传视频）')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                    .layoutWeight(1)

                  Button('刷新')
                    .fontSize(12)
                    .height(32)
                    .backgroundColor(Color.Transparent)
                    .fontColor($r('app.color.app_text_primary'))
                    .border({ width: 1, color: $r('app.color.app_border') })
                    .borderRadius(7)
                    .onClick((): void => {
                      this.loadExampleVideos();
                    })
                  
                  Button('返回')
                    .fontSize(12)
                    .height(32)
                    .backgroundColor(Color.Transparent)
                    .fontColor($r('app.color.app_text_secondary'))
                    .border({ width: 1, color: $r('app.color.app_border') })
                    .borderRadius(7)
                    .onClick((): void => {
                      this.showSelectExampleVideo = false;
                    })
                }
                .width('100%')
                .padding({ bottom: 10 })
                .alignItems(VerticalAlign.Center)

                if (this.exampleVideos.length > 0) {
                  Grid() {
                    ForEach(this.exampleVideos, (video: ExampleVideoInfo, index: number): void => {
                      GridItem() {
                        VideoItemCard({
                          name: video.name,
                          duration: video.duration,
                          sourceType: video.source_type,
                          earliestTime: video.earliest_time,
                          latestTime: video.latest_time,
                          onCardClick: (): void => {
                            this.handleExampleVideoClick(index);
                          }
                        })
                      }
                    })
                  }
                  .columnsTemplate('1fr 1fr')
                  .columnsGap(10)
                  .rowsGap(10)
                  .width('100%')
                  .layoutWeight(1)
                } else {
                  Column() {
                    Text('暂未搜索到同小组监控录像或已上传视频')
                      .fontSize(14)
                      .fontColor($r('app.color.app_text_muted'))
                      .margin({ bottom: 10 })
                    Button('重新刷新')
                      .width(100)
                      .height(35)
                      .fontSize(13)
                      .backgroundColor($r('app.color.app_surface_inverted'))
                      .fontColor($r('app.color.app_text_on_inverted'))
                      .borderRadius(8)
                      .onClick((): void => {
                        this.loadExampleVideos();
                      })
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                }
              }
              .padding(15)
              .width('100%')
              .layoutWeight(1)

            } else {
              // Saved Video Segments list
              Column() {
                if (this.segments.length === 0) {
                  Column() {
                    Text('暂无视频片段，请点击下方加号添加')
                      .fontSize(16)
                      .fontColor($r('app.color.app_text_muted'))
                      .margin({ top: 80 })
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Start)
                } else {
                  List({ space: 12 }) {
                    ForEach(this.segments, (seg: WorkspaceVideoSegment): void => {
                      ListItem() {
                        Row() {
                          Image(BASE_HOST + seg.thumbnail_url)
                            .width(100)
                            .height(60)
                            .borderRadius(6)
                            .objectFit(ImageFit.Cover)
                            .margin({ right: 12 })

                          Column({ space: 4 }) {
                            Text(seg.remark ? seg.remark : '未命名片段')
                              .fontSize(15)
                              .fontWeight(FontWeight.Bold)
                              .fontColor($r('app.color.app_text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            Text('来自监控：' + seg.video_name)
                              .fontSize(12)
                              .fontColor('#9CA3AF')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            if (seg.status === 'processing' || seg.status === 'pending') {
                              Row() {
                                Progress({ value: seg.progress, total: 100, type: ProgressType.Linear })
                                  .width('60%')
                                  .height(6)
                                  .color($r('app.color.app_primary'))
                                  .margin({ right: 8 })
                                Text(`预分析中 ${seg.progress}%`)
                                  .fontSize(10)
                                  .fontColor($r('app.color.app_primary'))
                              }
                              .width('100%')
                              .alignItems(VerticalAlign.Center)
                            } else if (seg.status === 'failed') {
                              Text('预分析失败: ' + seg.error_msg)
                                .fontSize(11)
                                .fontColor(Color.Red)
                                .maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                            } else {
                              Text(`时间段：${seg.start_offset.toFixed(1)}s - ${seg.end_offset.toFixed(1)}s`)
                                .fontSize(12)
                                .fontColor('#9CA3AF')
                                .maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                            }
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)
                        }
                        .width('100%')
                        .padding(15)
                        .backgroundColor($r('app.color.app_card_bg'))
                        .borderRadius(10)
                        .border({ width: 1, color: $r('app.color.app_border') })
                        .onClick((): void => {
                          this.showSegmentDetail(seg);
                        })
                      }
                    })
                  }
                  .width('90%')
                  .layoutWeight(1)
                }

                Button() {
                  Row({ space: 7 }) {
                    Blank()
                      .width(3)
                      .height(18)
                      .backgroundColor($r('app.color.app_accent'))
                    SymbolGlyph($r('sys.symbol.plus'))
                      .fontSize(15)
                      .fontColor([$r('app.color.app_text_on_inverted')])
                    Text('截取新片段')
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.app_text_on_inverted'))
                  }
                }
                  .width(132)
                  .height(40)
                  .backgroundColor($r('app.color.app_surface_inverted'))
                  .borderRadius(8)
                  .alignSelf(ItemAlign.End)
                  .margin({ right: 18, top: 15, bottom: 20 })
                  .onClick((): void => {
                    this.loadExampleVideos();
                    this.showSelectExampleVideo = true;
                  })
              }
              .width('100%')
              .layoutWeight(1)
            }

          } else if (this.currentSubTab === 1) {
            // ================== "人脸" Tab Content ==================
            Column({ space: 12 }) {
              Row() {
                Text('工作区人脸识别与检索')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.app_text_primary'))
                  .layoutWeight(1)

                Button('刷新')
                  .fontSize(12)
                  .height(32)
                  .backgroundColor(Color.Transparent)
                  .fontColor($r('app.color.app_text_primary'))
                  .border({ width: 1, color: $r('app.color.app_border') })
                  .borderRadius(7)
                  .onClick((): void => {
                    this.loadFaceGroups();
                  })
              }
              .width('90%')
              .padding({ top: 10, bottom: 4 })

              if (this.faceGroups.length > 0) {
                Grid() {
                  ForEach(this.faceGroups, (group: WorkspaceFaceGroupInfo): void => {
                    GridItem() {
                      FaceGroupCard({
                        group: group,
                        onCardClick: (): void => {
                          this.openFaceGroupDetail(group);
                        }
                      })
                    }
                  })
                }
                .columnsTemplate('1fr 1fr')
                .columnsGap(12)
                .rowsGap(12)
                .width('90%')
                .layoutWeight(1)
              } else {
                Column({ space: 12 }) {
                  Image($r('app.media.business_person_tracking'))
                    .width(72)
                    .height(72)
                    .objectFit(ImageFit.Contain)
                    .opacity(0.72)
                  Text('暂未识别到人脸卡片')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_secondary'))
                  Text('截取视频片段时开启“AI 特征提取与识别预处理”，系统将自动识别画面人脸，并将同一人脸在不同时间段的轨迹自动归类聚合。')
                    .fontSize(12)
                    .fontColor($r('app.color.app_text_muted'))
                    .textAlign(TextAlign.Center)
                    .padding({ left: 30, right: 30 })
                }
                .width('100%')
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .layoutWeight(1)

          } else {
            // ================== "问答" Tab Content ==================
            if (this.showCreateQA) {
              // Create Q&A Form choosing segments
              Column({ space: 10 }) {
                Text('新建问答 - 选择包含的视频片段')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.app_text_primary'))
                  .alignSelf(ItemAlign.Start)

                if (this.segments.length > 0) {
                  List({ space: 10 }) {
                    ForEach(this.segments, (seg: WorkspaceVideoSegment, index: number): void => {
                       ListItem() {
                        Row() {
                          Image(BASE_HOST + seg.thumbnail_url)
                            .width(100)
                            .height(60)
                            .borderRadius(6)
                            .objectFit(ImageFit.Cover)
                            .margin({ right: 12 })

                          Column({ space: 4 }) {
                            Text(seg.remark ? seg.remark : '未命名片段')
                              .fontSize(15)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(seg.isSelected ? $r('app.color.app_selection') : $r('app.color.app_text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            Text('来自监控：' + seg.video_name)
                              .fontSize(12)
                              .fontColor($r('app.color.app_text_muted'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            if (seg.status === 'processing' || seg.status === 'pending') {
                              Text(`预分析中 (${seg.progress}%)`)
                                .fontSize(11)
                                .fontColor($r('app.color.app_primary'))
                            } else if (seg.status === 'failed') {
                              Text('预分析失败')
                                .fontSize(11)
                                .fontColor(Color.Red)
                            } else {
                              Text(`时间段：${seg.start_offset.toFixed(1)}s - ${seg.end_offset.toFixed(1)}s`)
                                .fontSize(12)
                                .fontColor($r('app.color.app_text_muted'))
                                .maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                            }
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)
                        }
                        .width('100%')
                        .padding(10)
                        .backgroundColor(seg.isSelected ? $r('app.color.app_primary_soft') : $r('app.color.app_card_bg'))
                        .borderRadius(8)
                        .opacity(1.0)
                        .border({
                          width: { left: seg.isSelected ? 3 : 1, right: 1, top: 1, bottom: 1 },
                          color: seg.isSelected ? $r('app.color.app_selection') : $r('app.color.app_border')
                        })
                        .onClick((): void => {
                          if (seg.status === 'processing' || seg.status === 'pending') {
                            this.showToast({ message: '该片段正在后台预处理中，可同步提交问答', duration: 1500 });
                          }
                          if (seg.isSelected) {
                            this.toggleSegmentSelection(index, false);
                          } else {
                            this.showQASegmentPreview(seg, index);
                          }
                        })
                      }
                    })
                  }
                  .width('100%')
                  .layoutWeight(1)
                } else {
                  Column() {
                    Text('本工作区暂无视频片段，请先前往片段页裁剪视频')
                      .fontSize(14)
                      .fontColor($r('app.color.app_text_muted'))
                      .textAlign(TextAlign.Center)
                      .margin({ bottom: 20 })
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                }

                Text('AI 分析提问:')
                  .fontSize(14)
                  .fontColor($r('app.color.app_text_primary'))
                  .alignSelf(ItemAlign.Start)
                TextArea({ placeholder: '请输入要分析提问的具体问题', text: this.questionText })
                  .height(80)
                  .fontColor($r('app.color.app_text_primary'))
                  .backgroundColor($r('app.color.app_input_bg'))
                  .border({ width: 1, color: $r('app.color.app_border') })
                  .borderRadius(8)
                  .onChange((val: string): void => {
                    this.questionText = val;
                  })

                Row({ space: 15 }) {
                  Button('取消')
                    .layoutWeight(1)
                    .height(40)
                    .backgroundColor(Color.Transparent)
                    .fontColor($r('app.color.app_text_secondary'))
                    .border({ width: 1, color: $r('app.color.app_border') })
                    .borderRadius(8)
                    .onClick((): void => {
                      this.showCreateQA = false;
                      this.aiProgressText = '';
                      this.questionText = '';
                    })

                  Button('提交分析')
                    .layoutWeight(1)
                    .height(40)
                    .backgroundColor($r('app.color.app_surface_inverted'))
                    .fontColor($r('app.color.app_text_on_inverted'))
                    .borderRadius(8)
                    .onClick((): void => {
                      this.submitQA();
                    })
                }
                .width('100%')
                .margin({ top: 5 })

                if (this.aiProgressText.length > 0) {
                  Text(this.aiProgressText)
                    .width('100%')
                    .padding(10)
                    .backgroundColor($r('app.color.app_card_subtle_bg'))
                    .border({ width: { left: 3 }, color: $r('app.color.app_success') })
                    .borderRadius(6)
                    .fontColor($r('app.color.app_success'))
                    .fontSize(13)
                }
              }
              .padding(15)
              .width('100%')
              .layoutWeight(1)

            } else {
              // Q&A Records List
              Column() {
                if (this.qaRecords.length === 0) {
                  Column() {
                    Text('暂无问答记录')
                      .fontSize(16)
                      .fontColor($r('app.color.app_text_muted'))
                      .margin({ top: 80 })
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Start)
                } else {
                  List({ space: 12 }) {
                    ForEach(this.qaRecords, (record: QARecordInfo): void => {
                      ListItem() {
                        Row() {
                          Column({ space: 4 }) {
                            Text(record.question)
                              .fontSize(15)
                              .fontWeight(FontWeight.Bold)
                              .fontColor($r('app.color.app_text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            Text('创建时间：' + record.created_at)
                              .fontSize(12)
                              .fontColor('#9CA3AF')

                            if (record.status === 'processing' || record.status === 'pending') {
                              Text('AI 检索分析中...')
                                .fontSize(12)
                                .fontColor($r('app.color.app_primary'))
                            } else if (record.status === 'failed') {
                              Text('分析失败: ' + record.error_msg)
                                .fontSize(12)
                                .fontColor(Color.Red)
                                .maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                            } else {
                              Text('包含片段：' + record.video_count + ' 个')
                                .fontSize(12)
                                .fontColor('#10B981')
                            }
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)

                          Image($r('app.media.business_ai_qa'))
                            .width(28)
                            .height(28)
                            .objectFit(ImageFit.Contain)
                            .opacity(0.78)
                        }
                        .width('100%')
                        .padding(15)
                        .backgroundColor($r('app.color.app_card_bg'))
                        .borderRadius(10)
                        .border({
                          width: { left: 3, right: 1, top: 1, bottom: 1 },
                          color: record.status === 'failed' ? $r('app.color.app_danger') : (record.status === 'completed' ? $r('app.color.app_success') : $r('app.color.app_accent'))
                        })
                        .onClick((): void => {
                          this.activeTaskId = record.id;
                          this.activeTaskQuestion = record.question;
                          this.activeTaskAnswer = record.answer;
                          this.activeTaskStatus = record.status;
                          this.activeTaskVideoPaths = record.video_paths;

                          if (record.status === 'processing' || record.status === 'pending') {
                            this.startPollingStatus(record.id);
                          } else {
                            this.fetchSingleStatus(record.id);
                          }
                        })
                      }
                    })
                  }
                  .width('90%')
                  .layoutWeight(1)
                }

                Button() {
                  Row({ space: 7 }) {
                    Blank()
                      .width(3)
                      .height(18)
                      .backgroundColor($r('app.color.app_accent'))
                    Image($r('app.media.business_ai_qa'))
                      .width(19)
                      .height(19)
                      .objectFit(ImageFit.Contain)
                    Text('新建问答')
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.app_text_on_inverted'))
                  }
                }
                  .width(120)
                  .height(40)
                  .backgroundColor($r('app.color.app_surface_inverted'))
                  .borderRadius(8)
                  .alignSelf(ItemAlign.End)
                  .margin({ right: 18, top: 15, bottom: 20 })
                  .onClick((): void => {
                    for (let i = 0; i < this.segments.length; i++) {
                      this.segments[i].isSelected = false;
                    }
                    this.segments = [...this.segments];
                    this.questionText = '';
                    this.aiProgressText = '';
                    this.activeTaskId = '';
                    this.activeTaskProgress = [];
                    this.progressGroups = [];
                    this.manualCollapsedState = {};
                    this.showCreateQA = true;
                  })
              }
              .width('100%')
              .layoutWeight(1)
            }
          }

          // ===== Workspace Bottom Navigation =====
          Row() {
            this.WorkspaceSubTabItem(0, '片段')
            this.WorkspaceSubTabItem(1, '人脸')
            this.WorkspaceSubTabItem(2, '问答')
          }
          .width('100%')
          .height(68)
          .padding({ top: 4, bottom: 4 })
          .backgroundColor($r('app.color.app_nav_bar_bg'))
          .border({ width: { top: 1 }, color: $r('app.color.app_border') })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
  }
}

@Component
struct VideoItemCard {
  @Prop name: string = '';
  @Prop duration: number = 0;
  @Prop sourceType: string = 'monitor';
  @Prop earliestTime: string = '';
  @Prop latestTime: string = '';
  onCardClick: () => void = (): void => {};

  build() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column()
          .width('100%')
          .height(95)
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .borderRadius({ topLeft: 8, topRight: 8 })

        // 视频源分类徽章
        Text(this.sourceType === 'monitor' ? '监控设备' : (this.sourceType === 'upload' ? '上传视频' : '示例视频'))
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.sourceType === 'monitor' ? $r('app.color.app_selection') : $r('app.color.app_text_secondary'))
          .backgroundColor($r('app.color.app_card_bg'))
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .border({ width: 1, color: $r('app.color.app_border') })
          .borderRadius(4)
          .margin({ left: 6, top: 6 })
          .alignSelf(ItemAlign.Start)

        Image(this.sourceType === 'monitor' ? $r('app.media.business_monitor') : $r('app.media.business_clip_trim'))
          .width(42)
          .height(42)
          .objectFit(ImageFit.Contain)
          .alignSelf(ItemAlign.Center)
          .opacity(0.82)

        if (this.sourceType !== 'monitor') {
          Text(this.formatDuration(this.duration))
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor('rgba(0, 0, 0, 0.65)')
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .borderRadius(3)
            .margin(5)
        } else {
          Text(this.latestTime.length > 5 ? '持续录像中' : '无录像')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor('rgba(30, 64, 175, 0.75)')
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .borderRadius(3)
            .margin(5)
        }
      }
      .width('100%')

      Column({ space: 2 }) {
        Text(this.name)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.sourceType === 'monitor' && this.earliestTime && this.earliestTime.length >= 16 && this.latestTime && this.latestTime.length >= 16) {
          Text(`可用: ${this.earliestTime.slice(11, 16)} - ${this.latestTime.slice(11, 16)}`)
            .fontSize(10)
            .fontColor($r('app.color.app_text_muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .padding(8)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(8)
    .border({ width: 1, color: $r('app.color.app_border') })
    .onClick((): void => {
      this.onCardClick();
    })
  }

  formatDuration(sec: number): string {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }
}

@Component
struct FaceGroupCard {
  @Prop group: WorkspaceFaceGroupInfo = new WorkspaceFaceGroupInfo();
  onCardClick: () => void = (): void => {};

  build() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column()
          .width('100%')
          .height(115)
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .borderRadius({ topLeft: 8, topRight: 8 })

        Image(this.group.avatar_url ? (BASE_HOST + this.group.avatar_url) : $r('app.media.business_face_library'))
          .width('100%')
          .height(115)
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 8, topRight: 8 })

        Text(`${this.group.record_count} 条时间段记录`)
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor('rgba(30, 64, 175, 0.85)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .margin(6)
      }
      .width('100%')

      Column({ space: 2 }) {
        Text(this.group.name)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding(8)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(8)
    .border({ width: 1, color: $r('app.color.app_border') })
    .onClick((): void => {
      this.onCardClick();
    })
  }
}
