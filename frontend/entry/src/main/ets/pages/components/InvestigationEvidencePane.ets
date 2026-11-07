import { HttpUtil, BASE_HOST } from '../../utils/http';
import { InvestigationClip, InvestigationEvidenceMark,
  InvestigationFace, InvestigationFaceRecord, faceRecordsForClip } from '../../utils/investigationLayout';
import { RenewableVideo } from './RenewableVideo';

@Component
export struct InvestigationEvidencePane {
  workspaceId: number = 0;
  @Prop clips: Array<InvestigationClip> = [];
  @Prop @Watch('onFocusChanged') segmentId: number = 0;
  @Prop seconds: number = 0;
  @Prop seekRevision: number = 0;
  @Prop marks: Array<InvestigationEvidenceMark> = [];
  @Prop resourceWidth: number = 0;
  @Prop playerHeight: number = 220;
  onSelect: (segmentId: number, seconds: number) => void = (_id: number, _seconds: number): void => {};
  onPosition: (segmentId: number, seconds: number) => void = (_id: number, _seconds: number): void => {};
  onRetry: () => void = (): void => {};
  @State resourceTab: number = 0;
  @State faces: Array<InvestigationFace> = [];
  @State records: Array<InvestigationFaceRecord> = [];
  @State selectedFaceId: number = 0;
  @State faceLoading: boolean = false;
  @State faceError: string = '';
  private faceEpoch: number = 0;
  private faceSegmentId: number = 0;
  private visible: boolean = false;

  aboutToAppear(): void { this.visible = true; }
  aboutToDisappear(): void { this.visible = false; this.faceEpoch++; }

  private timeText(seconds: number): string {
    const value = Math.max(0, Math.floor(seconds));
    const minute = Math.floor(value / 60).toString().padStart(2, '0');
    return `${minute}:${(value % 60).toString().padStart(2, '0')}`;
  }

  private activeClips(): Array<InvestigationClip> {
    return this.clips.filter((clip: InvestigationClip): boolean => clip.id === this.segmentId);
  }

  private activeClip(): InvestigationClip {
    return this.clips.find((clip: InvestigationClip): boolean => clip.id === this.segmentId) ||
      new InvestigationClip();
  }

  private onFocusChanged(): void {
    if (this.faceSegmentId !== this.segmentId) {
      this.faceEpoch++;
      this.faces = [];
      this.records = [];
      this.selectedFaceId = 0;
      this.faceError = '';
      this.faceLoading = false;
      if (this.resourceTab === 1) this.loadFaces();
    }
  }

  private async loadFaces(): Promise<void> {
    const segmentId = this.segmentId;
    const epoch = ++this.faceEpoch;
    this.faceSegmentId = segmentId;
    this.selectedFaceId = 0;
    this.faces = [];
    this.records = [];
    this.faceError = '';
    if (!segmentId) return;
    this.faceLoading = true;
    try {
      const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/faces?segment_id=${segmentId}`);
      if (!this.visible || epoch !== this.faceEpoch) return;
      if (res.code !== 0 || !res.data) throw new Error('load faces');
      const raw = JSON.parse(res.data) as Array<Record<string, Object>>;
      if (!Array.isArray(raw)) throw new Error('invalid faces');
      this.faces = raw.map((item: Record<string, Object>): InvestigationFace => {
        const face = new InvestigationFace();
        face.id = item['id'] as number;
        face.name = (item['name'] as string) || `人脸 #${face.id}`;
        face.imageUrl = (item['avatar_url'] as string) || '';
        face.count = (item['record_count'] as number) || 0;
        return face;
      });
    } catch (_error) {
      if (this.visible && epoch === this.faceEpoch) this.faceError = '人脸线索加载失败';
    } finally {
      if (epoch === this.faceEpoch) this.faceLoading = false;
    }
  }

  private async openFace(faceId: number): Promise<void> {
    const segmentId = this.segmentId;
    const epoch = ++this.faceEpoch;
    this.selectedFaceId = faceId;
    this.records = [];
    this.faceLoading = true;
    this.faceError = '';
    try {
      const res = await HttpUtil.get(`/workspaces/${this.workspaceId}/faces/${faceId}/records?segment_id=${segmentId}`);
      if (!this.visible || epoch !== this.faceEpoch) return;
      if (res.code !== 0 || !res.data) throw new Error('load records');
      const raw = JSON.parse(res.data) as Array<Record<string, Object>>;
      if (!Array.isArray(raw)) throw new Error('invalid records');
      this.records = faceRecordsForClip(raw, segmentId);
    } catch (_error) {
      if (this.visible && epoch === this.faceEpoch) this.faceError = '人脸抓拍加载失败';
    } finally {
      if (epoch === this.faceEpoch) this.faceLoading = false;
    }
  }

  @Builder ResourceTabs() {
    Row({ space: 4 }) {
      ForEach(['引用片段', '人脸线索'], (label: string, index: number): void => {
        Button(label).fontSize(12).height(36).layoutWeight(1).borderRadius(8)
          .backgroundColor(this.resourceTab === index ? $r('app.color.app_primary_soft') : Color.Transparent)
          .fontColor(this.resourceTab === index ? $r('app.color.app_primary') : $r('app.color.app_text_secondary'))
          .accessibilityText(`${label}${this.resourceTab === index ? '，已选中' : ''}`)
          .onClick((): void => {
            this.resourceTab = index;
            if (index === 1) this.loadFaces();
          })
      })
    }.width('100%').padding(8)
  }

  @Builder ClipList() {
    List({ space: 4 }) {
      ForEach(this.clips, (clip: InvestigationClip, index: number): void => {
        ListItem() {
          Column({ space: 7 }) {
            if (clip.thumbnailUrl) {
              Image(BASE_HOST + clip.thumbnailUrl).width('100%').height(88)
                .objectFit(ImageFit.Contain).backgroundColor(Color.Black).borderRadius(6)
            }
            Row({ space: 6 }) {
              Text(`视频 ${index + 1}`).fontSize(11).fontColor($r('app.color.app_text_muted'))
              Blank()
              if (clip.id === this.segmentId) {
                Text('正在查看').fontSize(10).fontColor($r('app.color.app_primary'))
              }
            }.width('100%')
            Text(clip.title).fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary')).maxLines(2)
            Text(clip.videoName).fontSize(10).fontColor($r('app.color.app_text_muted'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%').alignItems(HorizontalAlign.Start).padding(10).borderRadius(8)
            .backgroundColor(clip.id === this.segmentId ? $r('app.color.app_primary_soft') : Color.Transparent)
            .border({ width: 1, color: clip.id === this.segmentId ?
              $r('app.color.app_selection') : Color.Transparent })
            .accessibilityText(`查看视频 ${index + 1}，${clip.title}`)
            .onClick((): void => { this.onSelect(clip.id, 0); })
        }
      }, (clip: InvestigationClip): string => `${clip.id}`)
    }.width('100%').layoutWeight(1).padding({ left: 8, right: 8 })
  }

  @Builder FaceList() {
    Column({ space: 8 }) {
      Text('仅当前视频').fontSize(11).fontColor($r('app.color.app_text_muted'))
      if (this.selectedFaceId > 0) {
        Button('‹ 全部人脸').fontSize(12).height(32).backgroundColor(Color.Transparent)
          .fontColor($r('app.color.app_primary'))
          .onClick((): void => { this.loadFaces(); })
      }
      if (this.faceLoading) {
        LoadingProgress().width(28).height(28).color($r('app.color.app_primary'))
      } else if (this.faceError) {
        Text(this.faceError).fontSize(12).fontColor($r('app.color.app_text_secondary'))
        Button('重试').fontSize(12).onClick((): void => {
          if (this.selectedFaceId) this.openFace(this.selectedFaceId);
          else this.loadFaces();
        })
      } else if (this.selectedFaceId > 0) {
        List({ space: 8 }) {
          ForEach(this.records, (record: InvestigationFaceRecord): void => {
            ListItem() {
              Row({ space: 10 }) {
                if (record.imageUrl) {
                  Image(BASE_HOST + record.imageUrl).width(60).height(60).objectFit(ImageFit.Contain)
                    .backgroundColor($r('app.color.app_card_subtle_bg')).borderRadius(6)
                }
                Column({ space: 6 }) {
                  Text(this.timeText(record.seconds)).fontSize(13).fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.app_text_primary'))
                  Text('定位抓拍 ›').fontSize(11).fontColor($r('app.color.app_primary'))
                }.alignItems(HorizontalAlign.Start)
              }.width('100%').padding(8)
                .onClick((): void => { this.onSelect(record.segmentId, record.seconds); })
            }
          }, (record: InvestigationFaceRecord): string => `${record.id}`)
          if (this.records.length === 0) {
            ListItem() { Text('当前视频中暂无抓拍记录').fontSize(12).padding(12) }
          }
        }.width('100%').layoutWeight(1)
      } else {
        List({ space: 6 }) {
          ForEach(this.faces, (face: InvestigationFace): void => {
            ListItem() {
              Row({ space: 8 }) {
                if (face.imageUrl) {
                  Image(BASE_HOST + face.imageUrl).width(52).height(52).objectFit(ImageFit.Contain)
                    .backgroundColor($r('app.color.app_card_subtle_bg')).borderRadius(6)
                }
                Column({ space: 5 }) {
                  Text(face.name).fontSize(12).fontColor($r('app.color.app_text_primary')).maxLines(2)
                  Text(`${face.count} 条抓拍 ›`).fontSize(11).fontColor($r('app.color.app_text_muted'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%').padding(8).onClick((): void => { this.openFace(face.id); })
            }
          }, (face: InvestigationFace): string => `${face.id}`)
          if (this.faces.length === 0) {
            ListItem() { Text('当前视频暂无人脸线索').fontSize(12).padding(12) }
          }
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').layoutWeight(1).padding(8).alignItems(HorizontalAlign.Start)
  }

  @Builder ClipSwitcher() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.clips, (clip: InvestigationClip, index: number): void => {
          Button(`视频 ${index + 1}`).height(32).fontSize(12).borderRadius(7)
            .backgroundColor(clip.id === this.segmentId ? $r('app.color.app_primary_soft') : Color.Transparent)
            .fontColor(clip.id === this.segmentId ? $r('app.color.app_primary') : $r('app.color.app_text_muted'))
            .accessibilityText(`视频 ${index + 1}，${clip.title}`)
            .onClick((): void => { this.onSelect(clip.id, 0); })
        }, (clip: InvestigationClip): string => `${clip.id}`)
      }
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
  }

  @Builder EvidenceList() {
    Column({ space: 6 }) {
      Row() {
        Text('工具证据').fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_primary')).layoutWeight(1)
        Text(`${this.marks.length} 个时间点`).fontSize(11).fontColor($r('app.color.app_text_muted'))
      }.width('100%').padding({ left: 12, right: 12, top: 12, bottom: 6 })
      List({ space: 2 }) {
        ForEach(this.marks, (mark: InvestigationEvidenceMark): void => {
          ListItem() {
            Row({ space: 10 }) {
              Text(this.timeText(mark.seconds)).fontSize(12).fontWeight(FontWeight.Medium).width(52)
                .fontColor($r('app.color.app_primary'))
              Column({ space: 3 }) {
                Text(this.clips.findIndex((clip: InvestigationClip): boolean => clip.id === mark.segmentId) >= 0 ?
                  `视频 ${this.clips.findIndex((clip: InvestigationClip): boolean => clip.id === mark.segmentId) + 1}` : '视频')
                  .fontSize(11).fontColor($r('app.color.app_text_secondary'))
                Text(mark.label).fontSize(11).fontColor($r('app.color.app_text_muted'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('›').fontSize(17).fontColor($r('app.color.app_text_muted'))
            }.width('100%').padding(10).borderRadius(6)
              .backgroundColor(mark.segmentId === this.segmentId && Math.abs(mark.seconds - this.seconds) < 0.1 ?
                $r('app.color.app_primary_soft') : Color.Transparent)
              .onClick((): void => { this.onSelect(mark.segmentId, mark.seconds); })
          }
        }, (mark: InvestigationEvidenceMark): string => `${mark.segmentId}-${mark.seconds}`)
        if (this.marks.length === 0) {
          ListItem() {
            Text('点击回答中的时间点，在这里核验画面。').fontSize(12)
              .fontColor($r('app.color.app_text_muted')).padding(12)
          }
        }
      }.width('100%').layoutWeight(1)
    }.width('100%').layoutWeight(1)
  }

  build() {
    Row() {
      if (this.resourceWidth > 0) {
        Column() {
          this.ResourceTabs()
          if (this.resourceTab === 0) { this.ClipList() }
          else { this.FaceList() }
        }.width(this.resourceWidth).height('100%')
          .border({ width: { right: 1 }, color: $r('app.color.app_border') })
      }
      Column({ space: 8 }) {
        Row() {
          Text('视频核验').fontSize(15).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary')).layoutWeight(1)
          Text(this.timeText(this.seconds)).fontSize(12).fontColor($r('app.color.app_primary'))
        }.width('100%').padding({ left: 12, right: 12, top: 12 })
        if (this.resourceWidth === 0) { this.ClipSwitcher() }
        if (this.activeClips().length > 0) {
          Column({ space: 6 }) {
            Text(this.activeClip().title).fontSize(12).fontColor($r('app.color.app_text_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (this.activeClip().mediaUrl) {
              RenewableVideo({ source: this.activeClip().mediaUrl, initialSeconds: this.seconds,
                seekRevision: this.seekRevision, autoPlay: this.seekRevision > 0,
                onPosition: (seconds: number): void => { this.onPosition(this.segmentId, seconds); } })
                .width('100%').height(this.playerHeight).clip(true).borderRadius(8)
            } else {
              Column({ space: 8 }) {
                Text('片段暂时无法播放').fontSize(13).fontColor(Color.White)
                Button('重新加载').fontSize(12).onClick((): void => { this.onRetry(); })
              }.width('100%').height(this.playerHeight).backgroundColor(Color.Black)
                .justifyContent(FlexAlign.Center).borderRadius(8)
            }
          }.width('100%').padding({ left: 12, right: 12 })
        }
        if (this.activeClips().length === 0) {
          Text('选择一个引用片段开始核验').fontSize(13).fontColor($r('app.color.app_text_muted'))
            .width('100%').height(this.playerHeight).textAlign(TextAlign.Center)
        }
        if (this.resourceWidth === 0) {
          this.ResourceTabs()
          if (this.resourceTab === 1) { this.FaceList() }
          else { this.EvidenceList() }
        } else { this.EvidenceList() }
      }.layoutWeight(1).height('100%')
    }.height('100%').backgroundColor($r('app.color.app_card_subtle_bg'))
      .border({ width: { right: 1 }, color: $r('app.color.app_border') })
  }
}
