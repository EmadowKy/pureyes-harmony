import { HttpUtil, updateBaseHost, OFFICIAL_SERVER_URL } from '../utils/http'
import router from '@ohos.router'

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

  aboutToAppear(): void {
    if (this.isCustomServer && this.customServerUrlStorage && this.customServerUrlStorage.trim().length > 0) {
      this.serverUrl = this.customServerUrlStorage;
    } else if (this.customServerUrlStorage && this.customServerUrlStorage.trim().length > 0) {
      this.serverUrl = this.customServerUrlStorage;
    } else {
      this.serverUrl = OFFICIAL_SERVER_URL;
    }
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

    if (res.success) {
      if (this.isCustomServer) {
        this.customServerUrlStorage = this.serverUrl;
      }
      updateBaseHost();
    }
  }

  async handleLogin(): Promise<void> {
    this.errorMsg = '';

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
      AppStorage.setOrCreate('access_token', dataObj['access_token'] as string);
      router.replaceUrl({ url: 'pages/Index' });
    } else {
      this.errorMsg = res.message.length > 0 ? res.message : '工号或密码错误';
    }
  }

  build() {
    Column({ space: 16 }) {
      Image($r('app.media.foreground'))
        .width(90)
        .height(90)
        .margin({ top: 60 })
        .backgroundColor($r('app.color.app_card_subtle_bg'))
        .borderRadius(45)

      Text('Pureyes 安防系统')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .margin({ bottom: 10 })

      // 自定义服务器输入栏（当 isCustomServer 为 true 时显示在用户名上方）
      if (this.isCustomServer) {
        Column({ space: 6 }) {
          // 1. 在服务器地址输入框的上方显示测试结果
          if (this.testResultText.length > 0) {
            Text(this.testResultText)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isTestSuccess ? Color.Green : Color.Red)
              .width('80%')
              .textAlign(TextAlign.Start)
          }

          // 2. 服务器地址输入框与右侧测试图标按钮
          Row() {
            TextInput({ placeholder: '请输入服务器地址', text: this.serverUrl })
              .layoutWeight(1)
              .height(50)
              .fontColor($r('app.color.app_text_primary'))
              .backgroundColor(Color.Transparent)
              .onChange((val: string): void => {
                this.serverUrl = val;
                this.customServerUrlStorage = val;
              })

            // 测试图标按钮（点击后进行连通性测试）
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor(this.testingServer ? ['#9CA3AF'] : [$r('app.color.app_primary')])
            }
            .width(44)
            .height(50)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick((): void => {
              this.testConnection();
            })
          }
          .width('80%')
          .height(50)
          .backgroundColor($r('app.color.app_input_bg'))
          .borderRadius(10)
          .padding({ left: 4, right: 4 })
        }
        .width('100%')
      } else {
        // 官方服务器模式下的连接状态显示
        if (this.testResultText.length > 0) {
          Text(this.testResultText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isTestSuccess ? Color.Green : Color.Red)
            .margin({ bottom: 4 })
        }
      }

      // 3. 用户名/工号输入框
      TextInput({ placeholder: '请输入工号 (例如: admin)', text: this.empId })
        .width('80%')
        .height(50)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .borderRadius(10)
        .onChange((val: string): void => {
          this.empId = val;
        })

      // 4. 密码输入框
      TextInput({ placeholder: '请输入密码 (例如: admin)', text: this.pass })
        .type(InputType.Password)
        .width('80%')
        .height(50)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .borderRadius(10)
        .onChange((val: string): void => {
          this.pass = val;
        })

      // 错误提示
      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(14)
          .fontColor(Color.Red)
          .margin({ top: 2 })
      }

      // 登录按钮
      Button(this.loading ? '登录中...' : '登录')
        .width('80%')
        .height(50)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .margin({ top: 10 })
        .enabled(!this.loading && !this.testingServer)
        .opacity((this.loading || this.testingServer) ? 0.6 : 1)
        .onClick((): void => {
          this.handleLogin();
        })

      // 5. 登录界面下方的蓝字切换按钮
      Text(this.isCustomServer ? '使用官方服务器' : '使用自定义服务器')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#2563EB')
        .margin({ top: 10 })
        .onClick((): void => {
          this.isCustomServer = !this.isCustomServer;
          if (!this.isCustomServer) {
            // 切回官方服务器
            updateBaseHost();
          } else {
            // 切到自定义服务器
            if (!this.serverUrl || this.serverUrl === OFFICIAL_SERVER_URL) {
              if (this.customServerUrlStorage && this.customServerUrlStorage.trim().length > 0) {
                this.serverUrl = this.customServerUrlStorage;
              } else {
                this.serverUrl = OFFICIAL_SERVER_URL;
              }
            }
          }
          this.testConnection();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
  }
}
