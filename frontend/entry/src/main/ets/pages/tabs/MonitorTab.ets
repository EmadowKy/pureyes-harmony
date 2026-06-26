import { HttpUtil, BASE_HOST } from '../../utils/http'
import promptAction from '@ohos.promptAction'

export class MonitorInfo {
  id: number = 0;
  name: string = '';
  stream_url: string = '';
}

class AddMonitorPayload {
  name: string = '';
  stream_url: string = '';
}

@CustomDialog
struct AddMonitorDialog {
  controller: CustomDialogController
  @State monitorName: string = '';
  @State streamUrl: string = '';
  confirm: (name: string, streamUrl: string) => void = (_n: string, _u: string): void => {};

  build() {
    Column({ space: 15 }) {
      Text('添加监控').fontSize(20).fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '监控名称', text: this.monitorName })
        .onChange((val: string): void => {
          this.monitorName = val;
        })
        .height(40)

      TextInput({ placeholder: '视频流地址 (stream_url)', text: this.streamUrl })
        .onChange((val: string): void => {
          this.streamUrl = val;
        })
        .height(40)

      Row({ space: 20 }) {
        Button('取消')
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)

        Button('提交')
          .onClick((): void => {
            this.confirm(this.monitorName, this.streamUrl);
            this.controller.close();
          })
      }.margin({ top: 10 })
    }.padding(20).width('90%')
  }
}

@Component
export struct MonitorTab {
  @Prop @Watch('onGroupChange') groupId: number = 0;
  @State monitors: Array<MonitorInfo> = [];
  @State selectedMonitorId: number = 0;
  @State selectedMonitorName: string = '';
  @State selectedMonitorUrl: string = '';
  @State timelineValue: number = 50;
  @State isLiveStream: boolean = false;

  addMonitorDialogController: CustomDialogController = new CustomDialogController({
    builder: AddMonitorDialog({
      confirm: (name: string, streamUrl: string): void => {
        this.submitAddMonitor(name, streamUrl);
      }
    }),
    autoCancel: true
  })

  aboutToAppear(): void {
    this.loadMonitors();
  }

  onGroupChange(): void {
    this.loadMonitors();
  }

  async loadMonitors(): Promise<void> {
    if (!this.groupId) {
      return;
    }
    const res = await HttpUtil.get(`/monitors/${this.groupId}`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      this.monitors = listObj.map((item: Record<string, Object>): MonitorInfo => {
        const m = new MonitorInfo();
        m.id = item['id'] as number;
        m.name = item['name'] as string;
        
        let rawUrl = (item['stream_url'] as string || '').trim();
        if (!rawUrl) {
          m.stream_url = '';
        } else if (rawUrl.startsWith('rtsp://') || rawUrl.startsWith('rtmp://')) {
          m.stream_url = `${BASE_HOST}/api/video/live/${m.id}/index.m3u8`;
        } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
          m.stream_url = rawUrl;
        } else {
          m.stream_url = `${BASE_HOST}/api/video/${rawUrl}`;
        }
        return m;
      });
    }
  }

  async submitAddMonitor(name: string, streamUrl: string): Promise<void> {
    if (!name || !streamUrl) {
      promptAction.showToast({ message: '请填写完整信息', duration: 2000 });
      return;
    }
    const payload = new AddMonitorPayload();
    payload.name = name;
    payload.stream_url = streamUrl;
    const res = await HttpUtil.post(`/monitors/${this.groupId}`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '监控添加成功', duration: 2000 });
      this.loadMonitors();
    } else {
      promptAction.showToast({ message: res.message || '添加失败', duration: 2000 });
    }
  }

  build() {
    Column() {
      if (this.selectedMonitorId !== 0) {
        // ---- Detail View ----
        Row() {
          Button('返回')
            .onClick((): void => {
              this.selectedMonitorId = 0;
              this.selectedMonitorName = '';
              this.selectedMonitorUrl = '';
              this.timelineValue = 50;
            })
          Text(this.selectedMonitorName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 10 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(15)

        Stack({ alignContent: Alignment.TopStart }) {
          Video({ src: this.selectedMonitorUrl })
            .width('100%')
            .height(250)
            .autoPlay(true)
            .controls(!this.isLiveStream)
            .objectFit(ImageFit.Contain)
            .onError((): void => {
              promptAction.showToast({ message: '视频流加载失败，监控无画面！', duration: 2000 });
            })

          if (this.isLiveStream) {
            Row() {
              Circle({ width: 8, height: 8 })
                .fill(Color.Red)
                .margin({ right: 6 })
              Text('LIVE 实时直播')
                .fontSize(12)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Bold)
            }
            .backgroundColor('rgba(0, 0, 0, 0.6)')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(12)
            .margin({ left: 15, top: 15 })
          }
        }
        .width('100%')
        .height(250)
        .backgroundColor(Color.Black)

        Text('历史回放时间轴')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20 })

        Row() {
          Text('过去').fontColor(Color.Gray)
          Slider({ value: this.timelineValue, min: 0, max: 100, style: SliderStyle.OutSet })
            .layoutWeight(1)
            .onChange((value: number, mode: SliderChangeMode): void => {
              this.timelineValue = value;
            })
          Text('现在').fontColor(Color.Gray)
        }
        .width('90%')
        .padding(20)

      } else {
        // ---- Grid View ----
        Row() {
          Text('监控列表')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Button('添加监控')
            .onClick((): void => {
              this.addMonitorDialogController.open();
            })
        }
        .width('90%')
        .padding({ top: 20, bottom: 10 })

        if (this.monitors.length === 0) {
          Column() {
            Text('暂无监控，请点击右上角添加')
              .fontSize(16)
              .fontColor(Color.Gray)
              .margin({ top: 80 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Center)
        } else {
          Grid() {
            ForEach(this.monitors, (monitor: MonitorInfo): void => {
              GridItem() {
                Column() {
                  Image($r('app.media.foreground'))
                    .width('100%')
                    .height(100)
                    .objectFit(ImageFit.Cover)
                    .borderRadius({ topLeft: 8, topRight: 8 })
                    .backgroundColor(Color.Gray)
                  Text(monitor.name)
                    .fontSize(14)
                    .padding(8)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
                .backgroundColor(Color.White)
                .borderRadius(8)
                .shadow({ radius: 4, color: '#1A000000' })
                .onClick((): void => {
                  if (!monitor.stream_url) {
                    promptAction.showToast({ message: '该监控设备未配置有效的视频源地址！', duration: 2000 });
                    return;
                  }
                  this.selectedMonitorId = monitor.id;
                  this.selectedMonitorName = monitor.name;
                  this.selectedMonitorUrl = monitor.stream_url.includes('?') ? 
                    `${monitor.stream_url}&t=${Date.now()}` : 
                    `${monitor.stream_url}?t=${Date.now()}`;
                  this.isLiveStream = monitor.stream_url.includes('/live/');
                })
              }
            })
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .padding(10)
          .width('100%')
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
