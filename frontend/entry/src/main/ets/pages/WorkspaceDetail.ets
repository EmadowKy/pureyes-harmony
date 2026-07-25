import router from '@ohos.router';
import { HttpUtil, BASE_HOST } from '../utils/http'
import promptAction from '@ohos.promptAction'
import { QARecordInfo } from './tabs/WorkspaceTab'

export class WorkspaceVideoSegment {
  id: number = 0;
  workspace_id: number = 0;
  video_name: string = '';
  start_offset: number = 0;
  end_offset: number = 0;
  duration: number = 0;
  remark: string = '';
  filepath: string = '';
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

            Button('最近1分钟')
              .fontSize(11)
              .height(26)
              .backgroundColor('#EFF6FF')
              .fontColor('#1E40AF')
              .onClick((): void => {
                const base = (this.activeVideo.latest_time && this.activeVideo.latest_time.indexOf(':') !== -1) ? this.activeVideo.latest_time : this.formatDateTime(new Date());
                this.endTimeText = base;
                this.startTimeText = this.computeShiftedTime(base, -1);
              })

            Button('最近3分钟')
              .fontSize(11)
              .height(26)
              .backgroundColor('#EFF6FF')
              .fontColor('#1E40AF')
              .onClick((): void => {
                const base = (this.activeVideo.latest_time && this.activeVideo.latest_time.indexOf(':') !== -1) ? this.activeVideo.latest_time : this.formatDateTime(new Date());
                this.endTimeText = base;
                this.startTimeText = this.computeShiftedTime(base, -3);
              })

            Button('最近5分钟')
              .fontSize(11)
              .height(26)
              .backgroundColor('#EFF6FF')
              .fontColor('#1E40AF')
              .onClick((): void => {
                const base = (this.activeVideo.latest_time && this.activeVideo.latest_time.indexOf(':') !== -1) ? this.activeVideo.latest_time : this.formatDateTime(new Date());
                this.endTimeText = base;
                this.startTimeText = this.computeShiftedTime(base, -5);
              })
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
                  Button('0.5 FPS')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedFps === 0.5 ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedFps === 0.5 ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedFps = 0.5; })

                  Button('1.0 FPS (推荐)')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1.2)
                    .backgroundColor(this.selectedFps === 1.0 ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedFps === 1.0 ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedFps = 1.0; })

                  Button('2.0 FPS')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedFps === 2.0 ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedFps === 2.0 ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedFps = 2.0; })
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
                  Button('480P')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedResolution === '480P' ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedResolution === '480P' ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedResolution = '480P'; })

                  Button('720P')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedResolution === '720P' ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedResolution === '720P' ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedResolution = '720P'; })

                  Button('1080P (推荐)')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1.3)
                    .backgroundColor(this.selectedResolution === '1080P' ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedResolution === '1080P' ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedResolution = '1080P'; })

                  Button('4K')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedResolution === '4K' ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedResolution === '4K' ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedResolution = '4K'; })
                }
                .width('100%')
              }
              .width('100%')
              .margin({ top: 2 })
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#EFF6FF')
          .borderRadius(10)
          .border({ width: 1, color: '#DBEAFE' })

          Column({ space: 4 }) {
            Text('片段备注/说明 (可选):')
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
              .alignSelf(ItemAlign.Start)

            TextInput({ text: this.remarkText, placeholder: '例：西门夜间人员进出记录' })
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
          .backgroundColor('#F3F4F6')
          .fontColor('#374151')
          .onClick((): void => {
            this.controller.close();
          })

        Button('确认拼接截取')
          .fontSize(13)
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
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
          .backgroundColor('rgba(255, 255, 255, 0.25)')
          .width(30)
          .height(30)
          .borderRadius(15)
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
        Image(this.group.avatar_url ? (BASE_HOST + this.group.avatar_url) : $r('app.media.startIcon'))
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
          .backgroundColor('#F3F4F6')
          .fontColor('#374151')
          .onClick((): void => {
            this.controller.close();
          })
      }
      .width('100%')
      .padding({ bottom: 6 })

      Divider().color('#E5E7EB')

      if (this.records.length > 0) {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.records, (rec: WorkspaceFaceRecordInfo): void => {
              Row({ space: 12 }) {
                // 左边：这个人脸在这一段的图片，点击可以查看大图
                Image(rec.crop_url ? (BASE_HOST + rec.crop_url) : $r('app.media.startIcon'))
                  .width(64)
                  .height(64)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .border({ width: 1, color: '#DBEAFE' })
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
                    .fontColor('#1E40AF')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row() {
                    Text('出现时间段: ')
                      .fontSize(12)
                      .fontColor($r('app.color.app_text_secondary'))
                    Text(rec.time_range_str)
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#2563EB')
                  }

                  Text('点击播放视频并精准跳转到起始时间 ➔')
                    .fontSize(10)
                    .fontColor('#6B7280')
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
              .backgroundColor('#F8FAFC')
              .borderRadius(8)
              .border({ width: 1, color: '#E2E8F0' })
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

          TextInput({ placeholder: '请输入片段备注，例如：大门经过车辆', text: this.remarkText })
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
                  Button('0.5 FPS')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedFps === 0.5 ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedFps === 0.5 ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedFps = 0.5; })

                  Button('1.0 FPS (推荐)')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1.2)
                    .backgroundColor(this.selectedFps === 1.0 ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedFps === 1.0 ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedFps = 1.0; })

                  Button('2.0 FPS')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedFps === 2.0 ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedFps === 2.0 ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedFps = 2.0; })
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
                  Button('480P')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedResolution === '480P' ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedResolution === '480P' ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedResolution = '480P'; })

                  Button('720P')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedResolution === '720P' ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedResolution === '720P' ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedResolution = '720P'; })

                  Button('1080P (推荐)')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1.3)
                    .backgroundColor(this.selectedResolution === '1080P' ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedResolution === '1080P' ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedResolution = '1080P'; })

                  Button('4K')
                    .fontSize(11)
                    .height(28)
                    .layoutWeight(1)
                    .backgroundColor(this.selectedResolution === '4K' ? $r('app.color.app_primary') : '#FFFFFF')
                    .fontColor(this.selectedResolution === '4K' ? Color.White : '#1F2937')
                    .onClick((): void => { this.selectedResolution = '4K'; })
                }
                .width('100%')
              }
              .width('100%')
              .margin({ top: 2 })
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#EFF6FF')
          .borderRadius(10)
          .border({ width: 1, color: '#DBEAFE' })

          Row({ space: 20 }) {
            Button('取消')
              .backgroundColor('#999999')
              .fontColor(Color.White)
              .width(100)
              .height(40)
              .onClick((): void => {
                this.controller.close();
              })

            Button('确认')
              .backgroundColor($r('app.color.app_primary'))
              .fontColor(Color.White)
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
    .borderRadius(16)
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
        .borderRadius(18)
        .backgroundColor('#F3F4F6')
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
          .borderRadius(18)
          .backgroundColor('#FEE2E2')
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
                  .height(34)
                  .fontSize(13)
                  .layoutWeight(1)
                  .onClick((): void => {
                    this.onDelete();
                    this.controller.close();
                  })

                Button('取消')
                  .backgroundColor('#E5E7EB')
                  .fontColor('#374151')
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
            src: BASE_HOST + '/api/video/' + this.segment.filepath,
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
                  .borderRadius(16)
                  .backgroundColor('#F3F4F6')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                  .onClick((): void => {
                    this.isEditingRemark = true;
                  })
                }
              }
              .width('100%')
              .padding(10)
              .backgroundColor('#F9FAFB')
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
                    .backgroundColor($r('app.color.app_primary'))
                    .fontColor(Color.White)
                    .height(36)
                    .fontSize(13)
                    .layoutWeight(1)
                    .onClick((): void => {
                      this.onUpdate(this.remarkText);
                      this.isEditingRemark = false;
                    })

                  Button('取消')
                    .backgroundColor('#E5E7EB')
                    .fontColor('#374151')
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
              .backgroundColor('#F9FAFB')
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
                      .fontColor('#10B981')
                      .backgroundColor('#D1FAE5')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                    Text('特征提炼就绪')
                      .fontSize(12)
                      .fontColor('#6B7280')
                  }

                  Text(`帧采样率: ${this.segment.sample_fps || 1} 帧/秒  |  画质: ${this.segment.resolution || '1080P'}`)
                    .fontSize(12)
                    .fontColor('#374151')
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (!this.showSelectionActions) {
                  Button('删除预处理')
                    .fontSize(12)
                    .fontColor('#EF4444')
                    .backgroundColor('#FEE2E2')
                    .height(32)
                    .onClick((): void => {
                      this.onDeleteFeatures();
                    })
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#F0FDF4')
              .borderRadius(8)
              .border({ width: 1, color: '#BBF7D0' })
              .alignItems(VerticalAlign.Center)

            } else if (this.segment.status === 'processing' || this.segment.status === 'pending') {
              // 2. 正在预处理状态：显示当前设置的精度与进度条
              Column({ space: 8 }) {
                Row() {
                  Text(`正在预处理 (${this.segment.sample_fps || 1} 帧/秒, ${this.segment.resolution || '1080P'})`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#3B82F6')
                    .layoutWeight(1)
                  Text(`${this.segment.progress}%`)
                    .fontSize(12)
                    .fontColor('#3B82F6')
                }
                .width('100%')

                Progress({ value: this.segment.progress, total: 100, type: ProgressType.Linear })
                  .width('100%')
                  .height(8)
                  .color($r('app.color.app_primary'))
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#EFF6FF')
              .borderRadius(8)
              .border({ width: 1, color: '#BFDBFE' })

            } else {
              // 3. 失败或未预处理状态：展示失败原因（若失败） + 精度选择器 + 开始/重新预处理按钮
              Column({ space: 10 }) {
                if (this.segment.status === 'failed') {
                  Text('预处理失败原因: ' + (this.segment.error_msg || '未知错误'))
                    .fontSize(12)
                    .fontColor('#EF4444')
                    .backgroundColor('#FEF2F2')
                    .padding(8)
                    .borderRadius(6)
                    .width('100%')
                }

                // A. 采样率选择 (0.5, 1, 2)
                Column({ space: 4 }) {
                  Text('帧采样率')
                    .fontSize(11)
                    .fontColor('#6B7280')
                    .width('100%')

                  Row({ space: 8 }) {
                    Button('0.5 帧/秒')
                      .fontSize(12)
                      .height(30)
                      .layoutWeight(1)
                      .fontColor(this.selectedFps === 0.5 ? Color.White : '#374151')
                      .backgroundColor(this.selectedFps === 0.5 ? $r('app.color.app_primary') : '#E5E7EB')
                      .onClick((): void => {
                        this.selectedFps = 0.5;
                      })

                    Button('1 帧/秒 (推荐)')
                      .fontSize(12)
                      .height(30)
                      .layoutWeight(1)
                      .fontColor(this.selectedFps === 1.0 ? Color.White : '#374151')
                      .backgroundColor(this.selectedFps === 1.0 ? $r('app.color.app_primary') : '#E5E7EB')
                      .onClick((): void => {
                        this.selectedFps = 1.0;
                      })

                    Button('2 帧/秒')
                      .fontSize(12)
                      .height(30)
                      .layoutWeight(1)
                      .fontColor(this.selectedFps === 2.0 ? Color.White : '#374151')
                      .backgroundColor(this.selectedFps === 2.0 ? $r('app.color.app_primary') : '#E5E7EB')
                      .onClick((): void => {
                        this.selectedFps = 2.0;
                      })
                  }
                  .width('100%')
                }

                // B. 画质清晰度选择 (480P, 720P, 1080P, 4K)，约束不超过原画
                Column({ space: 4 }) {
                  Text(`画质清晰度 (原画: ${this.segment.orig_resolution || '1080P'})`)
                    .fontSize(11)
                    .fontColor('#6B7280')
                    .width('100%')

                  Row({ space: 6 }) {
                    // 480P
                    Button('480P')
                      .fontSize(12)
                      .height(30)
                      .layoutWeight(1)
                      .fontColor(this.selectedResolution === '480P' ? Color.White : '#374151')
                      .backgroundColor(this.selectedResolution === '480P' ? $r('app.color.app_primary') : '#E5E7EB')
                      .onClick((): void => {
                        this.selectedResolution = '480P';
                      })

                    // 720P
                    Button('720P')
                      .fontSize(12)
                      .height(30)
                      .layoutWeight(1)
                      .enabled(this.isResAllowed('720P', this.segment.orig_resolution))
                      .fontColor(this.selectedResolution === '720P' ? Color.White : (this.isResAllowed('720P', this.segment.orig_resolution) ? '#374151' : '#9CA3AF'))
                      .backgroundColor(this.selectedResolution === '720P' ? $r('app.color.app_primary') : '#E5E7EB')
                      .onClick((): void => {
                        this.selectedResolution = '720P';
                      })

                    // 1080P
                    Button('1080P')
                      .fontSize(12)
                      .height(30)
                      .layoutWeight(1)
                      .enabled(this.isResAllowed('1080P', this.segment.orig_resolution))
                      .fontColor(this.selectedResolution === '1080P' ? Color.White : (this.isResAllowed('1080P', this.segment.orig_resolution) ? '#374151' : '#9CA3AF'))
                      .backgroundColor(this.selectedResolution === '1080P' ? $r('app.color.app_primary') : '#E5E7EB')
                      .onClick((): void => {
                        this.selectedResolution = '1080P';
                      })

                    // 4K
                    Button('4K')
                      .fontSize(12)
                      .height(30)
                      .layoutWeight(1)
                      .enabled(this.isResAllowed('4K', this.segment.orig_resolution))
                      .fontColor(this.selectedResolution === '4K' ? Color.White : (this.isResAllowed('4K', this.segment.orig_resolution) ? '#374151' : '#9CA3AF'))
                      .backgroundColor(this.selectedResolution === '4K' ? $r('app.color.app_primary') : '#E5E7EB')
                      .onClick((): void => {
                        this.selectedResolution = '4K';
                      })
                  }
                  .width('100%')
                }

                // C. 灰色提示文字
                Text('提示：精度越高/视频越长，预处理时间将会越长')
                  .fontSize(11)
                  .fontColor('#9CA3AF')
                  .width('100%')

                // D. 开始/重新预处理按钮
                if (!this.showSelectionActions) {
                  Button(this.segment.status === 'failed' ? '重新预处理' : '开始预处理')
                    .fontSize(13)
                    .backgroundColor($r('app.color.app_primary'))
                    .fontColor(Color.White)
                    .width('100%')
                    .height(36)
                    .onClick((): void => {
                      this.onPreprocess(this.selectedFps, this.selectedResolution);
                    })
                }
              }
              .width('100%')
              .padding(10)
              .backgroundColor('#F9FAFB')
              .borderRadius(8)
            }
          }
          .width('100%')

          // 问答选框选择模式的确认/取消按键
          if (this.showSelectionActions) {
            Row({ space: 10 }) {
              Button('确认选择')
                .backgroundColor($r('app.color.app_primary'))
                .fontColor(Color.White)
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .padding({ left: 0, right: 0 })
                .onClick((): void => {
                  this.onConfirmSelection();
                  this.controller.close();
                })

              Button('取消')
                .backgroundColor('#999999')
                .fontColor(Color.White)
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
    .borderRadius(16)
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
    const params = router.getParams() as Record<string, Object>;
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
      promptAction.showToast({ message: '获取人脸识别轨迹失败', duration: 1500 });
    }
  }

  jumpToFaceRecordVideo(rec: WorkspaceFaceRecordInfo): void {
    if (!rec.segment_filepath) {
      promptAction.showToast({ message: '对应视频文件已不存在', duration: 2000 });
      return;
    }

    const s = new WorkspaceVideoSegment();
    s.id = rec.segment_id;
    s.video_name = rec.video_name;
    s.filepath = rec.segment_filepath;
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
      this.activeVideo.url = BASE_HOST + "/api/video/" + path;
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

    promptAction.showToast({ message: '正在校验录像完整性并拼接截取...', duration: 2000 });
    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/segments`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '监控片段拼接截取成功', duration: 1500 });
      this.showSelectExampleVideo = false;
      this.loadSegments();
    } else {
      promptAction.showToast({ message: res.message || '截取失败，请检查录像完整性', duration: 3500 });
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

    promptAction.showToast({ message: '正在物理裁剪并保存片段...', duration: 1500 });
    const res = await HttpUtil.post(`/workspaces/${this.workspaceId}/segments`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '片段添加成功', duration: 1500 });
      this.showSelectExampleVideo = false;
      this.loadSegments();
    } else {
      promptAction.showToast({ message: '保存失败: ' + (res.message || '未知错误'), duration: 2000 });
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
      promptAction.showToast({ message: '找不到对应的视频文件', duration: 1500 });
      return;
    }
    const filepath = this.activeTaskVideoPaths[videoNumber - 1];
    const realSeg = this.findSegmentByFilepath(filepath);
    if (realSeg === null) {
      promptAction.showToast({ message: '该视频片段已删除，无法跳转播放', duration: 1500 });
      return;
    }
    
    this.selectedSegment = realSeg;
    this.selectedSegmentIndex = videoNumber - 1;
    this.jumpSeconds = timeToSeconds(timeStr);
    
    this.timestampPreviewDialogController.open();
    promptAction.showToast({ message: `已跳转到视频 ${videoNumber} 的 ${timeStr}`, duration: 1500 });
  }

  async submitUpdateSegment(segmentId: number, remark: string): Promise<void> {
    class UpdatePayload {
      remark: string = '';
    }
    const payload = new UpdatePayload();
    payload.remark = remark;

    const res = await HttpUtil.put(`/workspaces/segments/${segmentId}`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '备注修改成功', duration: 1500 });
      this.loadSegments();
    } else {
      promptAction.showToast({ message: '修改失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  async submitDeleteSegment(segmentId: number): Promise<void> {
    const res = await HttpUtil.del(`/workspaces/segments/${segmentId}`);
    if (res.code === 0) {
      promptAction.showToast({ message: '片段删除成功', duration: 1500 });
      this.loadSegments();
    } else {
      promptAction.showToast({ message: '删除失败: ' + (res.message || '未知错误'), duration: 2000 });
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
      promptAction.showToast({ message: '已开始预处理', duration: 1500 });
      this.loadSegments();
    } else {
      promptAction.showToast({ message: '启动预处理失败: ' + (res.message || '未知错误'), duration: 2000 });
    }
  }

  async submitDeleteSegmentFeatures(segmentId: number): Promise<void> {
    const res = await HttpUtil.del(`/workspaces/segments/${segmentId}/features`);
    if (res.code === 0) {
      promptAction.showToast({ message: '预处理特征已删除', duration: 1500 });
      this.loadSegments();
    } else {
      promptAction.showToast({ message: '删除特征失败: ' + (res.message || '未知错误'), duration: 2000 });
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
          promptAction.showToast({ message: 'AI 分析已完成', duration: 2000 });
          this.loadQARecords();
        } else if (status === 'failed') {
          clearInterval(this.pollIntervalId);
          this.pollIntervalId = 0;
          this.aiProgressText = '分析失败：' + error;
          promptAction.showToast({ message: 'AI 分析发生错误', duration: 2000 });
          this.loadQARecords();
        }
      } else {
        clearInterval(this.pollIntervalId);
        this.pollIntervalId = 0;
        this.aiProgressText = '获取分析进度失败: ' + (res.message || '网络连接异常');
      }
    }, 400);
  }

  async submitQA(): Promise<void> {
    if (!this.questionText) {
      promptAction.showToast({ message: '请输入问题', duration: 1500 });
      return;
    }
    
    const selectedList = this.segments.filter(v => v.isSelected);
    if (selectedList.length === 0) {
      promptAction.showToast({ message: '请至少选择一个视频片段', duration: 1500 });
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

  build() {
    Column() {
      // ===== Top Bar =====
      Row() {
        if (this.activeTaskId !== '') {
          // Inside Q&A detail view: show Back arrow and Home icon
          Row({ space: 14 }) {
            // Back Arrow Button (Polyline)
            Polyline({ width: 18, height: 18 })
              .points([[14, 2], [5, 9], [14, 16]])
              .fill(Color.Transparent)
              .stroke('#3B82F6')
              .strokeWidth(2.5)
              .strokeLineCap(LineCapStyle.Round)
              .strokeLineJoin(LineJoinStyle.Round)
              .onClick((): void => {
                if (this.pollIntervalId) {
                  clearInterval(this.pollIntervalId);
                  this.pollIntervalId = 0;
                }
                this.activeTaskId = '';
                this.aiProgressText = '';
                this.questionText = '';
                this.loadQARecords();
              })

            // Home Button (Polyline + Rect)
            Column() {
              Polyline({ width: 22, height: 10 })
                .points([[0, 10], [11, 0], [22, 10]])
                .fill(Color.Transparent)
                .stroke('#3B82F6')
                .strokeWidth(2.5)
                .strokeLineCap(LineCapStyle.Round)
                .strokeLineJoin(LineJoinStyle.Round)
              Rect({ width: 16, height: 10 })
                .fill(Color.Transparent)
                .stroke('#3B82F6')
                .strokeWidth(2.5)
                .strokeLineJoin(LineJoinStyle.Round)
                .margin({ top: -2.5 })
            }
            .alignItems(HorizontalAlign.Center)
            .onClick((): void => {
              if (this.pollIntervalId) {
                clearInterval(this.pollIntervalId);
                this.pollIntervalId = 0;
              }
              router.back();
            })
          }
          .alignItems(VerticalAlign.Center)
          .margin({ right: 14 })
        } else {
          // Inside Q&A list view: show Home button only
          Column() {
            Polyline({ width: 22, height: 10 })
              .points([[0, 10], [11, 0], [22, 10]])
              .fill(Color.Transparent)
              .stroke('#3B82F6')
              .strokeWidth(2.5)
              .strokeLineCap(LineCapStyle.Round)
              .strokeLineJoin(LineJoinStyle.Round)
            Rect({ width: 16, height: 10 })
              .fill(Color.Transparent)
              .stroke('#3B82F6')
              .strokeWidth(2.5)
              .strokeLineJoin(LineJoinStyle.Round)
              .margin({ top: -2.5 })
          }
          .alignItems(HorizontalAlign.Center)
          .margin({ right: 14 })
          .onClick((): void => {
            if (this.pollIntervalId) {
              clearInterval(this.pollIntervalId);
              this.pollIntervalId = 0;
            }
            router.back();
          })
        }

        // Title: "问答详情" or workspaceName
        Text(this.activeTaskId !== '' ? '问答详情' : this.workspaceName)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .layoutWeight(1)

        if (this.activeTaskId !== '') {
          // Status Badge on the right
          Text(this.activeTaskStatus === 'completed' ? '已完成' : (this.activeTaskStatus === 'failed' ? '失败' : '分析中'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.activeTaskStatus === 'completed' ? '#10B981' : (this.activeTaskStatus === 'failed' ? '#EF4444' : '#3B82F6'))
            .backgroundColor(this.activeTaskStatus === 'completed' ? '#D1FAE5' : (this.activeTaskStatus === 'failed' ? '#FEE2E2' : '#DBEAFE'))
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(12)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.activeTaskId !== '') {
        // ===== Q&A Analysis Process / Detail View =====
        Column({ space: 15 }) {

          Scroll(this.scroller) {
            Column({ space: 15 }) {
              Column({ space: 8 }) {
                Text('问题')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#9CA3AF')
                  .alignSelf(ItemAlign.Start)
                
                Text(this.activeTaskQuestion)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#111827')
                  .width('100%')
              }
              .width('100%')
              .padding(15)
              .backgroundColor(Color.White)
              .borderRadius(8)
              .shadow({ radius: 3, color: '#0D000000' })

              // ===== Selected Videos Panel (collapsible) =====
              if (this.activeTaskVideoPaths && this.activeTaskVideoPaths.length > 0) {
                Column() {
                  Row() {
                    Text(`关联视频片段 (${this.activeTaskVideoPaths.length})`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#9CA3AF')
                      .layoutWeight(1)
                    Text(this.isVideosCollapsed ? '展开 ▼' : '收起 ▲')
                      .fontSize(12)
                      .fontColor('#9CA3AF')
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
                              Image(BASE_HOST + '/api/video/thumbnail/' + filepath)
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
                                  .fontColor('#9CA3AF')
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                                Text(`时间段：${this.findSegmentByFilepath(filepath)!.start_offset.toFixed(1)}s - ${this.findSegmentByFilepath(filepath)!.end_offset.toFixed(1)}s`)
                                  .fontSize(12)
                                  .fontColor('#9CA3AF')
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
                          .shadow({ radius: 3, color: $r('app.color.app_shadow') })
                          .onClick((): void => {
                            const seg = this.findSegmentByFilepath(filepath);
                            if (seg !== null) {
                              this.showSegmentDetail(seg);
                            } else {
                              promptAction.showToast({ message: '该片段已删除，无法查看', duration: 1500 });
                            }
                          })

                          Text(`视频 ${index + 1}`)
                            .fontSize(10)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(Color.White)
                            .backgroundColor('#3B82F6')
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
                .backgroundColor(Color.White)
                .borderRadius(8)
                .shadow({ radius: 3, color: '#0D000000' })
              }

              if (this.progressGroups.length > 0) {
                ForEach(this.progressGroups, (group: ProgressGroup, idx: number): void => {
                  Column() {
                    Row() {
                      Circle({ width: 10, height: 10 })
                        .fill(group.isFailed ? '#EF4444' : (group.isCompleted ? '#10B981' : '#3B82F6'))
                        .margin({ right: 10 })

                      Row() {
                        Text(group.title)
                          .fontSize(14)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#374151')

                        if (group.badgeText) {
                          Text(group.badgeText)
                            .fontSize(10)
                            .fontColor('#3B82F6')
                            .backgroundColor('#EFF6FF')
                            .borderRadius(4)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .margin({ left: 6 })
                        }
                      }
                      .layoutWeight(1)

                      if (group.isFailed) {
                        Text('失败')
                          .fontSize(12)
                          .fontColor('#EF4444')
                          .margin({ right: 10 })
                      } else if (group.isCompleted) {
                        Text('已完成')
                          .fontSize(12)
                          .fontColor('#10B981')
                          .margin({ right: 10 })
                      } else {
                        Text('运行中')
                          .fontSize(12)
                          .fontColor('#3B82F6')
                          .margin({ right: 10 })
                      }

                      if (group.id !== 'answering') {
                        Text(group.isCollapsed ? '▼' : '▲')
                          .fontSize(12)
                          .fontColor('#9CA3AF')
                      }
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12, left: 15, right: 15 })
                    .backgroundColor('#F3F4F6')
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
                              .fontColor('#4B5563')
                              .margin({ right: 8 })
                            Text(detail)
                              .fontSize(13)
                              .fontColor('#4B5563')
                              .lineHeight(18)
                              .layoutWeight(1)
                          }
                          .width('100%')
                          .alignItems(VerticalAlign.Top)
                        })
                      }
                      .width('100%')
                      .padding({ left: 30, right: 15, top: 10, bottom: 10 })
                      .backgroundColor(Color.White)
                      .borderWidth({ left: 2, right: 0, top: 0, bottom: 0 })
                      .borderColor('#E5E7EB')
                    }
                  }
                  .width('100%')
                  .borderRadius(8)
                  .clip(true)
                  .shadow({ radius: 2, color: '#05000000' })
                })
              } else {
                Text('等待分析任务启动...')
                  .fontSize(13)
                  .fontColor('#9CA3AF')
                  .padding(15)
              }

              if (this.activeTaskAnswer || this.activeTaskStatus === 'completed' || this.activeTaskStatus === 'failed') {
                Column({ space: 8 }) {
                  Text('AI 回答')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#9CA3AF')
                    .alignSelf(ItemAlign.Start)

                  if (this.activeTaskAnswer) {
                    Column({ space: 6 }) {
                      ForEach(parseAnswerToChunks(this.activeTaskAnswer), (paraChunks: Array<TextChunk>): void => {
                        Text() {
                          ForEach(paraChunks, (chunk: TextChunk): void => {
                            Span(chunk.content)
                              .fontWeight(chunk.isBold ? FontWeight.Bold : FontWeight.Normal)
                              .fontColor(chunk.isTimestamp ? '#3B82F6' : (this.activeTaskStatus === 'failed' ? '#EF4444' : '#1F2937'))
                              .decoration(chunk.isTimestamp ? { type: TextDecorationType.Underline, color: '#3B82F6' } : { type: TextDecorationType.None })
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
                      .fontColor('#9CA3AF')
                      .width('100%')
                      .lineHeight(20)
                  }
                }
                .width('100%')
                .padding(15)
                .backgroundColor(Color.White)
                .borderRadius(8)
                .shadow({ radius: 3, color: '#0D000000' })
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
                    .backgroundColor($r('app.color.app_primary'))
                    .fontColor(Color.White)
                    .onClick((): void => {
                      this.loadExampleVideos();
                    })
                  
                  Button('返回')
                    .fontSize(12)
                    .height(32)
                    .backgroundColor('#666666')
                    .fontColor(Color.White)
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
                      .backgroundColor($r('app.color.app_primary'))
                      .fontColor(Color.White)
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
                          Image(BASE_HOST + '/api/video/thumbnail/' + seg.filepath)
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
}
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
                        .shadow({ radius: 4, color: $r('app.color.app_shadow') })
                        .onClick((): void => {
                          this.showSegmentDetail(seg);
                        })
                      }
                    })
                  }
                  .width('90%')
                  .layoutWeight(1)
                }

                Button('+ 截取新片段')
                  .width('90%')
                  .height(48)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .margin({ top: 15, bottom: 20 })
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
                  .height(30)
                  .backgroundColor('#EFF6FF')
                  .fontColor('#1E40AF')
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
                  Image($r('app.media.startIcon'))
                    .width(60)
                    .height(60)
                    .opacity(0.3)
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
                          Image(BASE_HOST + '/api/video/thumbnail/' + seg.filepath)
                            .width(100)
                            .height(60)
                            .borderRadius(6)
                            .objectFit(ImageFit.Cover)
                            .margin({ right: 12 })

                          Column({ space: 4 }) {
                            Text(seg.remark ? seg.remark : '未命名片段')
                              .fontSize(15)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(seg.isSelected ? '#3B82F6' : $r('app.color.app_text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            Text('来自监控：' + seg.video_name)
                              .fontSize(12)
                              .fontColor('#9CA3AF')
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
                                .fontColor('#9CA3AF')
                                .maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                            }
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)
                        }
                        .width('100%')
                        .padding(10)
                        .backgroundColor(seg.isSelected ? '#EFF6FF' : $r('app.color.app_card_bg'))
                        .borderRadius(8)
                        .opacity(1.0)
                        .border({
                          width: 1.5,
                          color: seg.isSelected ? '#3B82F6' : Color.Transparent
                        })
                        .onClick((): void => {
                          if (seg.status === 'processing' || seg.status === 'pending') {
                            promptAction.showToast({ message: '该片段正在后台预处理中，可同步提交问答', duration: 1500 });
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
                TextArea({ placeholder: '请输入问题，例如：画面里有没有人经过？有几个人？', text: this.questionText })
                  .height(80)
                  .fontColor($r('app.color.app_text_primary'))
                  .backgroundColor($r('app.color.app_input_bg'))
                  .onChange((val: string): void => {
                    this.questionText = val;
                  })

                Row({ space: 15 }) {
                  Button('取消')
                    .layoutWeight(1)
                    .backgroundColor($r('app.color.app_text_muted'))
                    .fontColor(Color.White)
                    .onClick((): void => {
                      this.showCreateQA = false;
                      this.aiProgressText = '';
                      this.questionText = '';
                    })

                  Button('提交分析')
                    .layoutWeight(1)
                    .backgroundColor($r('app.color.app_primary'))
                    .fontColor(Color.White)
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
                    .backgroundColor('#E8F5E9')
                    .borderRadius(10)
                    .fontColor('#2E7D32')
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

                          Image($r('app.media.startIcon'))
                            .width(20)
                            .height(20)
                            .opacity(0.5)
                        }
                        .width('100%')
                        .padding(15)
                        .backgroundColor($r('app.color.app_card_bg'))
                        .borderRadius(10)
                        .shadow({ radius: 4, color: $r('app.color.app_shadow') })
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

                Button('+ 新建问答')
                  .width('90%')
                  .height(48)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .margin({ top: 15, bottom: 20 })
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

          // ===== Bottom Tab Bar (Three Tabs: 片段 | 人脸 | 问答) =====
          Row() {
            // Tab 0: 片段
            Column() {
              Stack() {
                Rect({ width: 22, height: 16 })
                  .fill(Color.Transparent)
                  .stroke(this.currentSubTab === 0 ? '#3B82F6' : '#9CA3AF')
                  .strokeWidth(2)
                  .strokeLineJoin(LineJoinStyle.Round)
                Polygon({ width: 6, height: 8 })
                  .points([[0, 0], [0, 8], [6, 4]])
                  .fill(this.currentSubTab === 0 ? '#3B82F6' : '#9CA3AF')
                  .margin({ left: 2 })
              }
              .width(22)
              .height(22)
              .margin({ bottom: 4 })

              Text('片段')
                .fontSize(11)
                .fontColor(this.currentSubTab === 0 ? $r('app.color.app_primary') : $r('app.color.app_text_muted'))
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
            .onClick((): void => {
              this.currentSubTab = 0;
              this.showCreateQA = false;
              this.showSelectExampleVideo = false;
              this.loadSegments();
            })

            Column() {
              // Custom Chat/Q&A outline icon (1:1 aspect ratio)
              Stack() {
                Rect({ width: 20, height: 14 })
                  .fill(Color.Transparent)
                  .stroke(this.currentSubTab === 1 ? '#3B82F6' : '#9CA3AF')
                  .strokeWidth(2)
                  .strokeLineJoin(LineJoinStyle.Round)
                  .borderRadius(2)
                Polygon({ width: 5, height: 5 })
                  .points([[5, 0], [0, 5], [5, 5]])
                  .fill(this.currentSubTab === 1 ? '#3B82F6' : '#9CA3AF')
                  .offset({ x: -5, y: 7 })
              }
              .width(22)
              .height(22)
              .margin({ bottom: 4 })

              Text('问答')
                .fontSize(11)
                .fontColor(this.currentSubTab === 1 ? $r('app.color.app_primary') : $r('app.color.app_text_muted'))
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
            .onClick((): void => {
              this.currentSubTab = 1;
              this.showCreateQA = false;
              this.showSelectExampleVideo = false;
              this.loadQARecords();
            })
          }
          .width('100%')
          .height(56)
          .backgroundColor('#F9FAFB')
          .border({ width: { top: 1 }, color: '#E5E7EB' })
          .padding({ top: 5, bottom: 5 })
        }
        .width('100%')
        .layoutWeight(1)
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
          .linearGradient({
            angle: 135,
            colors: this.sourceType === 'monitor' ? [['#DBEAFE', 0.0], ['#BFDBFE', 1.0]] : (this.sourceType === 'upload' ? [['#D1FAE5', 0.0], ['#A7F3D0', 1.0]] : [['#F3E8FF', 0.0], ['#E9D5FF', 1.0]])
          })
          .borderRadius({ topLeft: 8, topRight: 8 })

        // 视频源分类徽章
        Text(this.sourceType === 'monitor' ? '监控设备' : (this.sourceType === 'upload' ? '上传视频' : '示例视频'))
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.sourceType === 'monitor' ? '#1E40AF' : (this.sourceType === 'upload' ? '#065F46' : '#6B21A8'))
          .backgroundColor(this.sourceType === 'monitor' ? '#EFF6FF' : (this.sourceType === 'upload' ? '#ECFDF5' : '#F5F3FF'))
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .borderRadius(4)
          .margin({ left: 6, top: 6 })
          .alignSelf(ItemAlign.Start)

        Image($r('app.media.startIcon'))
          .width(28)
          .height(28)
          .alignSelf(ItemAlign.Center)
          .opacity(0.8)

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
    .shadow({ radius: 3, color: $r('app.color.app_shadow') })
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
          .linearGradient({
            angle: 135,
            colors: [['#EFF6FF', 0.0], ['#DBEAFE', 1.0]]
          })
          .borderRadius({ topLeft: 8, topRight: 8 })

        Image(this.group.avatar_url ? (BASE_HOST + this.group.avatar_url) : $r('app.media.startIcon'))
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
    .shadow({ radius: 3, color: $r('app.color.app_shadow') })
    .onClick((): void => {
      this.onCardClick();
    })
  }
}
