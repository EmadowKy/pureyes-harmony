import { HttpUtil } from '../utils/http'
import router from '@ohos.router'

@Entry
@Component
struct Login {
  @State empId: string = '';
  @State pass: string = '';
  @State loading: boolean = false;
  @State serverStatus: string = '检查服务器连接中...';
  @State isServerOk: boolean = false;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    this.checkServer();
  }

  async checkServer(): Promise<void> {
    const res = await HttpUtil.get('/health');
    if (res.code === 0) {
      this.serverStatus = '✅ 服务器已连接';
      this.isServerOk = true;
    } else {
      this.serverStatus = '❌ 服务器未连接，请检查模拟器/局域网 IP 设置';
      this.isServerOk = false;
    }
  }

  async handleLogin(): Promise<void> {
    this.errorMsg = '';

    if (this.empId.length === 0 || this.pass.length === 0) {
      this.errorMsg = '请输入工号和密码';
      return;
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
    Column({ space: 20 }) {
      Image($r('app.media.foreground'))
        .width(100)
        .height(100)
        .margin({ top: 92 })
        .backgroundColor($r('app.color.app_card_subtle_bg'))
        .borderRadius(50)

      Text('Pureyes 安防系统')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      Text(this.serverStatus)
        .fontSize(14)
        .fontColor(this.isServerOk ? Color.Green : Color.Red)
        .margin({ bottom: 10 })

      TextInput({ placeholder: '请输入工号 (例如: admin)' })
        .width('80%')
        .height(50)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .borderRadius(10)
        .onChange((val: string): void => {
          this.empId = val;
        })

      TextInput({ placeholder: '请输入密码 (例如: admin)' })
        .type(InputType.Password)
        .width('80%')
        .height(50)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .borderRadius(10)
        .onChange((val: string): void => {
          this.pass = val;
        })

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(14)
          .fontColor(Color.Red)
          .margin({ top: 4 })
      }

      Button(this.loading ? '登录中...' : '登录')
        .width('80%')
        .height(50)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .margin({ top: 20 })
        .enabled(!this.loading)
        .opacity(this.loading ? 0.6 : 1)
        .onClick((): void => {
          this.handleLogin();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
  }
}


