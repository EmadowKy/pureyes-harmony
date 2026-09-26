import { MonitorTab } from './tabs/MonitorTab'
import { WorkspaceTab } from './tabs/WorkspaceTab'
import { GroupTab } from './tabs/GroupTab'
import { ProfileTab } from './tabs/ProfileTab'
import { HttpResult, HttpUtil, getBaseUrl } from '../utils/http'
import { SecurityUtil } from '../utils/security'
import { common } from '@kit.AbilityKit';

export class GroupInfo {
  id: number = 0;
  name: string = '';
}

export class SelectItem {
  value: string = '';
}

enum NavIconType {
  Monitor,
  Workspace,
  Group,
  Profile
}

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @StorageLink('currentGroupId') currentGroupId: number = 0; 
  @StorageLink('refreshGroupFlag') @Watch('onRefreshFlagChange') refreshGroupFlag: number = 0;
  @StorageLink('session_check_flag') @Watch('onSessionCheck') sessionCheckFlag: number = 0;
  @StorageLink('widget_route') @Watch('onWidgetRoute') widgetRoute: string = '';
  @State groups: Array<GroupInfo> = [];
  @State sessionState: string = 'checking';
  @State sessionMessage: string = '';
  private tabsController: TabsController = new TabsController();
  private checkingSession: boolean = false;

  aboutToAppear(): void {
    this.verifySession();
  }

  onSessionCheck(): void {
    this.verifySession();
  }

  onWidgetRoute(): void {
    if (this.sessionState === 'ready') this.openWidgetTarget();
  }

  private openWidgetTarget(): void {
    if (!this.widgetRoute || this.sessionState !== 'ready') return;
    let workspaceId = 0;
    let conversationId = '';
    try {
      const target = JSON.parse(this.widgetRoute) as Record<string, Object>;
      workspaceId = target['workspaceId'] as number;
      conversationId = (target['conversationId'] as string) || '';
    } catch (_error) {
      // Invalid widget payload falls back to the workspace list.
    }
    this.widgetRoute = '';
    if (!Number.isSafeInteger(workspaceId) || workspaceId <= 0) {
      this.currentIndex = 1;
      this.tabsController.changeIndex(1);
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/WorkspaceDetail',
      params: { workspaceId, workspaceName: '工作区', conversationId }
    }).catch((error: Object): void => {
      console.warn('[InvestigationCard] navigation failed', JSON.stringify(error));
    });
  }

  private openLogin(): void {
    try {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' });
    } catch (error) {
      this.sessionState = 'offline';
      this.sessionMessage = '无法打开登录页，请重试';
      console.warn('[Navigation] Failed to open login page:', JSON.stringify(error));
    }
  }

  async verifySession(): Promise<void> {
    if (this.checkingSession) return;
    this.checkingSession = true;
    this.sessionState = 'checking';
    this.sessionMessage = '';
    const token = AppStorage.get<string>('access_token');
    const savedServer = AppStorage.get<string>('session_server_url') || '';
    if (!token || savedServer !== getBaseUrl().replace(/\/+$/, '')) {
      if (token) {
        AppStorage.setOrCreate('login_notice', savedServer ?
          '服务器地址已更改，请重新登录' : '登录状态升级后需重新登录一次');
      }
      await SecurityUtil.clearSession(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.checkingSession = false;
      this.openLogin();
      return;
    }
    let res: HttpResult = await HttpUtil.get('/users/me');
    if (res.httpStatus === 401) {
      const refreshToken = AppStorage.get<string>('refresh_token') || '';
      if (refreshToken) {
        const refreshed = await HttpUtil.postWithToken('/auth/refresh', refreshToken);
        if (refreshed.code === 0 && refreshed.data) {
          try {
            const payload = JSON.parse(refreshed.data) as Record<string, Object>;
            const newToken = payload['access_token'] as string;
            if (newToken) {
              AppStorage.setOrCreate('access_token', newToken);
              await SecurityUtil.setSecureProp('access_token', newToken);
              res = await HttpUtil.get('/users/me');
            } else {
              res = refreshed;
              res.message = '服务器未返回有效的续期凭据';
            }
          } catch (error) {
            res = refreshed;
            res.message = '服务器返回的续期凭据无法读取';
          }
        } else {
          res = refreshed;
        }
      }
    }
    if (res.httpStatus === 200 && res.code === 0 && res.data) {
      this.sessionState = 'ready';
      this.checkingSession = false;
      this.loadGroups();
      this.openWidgetTarget();
      return;
    }
    if (res.httpStatus === 401 || res.httpStatus === 403 || res.code === 2002) {
      AppStorage.setOrCreate('login_notice', '登录已过期或账号不可用，请重新登录');
      await SecurityUtil.clearSession(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.checkingSession = false;
      this.openLogin();
      return;
    }
    this.sessionState = 'offline';
    this.sessionMessage = res.message || '服务器暂时不可用，请检查网络和服务器地址';
    this.checkingSession = false;
  }

  onRefreshFlagChange(): void {
    if (this.sessionState === 'ready') this.loadGroups();
  }

  async loadGroups() {
    const res = await HttpUtil.get('/groups/');
    if (res.code === 0 && res.data) {
      const groupList = JSON.parse(res.data) as Array<Record<string, Object>>;
      this.groups = groupList.map((g: Record<string, Object>) => {
        const info = new GroupInfo();
        info.id = g['id'] as number;
        info.name = g['name'] as string;
        return info;
      });
      
      if (this.groups.length > 0 && this.currentGroupId === 0) {
        this.currentGroupId = this.groups[0].id;
      }
    } else if (res.httpStatus === 0 || res.httpStatus === 401 || res.httpStatus === 403) {
      this.sessionState = 'offline';
      this.sessionMessage = res.message || '连接已中断，请重试';
    }
  }

  @Builder TopNavigation() {
    Row({ space: 12 }) {
      Stack() {
        Image($r('app.media.business_monitor'))
          .width(30)
          .height(30)
          .objectFit(ImageFit.Contain)
      }
      .width(42)
      .height(42)
      .backgroundColor($r('app.color.app_card_subtle_bg'))
      .border({ width: 1, color: $r('app.color.app_border') })
      .borderRadius(10)

      Column({ space: 0 }) {
        Text('当前调查组')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_muted'))
          .letterSpacing(0.4)

        Select(this.groups.map(g => {
          const item = new SelectItem();
          item.value = g.name;
          return item as SelectOption;
        }))
          .selected(this.groups.findIndex(g => g.id === this.currentGroupId) >= 0 ? this.groups.findIndex(g => g.id === this.currentGroupId) : 0)
          .value(this.groups.find(g => g.id === this.currentGroupId)?.name || '选择小组')
          .font({ size: 19, weight: FontWeight.Bold })
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor(Color.Transparent)
          .onSelect((index: number, value: string) => {
            if (this.groups[index]) {
              this.currentGroupId = this.groups[index].id;
            }
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 6 }) {
        Blank()
          .width(7)
          .height(7)
          .backgroundColor($r('app.color.app_success'))
          .borderRadius(4)
        Text('会话已验证')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_secondary'))
      }
      .padding({ left: 9, right: 9, top: 7, bottom: 7 })
      .border({ width: 1, color: $r('app.color.app_border') })
      .borderRadius(8)
    }
    .width('100%')
    .height(72)
    .padding({ left: 18, right: 18 })
    .backgroundColor($r('app.color.app_top_bar_bg'))
    .border({ width: { bottom: 1 }, color: $r('app.color.app_border') })
  }

  @Builder NavIcon(iconType: NavIconType, isSelected: boolean) {
    if (iconType === NavIconType.Monitor) {
      Image($r('app.media.business_monitor'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .opacity(isSelected ? 1 : 0.52)
    } else if (iconType === NavIconType.Workspace) {
      Image($r('app.media.business_workspace'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .opacity(isSelected ? 1 : 0.52)
    } else if (iconType === NavIconType.Group) {
      Image($r('app.media.business_team'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .opacity(isSelected ? 1 : 0.52)
    } else {
      SymbolGlyph($r('sys.symbol.person'))
        .fontSize(21)
        .fontColor([isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon')])
    }
  }

  @Builder NavBarItem(index: number, label: string, iconType: NavIconType) {
    Column({ space: 0 }) {
      Blank()
        .width(26)
        .height(3)
        .backgroundColor(this.currentIndex === index ? $r('app.color.app_accent') : Color.Transparent)

      Stack() {
        this.NavIcon(iconType, this.currentIndex === index)
      }
      .width(46)
      .height(34)
      .margin({ top: 4 })

      Text(label)
        .fontSize(11)
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentIndex === index ? $r('app.color.app_nav_text_selected') : $r('app.color.app_nav_text'))
    }
    .width('100%')
    .height(64)
    .justifyContent(FlexAlign.Start)
    .onClick((): void => {
      this.currentIndex = index;
      this.tabsController.changeIndex(index);
    })
  }

  build() {
    if (this.sessionState !== 'ready') {
      Column({ space: 16 }) {
        Image($r('app.media.foreground'))
          .width(64)
          .height(64)
          .borderRadius(16)
        Text(this.sessionState === 'checking' ? '正在验证登录状态…' : '暂时无法连接工作台')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
        Text(this.sessionState === 'checking' ? '正在与服务器确认账号，请稍候' : this.sessionMessage)
          .fontSize(13)
          .fontColor($r('app.color.app_text_secondary'))
          .textAlign(TextAlign.Center)
          .width('82%')
        if (this.sessionState === 'offline') {
          Button('重试连接')
            .onClick((): void => { this.verifySession(); })
          Button('切换账号或服务器')
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.app_primary'))
            .onClick((): void => { this.openLogin(); })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.app_page_bg'))
    } else {
      Column() {
        this.TopNavigation()

        Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
          TabContent() {
            MonitorTab({ groupId: this.currentGroupId })
          }.tabBar(this.NavBarItem(0, '监控', NavIconType.Monitor))

          TabContent() {
            WorkspaceTab({ groupId: this.currentGroupId })
          }.tabBar(this.NavBarItem(1, '工作区', NavIconType.Workspace))

          TabContent() {
            GroupTab({ groupId: this.currentGroupId })
          }.tabBar(this.NavBarItem(2, '小组', NavIconType.Group))

          TabContent() {
            ProfileTab()
          }.tabBar(this.NavBarItem(3, '我的', NavIconType.Profile))
        }
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .barHeight(66)
        .barBackgroundColor($r('app.color.app_nav_bar_bg'))
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_page_bg'))
    }
  }
}
