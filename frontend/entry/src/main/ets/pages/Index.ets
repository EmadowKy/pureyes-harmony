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
      import('@ohos.router').then(router => router.default.replaceUrl({ url: 'pages/Login' }));
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
    Row() {
      Select(this.groups.map(g => {
        const item = new SelectItem();
        item.value = g.name;
        return item as SelectOption;
      }))
        .selected(this.groups.findIndex(g => g.id === this.currentGroupId) >= 0 ? this.groups.findIndex(g => g.id === this.currentGroupId) : 0)
        .value(this.groups.find(g => g.id === this.currentGroupId)?.name || "选择小组")
        .font({ size: 20, weight: FontWeight.Bold })
        .onSelect((index: number, value: string) => {
          if (this.groups[index]) {
            this.currentGroupId = this.groups[index].id;
          }
        })
        .layoutWeight(1)
        
      Blank()
      
      Image($r('app.media.foreground'))
        .width(32).height(32).borderRadius(16)
    }
    .width('100%')
    .height(60)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.app_top_bar_bg'))
  }

  @Builder MonitorIcon(isSelected: boolean) {
    Column({ space: 2 }) {
      Blank()
        .width(22)
        .height(14)
        .backgroundColor(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
        .borderRadius(4)
      Row({ space: 2 }) {
        Blank()
          .width(10)
          .height(3)
          .backgroundColor(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
          .borderRadius(2)
        Circle({ width: 4, height: 4 })
          .fill(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
      }
      .justifyContent(FlexAlign.Center)
      .width(22)
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
  }

  @Builder WorkspaceIcon(isSelected: boolean) {
    Column({ space: 4 }) {
      Row({ space: 3 }) {
        Blank()
          .width(8)
          .height(8)
          .backgroundColor(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
          .borderRadius(3)
        Blank()
          .width(8)
          .height(8)
          .backgroundColor(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
          .borderRadius(3)
      }
      Row({ space: 3 }) {
        Blank()
          .width(8)
          .height(8)
          .backgroundColor(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
          .borderRadius(3)
        Blank()
          .width(8)
          .height(8)
          .backgroundColor(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
          .borderRadius(3)
      }
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
  }

  @Builder GroupIcon(isSelected: boolean) {
    Column({ space: 2 }) {
      Row({ space: 1 }) {
        Circle({ width: 7, height: 7 })
          .fill(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
          .opacity(0.75)
        Circle({ width: 10, height: 10 })
          .fill(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
        Circle({ width: 7, height: 7 })
          .fill(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
          .opacity(0.75)
      }
      .alignItems(VerticalAlign.Center)

      Blank()
        .width(23)
        .height(9)
        .backgroundColor(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
        .borderRadius(9)
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
  }

  @Builder ProfileIcon(isSelected: boolean) {
    Column({ space: 3 }) {
      Circle({ width: 10, height: 10 })
        .fill(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
      Blank()
        .width(20)
        .height(10)
        .backgroundColor(isSelected ? $r('app.color.app_nav_icon_selected') : $r('app.color.app_nav_icon'))
        .borderRadius(10)
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
  }

  @Builder NavIcon(iconType: NavIconType, isSelected: boolean) {
    if (iconType === NavIconType.Monitor) {
      this.MonitorIcon(isSelected)
    } else if (iconType === NavIconType.Workspace) {
      this.WorkspaceIcon(isSelected)
    } else if (iconType === NavIconType.Group) {
      this.GroupIcon(isSelected)
    } else {
      this.ProfileIcon(isSelected)
    }
  }

  @Builder NavBarItem(index: number, label: string, iconType: NavIconType) {
    Column({ space: 3 }) {
      Stack() {
        this.NavIcon(iconType, this.currentIndex === index)
      }
      .width(50)
      .height(40)
      .borderRadius(16)
      .backgroundColor(this.currentIndex === index ? $r('app.color.app_nav_item_bg') : Color.Transparent)
      .shadow(this.currentIndex === index ? {
        radius: 14,
        color: $r('app.color.app_nav_shadow'),
        offsetX: 0,
        offsetY: 5
      } : {
        radius: 0,
        color: Color.Transparent,
        offsetX: 0,
        offsetY: 0
      })

      Text(label)
        .fontSize(12)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentIndex === index ? $r('app.color.app_nav_text_selected') : $r('app.color.app_nav_text'))
    }
    .width('100%')
    .height(64)
    .justifyContent(FlexAlign.Center)
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
      .barHeight(74)
      .barBackgroundColor($r('app.color.app_nav_bar_bg'))
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
  }
}
