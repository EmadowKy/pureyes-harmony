import { MonitorTab } from './tabs/MonitorTab'
import { WorkspaceTab } from './tabs/WorkspaceTab'
import { GroupTab } from './tabs/GroupTab'
import { ProfileTab } from './tabs/ProfileTab'
import { HttpUtil } from '../utils/http'

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
  @State groups: Array<GroupInfo> = [];
  private tabsController: TabsController = new TabsController();

  aboutToAppear() {
    const token = AppStorage.get<string>('access_token');
    if (!token) {
      try {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' });
      } catch (error) {
        console.warn('[Navigation] Failed to open login page:', JSON.stringify(error));
      }
      return;
    }
    this.loadGroups();
  }

  onRefreshFlagChange() {
    this.loadGroups();
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
        Text('服务在线')
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
