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
export struct RenameGroupDialog {
  controller: CustomDialogController
  @State groupName: string = '';
  confirm: (name: string) => void = (_name: string): void => {};

  build() {
    Column({ space: 15 }) {
      Text('修改小组名称')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      TextInput({ placeholder: '新的小组名称', text: this.groupName })
        .onChange((val: string): void => {
          this.groupName = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .border({ width: 1, color: $r('app.color.app_border') })
        .borderRadius(8)

      Row({ space: 20 }) {
        Button('取消')
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .fontColor($r('app.color.app_text_primary'))
          .border({ width: 1, color: $r('app.color.app_border') })

        Button('保存')
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.confirm(this.groupName);
            this.controller.close();
          })
      }
      .margin({ top: 10 })
    }
    .padding(20)
    .width('90%')
    .backgroundColor($r('app.color.app_card_bg'))
    .border({ width: 1, color: $r('app.color.app_border') })
    .borderRadius(8)
  }
}

@Component
export struct GroupTab {
  @Prop @Watch('onGroupChange') groupId: number = 0;
  @State group: GroupDetail = new GroupDetail();
  @State members: Array<MemberInfo> = [];
  @State inviteCandidates: Array<MemberInfo> = [];
  @State selectedMember: MemberInfo = new MemberInfo();
  @State inviteKeyword: string = '';
  @State selectedInviteEmpId: string = '';
  @State showMemberDetail: boolean = false;
  @State isLoading: boolean = false;

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
    this.resetInviteState();
    this.closeMemberDetail();
    this.loadGroup();
  }

  resetInviteState(): void {
    this.inviteKeyword = '';
    this.selectedInviteEmpId = '';
    this.inviteCandidates = [];
  }

  roleLabel(role: string): string {
    if (role === 'super_admin') {
      return '超级管理员';
    }
    if (role === 'admin') {
      return '管理员';
    }
    return '普通用户';
  }

  statusLabel(member: MemberInfo): string {
    if (member.is_creator) {
      return '组长';
    }
    if (member.status === 'pending') {
      return '待确认';
    }
    return '成员';
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

  isKnownMember(empId: string): boolean {
    for (let i = 0; i < this.members.length; i++) {
      if (this.members[i].emp_id === empId) {
        return true;
      }
    }
    return false;
  }

  async loadGroup(): Promise<void> {
    if (!this.groupId) {
      this.group = new GroupDetail();
      this.members = [];
      this.resetInviteState();
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

  async searchInviteCandidates(keyword: string): Promise<void> {
    this.inviteKeyword = keyword;
    this.selectedInviteEmpId = '';

    const nextKeyword = keyword.trim();
    if (!this.group.is_creator || !nextKeyword) {
      this.inviteCandidates = [];
      return;
    }

    const res = await HttpUtil.get(`/users/search?keyword=${encodeURIComponent(nextKeyword)}`);
    if (this.inviteKeyword.trim() !== nextKeyword) {
      return;
    }

    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const candidates: Array<MemberInfo> = [];
      for (let i = 0; i < listObj.length && candidates.length < 5; i++) {
        const candidate = this.parseMember(listObj[i]);
        if (candidate.emp_id && !this.isKnownMember(candidate.emp_id)) {
          candidates.push(candidate);
        }
      }
      this.inviteCandidates = candidates;
    } else {
      this.inviteCandidates = [];
    }
  }

  selectInviteCandidate(candidate: MemberInfo): void {
    this.selectedInviteEmpId = candidate.emp_id;
    this.inviteKeyword = candidate.emp_id;
    this.inviteCandidates = [candidate];
  }

  async submitInvite(empId?: string): Promise<void> {
    if (!this.group.is_creator) {
      promptAction.showToast({ message: '只有组长可以邀请成员', duration: 2000 });
      return;
    }

    const targetEmpId = (empId || this.selectedInviteEmpId || this.inviteKeyword).trim();
    if (!targetEmpId) {
      promptAction.showToast({ message: '请输入工号', duration: 2000 });
      return;
    }

    const payload = new InvitePayload();
    payload.emp_id = targetEmpId;
    const res = await HttpUtil.post(`/groups/${this.groupId}/invite`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '邀请已发送', duration: 2000 });
      this.resetInviteState();
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

  openMemberDetail(member: MemberInfo): void {
    this.selectedMember = member;
    this.showMemberDetail = true;
  }

  closeMemberDetail(): void {
    this.selectedMember = new MemberInfo();
    this.showMemberDetail = false;
  }

  @Builder DetailRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .width(70)
        .fontSize(13)
        .fontColor($r('app.color.app_text_secondary'))

      Text(value.length > 0 ? value : '未填写')
        .fontSize(14)
        .fontColor($r('app.color.app_text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.app_card_subtle_bg'))
    .border({ width: 1, color: $r('app.color.app_border') })
    .borderRadius(8)
  }

  @Builder MemberDetailOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.closeMemberDetail();
        })

      Column({ space: 14 }) {
        Row({ space: 12 }) {
          Image(this.selectedMember.avatar ? this.selectedMember.avatar : $r('app.media.foreground'))
            .width(58)
            .height(58)
            .borderRadius(29)
            .backgroundColor($r('app.color.app_card_subtle_bg'))

          Column({ space: 4 }) {
            Text(this.selectedMember.name || this.selectedMember.emp_id)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
            Text(this.statusLabel(this.selectedMember))
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('关闭')
            .height(34)
            .backgroundColor($r('app.color.app_card_subtle_bg'))
            .fontColor($r('app.color.app_text_primary'))
            .onClick((): void => {
              this.closeMemberDetail();
            })
        }
        .width('100%')

        Column({ space: 8 }) {
          this.DetailRow('工号', this.selectedMember.emp_id)
          this.DetailRow('姓名', this.selectedMember.name)
          this.DetailRow('手机号', this.selectedMember.phone)
          this.DetailRow('头像', this.selectedMember.avatar ? '已上传' : '未设置')
        }
        .width('100%')
      }
      .width('88%')
      .padding(16)
      .backgroundColor($r('app.color.app_card_bg'))
      .border({ width: 1, color: $r('app.color.app_border') })
      .borderRadius(8)
    }
    .width('100%')
    .height('100%')
  }

  @Builder InvitePanel() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text('邀请成员')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('发送')
          .height(36)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.submitInvite();
          })
      }
      .width('100%')

      TextInput({ placeholder: '输入工号、姓名或手机号', text: this.inviteKeyword })
        .width('100%')
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .border({ width: 1, color: $r('app.color.app_border') })
        .borderRadius(8)
        .onChange((val: string): void => {
          this.searchInviteCandidates(val);
        })

      if (this.inviteKeyword.trim().length > 0 && this.inviteCandidates.length === 0) {
        Text('暂无候选')
          .width('100%')
          .fontSize(13)
          .fontColor($r('app.color.app_text_secondary'))
          .padding({ top: 4, bottom: 4 })
      }

      ForEach(this.inviteCandidates, (candidate: MemberInfo): void => {
        Row({ space: 10 }) {
          Image(candidate.avatar ? candidate.avatar : $r('app.media.foreground'))
            .width(38)
            .height(38)
            .borderRadius(19)
            .backgroundColor($r('app.color.app_card_subtle_bg'))

          Column({ space: 2 }) {
            Text(candidate.name || candidate.emp_id)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary'))
            Text(`工号: ${candidate.emp_id}`)
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.selectedInviteEmpId === candidate.emp_id ? '已选择' : '选择')
            .width(64)
            .height(32)
            .fontSize(12)
            .padding({ left: 0, right: 0 })
            .backgroundColor(this.selectedInviteEmpId === candidate.emp_id ? $r('app.color.app_primary_soft') : $r('app.color.app_primary'))
            .fontColor(this.selectedInviteEmpId === candidate.emp_id ? $r('app.color.app_primary') : Color.White)
            .onClick((): void => {
              this.selectInviteCandidate(candidate);
            })
        }
        .width('100%')
        .padding(10)
        .backgroundColor($r('app.color.app_card_subtle_bg'))
        .border({ width: 1, color: $r('app.color.app_border') })
        .borderRadius(8)
      })
    }
    .width('90%')
    .padding(14)
    .backgroundColor($r('app.color.app_card_bg'))
    .border({ width: 1, color: $r('app.color.app_border') })
    .borderRadius(8)
  }

  @Builder MemberList() {
    Column({ space: 10 }) {
      Row() {
        Text('成员')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .layoutWeight(1)

        Button('刷新')
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .fontColor($r('app.color.app_text_primary'))
          .border({ width: 1, color: $r('app.color.app_border') })
          .onClick((): void => {
            this.loadGroup();
          })
      }
      .width('90%')

      List({ space: 10 }) {
        ForEach(this.members, (member: MemberInfo): void => {
          ListItem() {
            Row({ space: 12 }) {
              Image(member.avatar ? member.avatar : $r('app.media.foreground'))
                .width(50)
                .height(50)
                .borderRadius(25)
                .backgroundColor($r('app.color.app_card_subtle_bg'))
                .onClick((): void => {
                  this.openMemberDetail(member);
                })

              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Text(member.name || member.emp_id)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))

                  Text(this.statusLabel(member))
                    .fontSize(12)
                    .fontColor(member.status === 'pending' ? '#B45309' : $r('app.color.app_primary'))
                    .backgroundColor($r('app.color.app_primary_soft'))
                    .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                    .borderRadius(8)
                }

                Text(`工号: ${member.emp_id}`)
                  .fontSize(13)
                  .fontColor($r('app.color.app_text_secondary'))
                Text(member.phone ? `手机: ${member.phone}` : `身份: ${this.roleLabel(member.role)}`)
                  .fontSize(13)
                  .fontColor($r('app.color.app_text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .onClick((): void => {
                this.openMemberDetail(member);
              })

              Column({ space: 8 }) {
                Button('查看')
                  .height(32)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor($r('app.color.app_primary_soft'))
                  .fontColor($r('app.color.app_primary'))
                  .onClick((): void => {
                    this.openMemberDetail(member);
                  })

                if (this.group.is_creator && !member.is_creator) {
                  Button(member.status === 'pending' ? '撤回' : '移除')
                    .height(32)
                    .padding({ left: 12, right: 12 })
                    .backgroundColor($r('app.color.app_card_subtle_bg'))
                    .fontColor('#B91C1C')
                    .border({ width: 1, color: $r('app.color.app_border') })
                    .onClick((): void => {
                      this.removeMember(member);
                    })
                }
              }
            }
            .width('100%')
            .padding(15)
            .backgroundColor($r('app.color.app_card_bg'))
            .border({ width: 1, color: $r('app.color.app_border') })
            .borderRadius(8)
          }
        })
      }
      .width('90%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        Row() {
          Column({ space: 4 }) {
            Text(this.group.name || '小组成员')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
            Text(`成员 ${this.group.member_count} · 待确认 ${this.group.pending_count}`)
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.group.is_creator) {
            Button('改名')
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.app_primary_soft'))
              .fontColor($r('app.color.app_primary'))
              .onClick((): void => {
                this.renameDialogController.open();
              })
          } else if (this.group.id !== 0) {
            Button('退出')
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.app_card_bg'))
              .fontColor($r('app.color.app_danger'))
              .border({ width: 1, color: $r('app.color.app_danger') })
              .onClick((): void => {
                this.leaveGroup();
              })
          }
        }
        .width('90%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .backgroundColor($r('app.color.app_card_bg'))
        .border({ width: 1, color: $r('app.color.app_border') })
        .borderRadius(8)
        .margin({ top: 18 })

        if (this.group.is_creator && this.group.id !== 0) {
          this.InvitePanel()
        }

        if (this.members.length === 0 && !this.isLoading) {
          Column() {
            Text(this.groupId ? '暂无成员' : '请先创建或选择小组')
              .fontSize(16)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .width('90%')
          .padding(28)
          .backgroundColor($r('app.color.app_card_bg'))
          .border({ width: 1, color: $r('app.color.app_border') })
          .borderRadius(8)
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)
        } else {
          this.MemberList()
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.app_page_bg'))

      if (this.showMemberDetail) {
        this.MemberDetailOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
