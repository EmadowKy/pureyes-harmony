import { HttpUtil } from '../../utils/http'
import promptAction from '@ohos.promptAction'

export class MemberInfo {
  emp_id: string = '';
  name: string = '';
  avatar: string = '';
}

@CustomDialog
export struct InviteMemberDialog {
  controller: CustomDialogController
  @State empId: string = '';
  confirm: (empId: string) => void = () => {};

  build() {
    Column({ space: 15 }) {
      Text("邀请新成员入组").fontSize(20).fontWeight(FontWeight.Bold)
      TextInput({ placeholder: "对方的工号", text: this.empId })
        .onChange((val: string): void => {
          this.empId = val;
        }).height(40)
      Row({ space: 20 }) {
        Button("取消").onClick((): void => {
          this.controller.close();
        }).backgroundColor(Color.Gray)
        Button("发送邀请").onClick((): void => {
          this.confirm(this.empId);
          this.controller.close();
        })
      }.margin({ top: 10 })
    }.padding(20).width('90%')
  }
}

@Component
export struct GroupTab {
  @Prop @Watch('onGroupChange') groupId: number = 0;
  @State members: Array<MemberInfo> = [];
  @State isLoading: boolean = false;

  inviteDialogController: CustomDialogController = new CustomDialogController({
    builder: InviteMemberDialog({
      confirm: (empId: string): void => { this.submitInvite(empId); }
    }),
    autoCancel: true
  })

  aboutToAppear(): void {
    this.loadMembers();
  }

  onGroupChange(): void {
    this.loadMembers();
  }

  async loadMembers(): Promise<void> {
    if (!this.groupId) {
      return;
    }
    this.isLoading = true;
    const res = await HttpUtil.get(`/groups/${this.groupId}/members`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      const parsed: Array<MemberInfo> = [];
      for (let i = 0; i < listObj.length; i++) {
        const item = listObj[i];
        const m = new MemberInfo();
        m.emp_id = item['emp_id'] as string;
        m.name = item['name'] as string;
        m.avatar = item['avatar'] as string || '';
        parsed.push(m);
      }
      this.members = parsed;
    } else {
      this.members = [];
    }
    this.isLoading = false;
  }

  async submitInvite(empId: string): Promise<void> {
    if (!empId) {
      return;
    }
    class InvitePayload {
      emp_id: string = '';
    }
    const payload = new InvitePayload();
    payload.emp_id = empId;
    const res = await HttpUtil.post(`/groups/${this.groupId}/invite`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '邀请已发送', duration: 2000 });
      this.loadMembers();
    } else {
      promptAction.showToast({ message: res.message, duration: 2000 });
    }
  }

  build() {
    Column() {
      Row() {
        Text("小组成员").fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button("邀请成员").onClick((): void => {
          this.inviteDialogController.open();
        })
      }.width('90%').padding({ top: 20, bottom: 10 })

      if (this.members.length === 0 && !this.isLoading) {
        Column() {
          Text('暂无成员')
            .fontSize(16)
            .fontColor(Color.Gray)
            .margin({ top: 80 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Start)
      } else {
        List({ space: 10 }) {
          ForEach(this.members, (member: MemberInfo): void => {
            ListItem() {
              Row({ space: 15 }) {
                Image(member.avatar ? member.avatar : $r('app.media.foreground'))
                  .width(50).height(50).borderRadius(25).backgroundColor(Color.Gray)
                Column() {
                  Text(member.name).fontSize(16).fontWeight(FontWeight.Bold)
                  Text(`工号: ${member.emp_id}`).fontSize(14).fontColor(Color.Gray)
                }.alignItems(HorizontalAlign.Start)
              }.width('100%').padding(15).backgroundColor(Color.White).borderRadius(8)
            }
          })
        }.width('90%').layoutWeight(1)
      }
    }
    .width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}
