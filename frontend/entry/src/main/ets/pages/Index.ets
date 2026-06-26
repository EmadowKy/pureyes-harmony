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

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @StorageLink('currentGroupId') currentGroupId: number = 0; 
  @StorageLink('refreshGroupFlag') @Watch('onRefreshFlagChange') refreshGroupFlag: number = 0;
  @State groups: Array<GroupInfo> = [];

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
    .backgroundColor('#f8f9fa')
  }

  build() {
    Column() {
      this.TopNavigation()
      
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          MonitorTab({ groupId: this.currentGroupId })
        }.tabBar("监控")

        TabContent() {
          WorkspaceTab({ groupId: this.currentGroupId })
        }.tabBar("工作区")

        TabContent() {
          GroupTab({ groupId: this.currentGroupId })
        }.tabBar("小组")

        TabContent() {
          ProfileTab()
        }.tabBar("我的")
      }
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}