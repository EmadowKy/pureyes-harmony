import { HttpUtil } from '../../utils/http'
import promptAction from '@ohos.promptAction'

export class MemberInfo {
  emp_id: string = '';
  name: string = '';
  phone: string = '';
  avatar: string = '';
  role: string = '';
  status: string = '';
  is_creator: boolean = false;
}

export class GroupDetail {
  id: number = 0;
  name: string = '';
  creator_id: string = '';
  member_count: number = 0;
  pending_count: number = 0;
  is_creator: boolean = false;
}

class InvitePayload {
  emp_id: string = '';
}

class GroupNamePayload {
  name: string = '';
}

@CustomDialog
export struct InviteMemberDialog {
  controller: CustomDialogController
  @State empId: string = '';
  confirm: (empId: string) => void = (_empId: string): void => {};

  build() {
    Column({ space: 15 }) {
      Text('邀请新成员')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '输入对方工号', text: this.empId })
        .onChange((val: string): void => {
          this.empId = val;
        })
        .height(40)

      Row({ space: 20 }) {
        Button('取消')
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)

        Button('发送邀请')
          .onClick((): void => {
            this.confirm(this.empId);
            this.controller.close();
          })
      }
      .margin({ top: 10 })
    }
    .padding(20)
    .width('90%')
  }
}

@CustomDialog
export struct RenameGroupDialog {
  controller: CustomDialogController
  @State groupName: string = '';
  confirm: (name: string) => void = (_name: string): void => {};

  build() {
    Column({ space: 15 }) {
      Text('修改小组名称')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '新的小组名称', text: this.groupName })
        .onChange((val: string): void => {
          this.groupName = val;
        })
        .height(40)

      Row({ space: 20 }) {
        Button('取消')
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)

        Button('保存')
          .onClick((): void => {
            this.confirm(this.groupName);
            this.controller.close();
          })
      }
      .margin({ top: 10 })
    }
    .padding(20)
    .width('90%')
  }
}

@Component
export struct GroupTab {
  @Prop @Watch('onGroupChange') groupId: number = 0;
  @State group: GroupDetail = new GroupDetail();
  @State members: Array<MemberInfo> = [];
  @State isLoading: boolean = false;

  inviteDialogController: CustomDialogController = new CustomDialogController({
    builder: InviteMemberDialog({
      confirm: (empId: string): void => {
        this.submitInvite(empId);
      }
    }),
    autoCancel: true
  })

  renameDialogController: CustomDialogController = new CustomDialogController({
    builder: RenameGroupDialog({
      confirm: (name: string): void => {
        this.renameGroup(name);
      }
    }),
    autoCancel: true
  })

  aboutToAppear(): void {
    this.loadGroup();
  }

  onGroupChange(): void {
    this.loadGroup();
  }

  parseMember(item: Record<string, Object>): MemberInfo {
    const m = new MemberInfo();
    m.emp_id = (item['emp_id'] as string) || '';
    m.name = (item['name'] as string) || '';
    m.phone = (item['phone'] as string) || '';
    m.avatar = (item['avatar'] as string) || '';
    m.role = (item['role'] as string) || '';
    m.status = (item['status'] as string) || 'accepted';
    m.is_creator = (item['is_creator'] as boolean) || false;
    return m;
  }

  async loadGroup(): Promise<void> {
    if (!this.groupId) {
      this.group = new GroupDetail();
      this.members = [];
      return;
    }

    this.isLoading = true;
    const groupRes = await HttpUtil.get(`/groups/${this.groupId}`);
    if (groupRes.code === 0 && groupRes.data) {
      const dataObj = JSON.parse(groupRes.data) as Record<string, Object>;
      const detail = new GroupDetail();
      detail.id = (dataObj['id'] as number) || 0;
      detail.name = (dataObj['name'] as string) || '';
      detail.creator_id = (dataObj['creator_id'] as string) || '';
      detail.member_count = (dataObj['member_count'] as number) || 0;
      detail.pending_count = (dataObj['pending_count'] as number) || 0;
      detail.is_creator = (dataObj['is_creator'] as boolean) || false;
      this.group = detail;
    } else {
      this.group = new GroupDetail();
    }

    await this.loadMembers();
    this.isLoading = false;
  }

  async loadMembers(): Promise<void> {
    if (!this.groupId) {
      this.members = [];
      return;
    }

    const includePending = this.group.is_creator ? '?include_pending=1' : '';
    const res = await HttpUtil.get(`/groups/${this.groupId}/members${includePending}`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const parsed: Array<MemberInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        parsed.push(this.parseMember(listObj[i]));
      }
      this.members = parsed;
    } else {
      this.members = [];
    }
  }

  async submitInvite(empId: string): Promise<void> {
    const targetEmpId = empId.trim();
    if (!targetEmpId) {
      promptAction.showToast({ message: '请输入工号', duration: 2000 });
      return;
    }

    const payload = new InvitePayload();
    payload.emp_id = targetEmpId;
    const res = await HttpUtil.post(`/groups/${this.groupId}/invite`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '邀请已发送', duration: 2000 });
      this.loadGroup();
    } else {
      promptAction.showToast({ message: res.message || '邀请失败', duration: 2000 });
    }
  }

  async renameGroup(name: string): Promise<void> {
    const nextName = name.trim();
    if (!nextName) {
      promptAction.showToast({ message: '请输入小组名称', duration: 2000 });
      return;
    }

    const payload = new GroupNamePayload();
    payload.name = nextName;
    const res = await HttpUtil.put(`/groups/${this.groupId}`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '小组名称已更新', duration: 2000 });
      AppStorage.setOrCreate('refreshGroupFlag', Math.random());
      this.loadGroup();
    } else {
      promptAction.showToast({ message: res.message || '更新失败', duration: 2000 });
    }
  }

  async removeMember(member: MemberInfo): Promise<void> {
    const res = await HttpUtil.del(`/groups/${this.groupId}/members/${member.emp_id}`);
    if (res.code === 0) {
      const label = member.status === 'pending' ? '邀请已撤回' : '成员已移除';
      promptAction.showToast({ message: label, duration: 2000 });
      this.loadGroup();
    } else {
      promptAction.showToast({ message: res.message || '操作失败', duration: 2000 });
    }
  }

  async leaveGroup(): Promise<void> {
    const res = await HttpUtil.post(`/groups/${this.groupId}/leave`);
    if (res.code === 0) {
      promptAction.showToast({ message: '已退出小组', duration: 2000 });
      AppStorage.setOrCreate('currentGroupId', 0);
      AppStorage.setOrCreate('refreshGroupFlag', Math.random());
    } else {
      promptAction.showToast({ message: res.message || '退出失败', duration: 2000 });
    }
  }

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(this.group.name || '小组成员')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
          Text(`${this.group.member_count} 位成员 · ${this.group.pending_count} 个待确认邀请`)
            .fontSize(12)
            .fontColor(Color.Gray)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.group.is_creator) {
          Button('改名')
            .height(36)
            .margin({ right: 8 })
            .onClick((): void => {
              this.renameDialogController.open();
            })

          Button('邀请')
            .height(36)
            .onClick((): void => {
              this.inviteDialogController.open();
            })
        } else if (this.group.id !== 0) {
          Button('退出')
            .height(36)
            .backgroundColor('#D64545')
            .fontColor(Color.White)
            .onClick((): void => {
              this.leaveGroup();
            })
        }
      }
      .width('90%')
      .padding({ top: 20, bottom: 10 })

      if (this.members.length === 0 && !this.isLoading) {
        Column() {
          Text(this.groupId ? '暂无成员' : '请先创建或选择小组')
            .fontSize(16)
            .fontColor(Color.Gray)
            .margin({ top: 80 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
      } else {
        List({ space: 10 }) {
          ForEach(this.members, (member: MemberInfo): void => {
            ListItem() {
              Row({ space: 12 }) {
                Image(member.avatar ? member.avatar : $r('app.media.foreground'))
                  .width(50)
                  .height(50)
                  .borderRadius(25)
                  .backgroundColor(Color.Gray)

                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(member.name || member.emp_id)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                    if (member.is_creator) {
                      Text('组长')
                        .fontSize(12)
                        .fontColor('#2563EB')
                    } else if (member.status === 'pending') {
                      Text('待确认')
                        .fontSize(12)
                        .fontColor('#B45309')
                    }
                  }

                  Text(`工号: ${member.emp_id}`)
                    .fontSize(13)
                    .fontColor(Color.Gray)
                  Text(member.phone ? `手机: ${member.phone}` : `角色: ${member.role}`)
                    .fontSize(13)
                    .fontColor(Color.Gray)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.group.is_creator && !member.is_creator) {
                  Button(member.status === 'pending' ? '撤回' : '移除')
                    .height(32)
                    .backgroundColor('#F3F4F6')
                    .fontColor('#B91C1C')
                    .onClick((): void => {
                      this.removeMember(member);
                    })
                }
              }
              .width('100%')
              .padding(15)
              .backgroundColor(Color.White)
              .borderRadius(8)
            }
          })
        }
        .width('90%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
