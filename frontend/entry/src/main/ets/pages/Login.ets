import { HttpUtil, updateBaseHost, OFFICIAL_SERVER_URL } from '../utils/http'
import { SecurityUtil } from '../utils/security'

@Entry
@Component
struct Login {
  @State empId: string = '';
  @State pass: string = '';
  @State loading: boolean = false;
  
  // 使用 StorageLink 进行鸿蒙本地磁盘持久化存储双向绑定
  @StorageLink('is_custom_server') isCustomServer: boolean = false;
  @StorageLink('custom_server_url') customServerUrlStorage: string = '';
  
  @State serverUrl: string = OFFICIAL_SERVER_URL;
  @State testingServer: boolean = false;
  @State testResultText: string = '';
  @State isTestSuccess: boolean = false;
  
  @State isServerOk: boolean = false;
  @State errorMsg: string = '';

  async aboutToAppear(): Promise<void> {
    await SecurityUtil.initSecureState();
    this.serverUrl = this.isCustomServer && this.customServerUrlStorage.trim().length > 0 ?
      this.customServerUrlStorage : OFFICIAL_SERVER_URL;
    this.applyCurrentServerConfig();
    this.testConnection();
  }

  async testConnection(): Promise<void> {
    if (this.testingServer) {
      return;
    }
    this.testingServer = true;
    this.testResultText = '正在测试服务器连接...';
    this.isTestSuccess = false;

    const targetUrl = this.isCustomServer ? this.serverUrl : OFFICIAL_SERVER_URL;
    const res = await HttpUtil.testServerUrl(targetUrl);
    
    this.testingServer = false;
    this.testResultText = res.message;
    this.isTestSuccess = res.success;
    this.isServerOk = res.success;
  }

  applyCurrentServerConfig(): void {
    if (this.isCustomServer) {
      const cleanUrl = (this.serverUrl || '').trim();
      this.customServerUrlStorage = cleanUrl;
      AppStorage.setOrCreate('is_custom_server', true);
      AppStorage.setOrCreate('custom_server_url', cleanUrl);
      SecurityUtil.setSecureProp('custom_server_url', cleanUrl);
      SecurityUtil.setSecureProp('is_custom_server', 'true');
    } else {
      this.serverUrl = OFFICIAL_SERVER_URL;
      AppStorage.setOrCreate('is_custom_server', false);
      SecurityUtil.setSecureProp('is_custom_server', 'false');
    }
    updateBaseHost();
  }

  async handleLogin(): Promise<void> {
    this.errorMsg = '';
    
    // 点击登录的第一时间，无缝同步更新保存当前页面的服务器地址配置
    this.applyCurrentServerConfig();

    if (this.empId.length === 0 || this.pass.length === 0) {
      this.errorMsg = '请输入工号和密码';
      return;
    }

    if (!this.isServerOk) {
      await this.testConnection();
      if (!this.isServerOk) {
        this.errorMsg = '服务器未连接，暂时无法登录';
        return;
      }
    }

    class LoginPayload {
      emp_id: string = '';
      password: string = '';
    }

    const payload = new LoginPayload();
    payload.emp_id = this.empId;
    payload.password = this.pass;

    this.loading = true;
    const res = await HttpUtil.post('/auth/login', payload);
    this.loading = false;

    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      const token = dataObj['access_token'] as string;
      AppStorage.setOrCreate('access_token', token);
      await SecurityUtil.setSecureProp('access_token', token);
      try {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
      } catch (error) {
        this.errorMsg = '登录成功，但页面跳转失败，请重试';
        console.warn('[Navigation] Failed to open workspace:', JSON.stringify(error));
      }
    } else {
      this.errorMsg = res.message.length > 0 ? res.message : '工号或密码错误';
    }
  }

  build() {
    Scroll() {
      Column() {
        Column({ space: 18 }) {
          Row({ space: 14 }) {
            Image($r('app.media.foreground'))
              .width(58)
              .height(58)
              .borderRadius(14)
              .objectFit(ImageFit.Cover)
              .backgroundColor($r('app.color.app_card_bg'))
              .border({ width: 1, color: $r('app.color.app_border') })

            Column({ space: 2 }) {
              Text('PUREYES')
                .fontSize(29)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_text_primary'))
                .letterSpacing(1.2)

              Text('视频调查工作台')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.app_text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('接入视频')
              .fontSize(11)
              .fontColor($r('app.color.app_text_muted'))
            Blank().height(1).layoutWeight(1).backgroundColor($r('app.color.app_track'))
            Text('提取片段')
              .fontSize(11)
              .fontColor($r('app.color.app_text_muted'))
            Blank().height(1).layoutWeight(1).backgroundColor($r('app.color.app_track'))
            Text('验证线索')
              .fontSize(11)
              .fontColor($r('app.color.app_text_muted'))
          }
          .width('100%')
        }
        .width('90%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 52, bottom: 30 })

        Column({ space: 14 }) {
          Row() {
            Column({ space: 3 }) {
              Text('欢迎回来')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_text_primary'))
              Text('使用你的员工账号进入视频工作台')
                .fontSize(13)
                .fontColor($r('app.color.app_text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Row({ space: 6 }) {
              Blank()
                .width(7)
                .height(7)
                .backgroundColor(this.isTestSuccess ? $r('app.color.app_success') : $r('app.color.app_danger'))
                .borderRadius(4)
              Text(this.testingServer ? '检测中' : (this.isTestSuccess ? '已连接' : '未连接'))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.app_text_secondary'))
            }
            .padding({ left: 8, right: 8, top: 5, bottom: 5 })
            .border({ width: 1, color: $r('app.color.app_border') })
            .borderRadius(6)
          }
          .width('100%')

          if (this.isCustomServer) {
            Column({ space: 6 }) {
              Text('服务器地址')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.app_text_secondary'))
                .width('100%')

              Row() {
                TextInput({ placeholder: 'https://example.com', text: this.serverUrl })
                  .layoutWeight(1)
                  .height(46)
                  .fontColor($r('app.color.app_text_primary'))
                  .backgroundColor(Color.Transparent)
                  .onChange((val: string): void => {
                    this.serverUrl = val;
                    this.customServerUrlStorage = val;
                  })

                Button() {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(18)
                    .fontColor([this.testingServer ? $r('app.color.app_text_muted') : $r('app.color.app_primary')])
                }
                .width(40)
                .height(40)
                .padding(0)
                .backgroundColor(Color.Transparent)
                .border({ width: 1, color: $r('app.color.app_border') })
                .borderRadius(8)
                .onClick((): void => {
                  this.testConnection();
                })
              }
              .height(48)
              .backgroundColor($r('app.color.app_input_bg'))
              .border({ width: 1, color: $r('app.color.app_border') })
              .borderRadius(8)
              .padding({ left: 4, right: 4 })
            }
            .width('100%')
          }

          Column({ space: 6 }) {
            Text('工号')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_secondary'))
              .width('100%')
            TextInput({ placeholder: '请输入工号', text: this.empId })
              .width('100%')
              .height(48)
              .fontColor($r('app.color.app_text_primary'))
              .backgroundColor($r('app.color.app_input_bg'))
              .border({ width: 1, color: $r('app.color.app_border') })
              .borderRadius(8)
              .contentType(ContentType.USER_NAME)
              .onChange((val: string): void => {
                this.empId = val;
              })
          }
          .width('100%')

          Column({ space: 6 }) {
            Text('密码')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_secondary'))
              .width('100%')
            TextInput({ placeholder: '请输入密码', text: this.pass })
              .type(InputType.Password)
              .width('100%')
              .height(48)
              .fontColor($r('app.color.app_text_primary'))
              .backgroundColor($r('app.color.app_input_bg'))
              .border({ width: 1, color: $r('app.color.app_border') })
              .borderRadius(8)
              .contentType(ContentType.PASSWORD)
              .onChange((val: string): void => {
                this.pass = val;
              })
          }
          .width('100%')

          if (this.errorMsg.length > 0) {
            Row({ space: 7 }) {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(15)
                .fontColor([$r('app.color.app_danger')])
              Text(this.errorMsg)
                .fontSize(13)
                .fontColor($r('app.color.app_danger'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 11, right: 11, top: 9, bottom: 9 })
            .backgroundColor($r('app.color.app_accent_soft'))
            .borderRadius(6)
          }

          Button() {
            Row({ space: 10 }) {
              Blank()
                .width(3)
                .height(22)
                .backgroundColor($r('app.color.app_accent'))

              Text(this.loading ? '正在登录…' : '进入工作台')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_text_on_inverted'))

              Blank()

              SymbolGlyph($r('sys.symbol.arrowshape_right_fill'))
                .fontSize(16)
                .fontColor([$r('app.color.app_text_on_inverted')])
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
          }
            .width('100%')
            .height(50)
            .padding(0)
            .backgroundColor($r('app.color.app_surface_inverted'))
            .borderRadius(8)
            .enabled(!this.loading && !this.testingServer)
            .opacity((this.loading || this.testingServer) ? 0.6 : 1)
            .onClick((): void => {
              this.handleLogin();
            })

          Row({ space: 8 }) {
            Image($r('app.media.business_secure_server'))
              .width(28)
              .height(28)
              .objectFit(ImageFit.Contain)
            Column({ space: 1 }) {
              Text(this.isCustomServer ? '自定义服务器' : '官方服务器')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.app_text_primary'))
              Text(this.isCustomServer ? '切换回官方服务' : '切换到本地或私有服务')
                .fontSize(11)
                .fontColor($r('app.color.app_text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([$r('app.color.app_text_muted')])
          }
          .width('100%')
          .padding({ left: 2, right: 2, top: 12, bottom: 4 })
          .border({ width: { top: 1 }, color: $r('app.color.app_border') })
          .onClick((): void => {
            this.isCustomServer = !this.isCustomServer;
            if (!this.isCustomServer) {
              this.applyCurrentServerConfig();
            } else {
              if (!this.serverUrl || this.serverUrl === OFFICIAL_SERVER_URL) {
                this.serverUrl = this.customServerUrlStorage && this.customServerUrlStorage.trim().length > 0 ?
                  this.customServerUrlStorage : OFFICIAL_SERVER_URL;
              }
              this.applyCurrentServerConfig();
            }
            this.testConnection();
          })

          if (this.testResultText.length > 0) {
            Text(this.testResultText)
              .fontSize(11)
              .fontColor(this.isTestSuccess ? $r('app.color.app_success') : $r('app.color.app_text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .width('90%')
        .padding(20)
        .backgroundColor($r('app.color.app_card_bg'))
        .border({ width: 1, color: $r('app.color.app_border') })
        .borderRadius(12)
        .margin({ bottom: 30 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
    .scrollable(ScrollDirection.Vertical)
  }
}
