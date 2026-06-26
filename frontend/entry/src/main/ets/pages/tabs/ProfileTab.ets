import { HttpUtil } from '../../utils/http'
import promptAction from '@ohos.promptAction'
import router from '@ohos.router'

export class UserInfo {
  emp_id: string = '';
  name: string = '';
  avatar: string = '';
  role: string = '';
}

export class InviteInfo {
  group_id: number = 0;
  group_name: string = '';
}

class EditPayload {
  name: string = '';
  password: string = '';
}

class CreateGroupPayload {
  name: string = '';
}

class RespondPayload {
  action: string = '';
}

class CreateUserPayload {
  emp_id: string = '';
  name: string = '';
  password: string = '';
}

@CustomDialog
export struct EditProfileDialog {
  controller: CustomDialogController
  @State name: string = '';
  @State pass: string = '';
  confirm: (name: string, pass: string) => void = (name: string, pass: string): void => {};

  build() {
    Column({ space: 15 }) {
      Text('修改个人资料')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '新姓名', text: this.name })
        .onChange((val: string): void => {
          this.name = val;
        })
        .height(40)

      TextInput({ placeholder: '新密码 (不少于6位，不修改留空)', text: this.pass })
        .type(InputType.Password)
        .onChange((val: string): void => {
          this.pass = val;
        })
        .height(40)

      Row({ space: 20 }) {
        Button('取消')
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)

        Button('确认')
          .onClick((): void => {
            this.confirm(this.name, this.pass);
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
export struct CreateUserDialog {
  controller: CustomDialogController
  @State empId: string = '';
  @State name: string = '';
  @State pass: string = '';
  confirm: (empId: string, name: string, pass: string) => void =
    (empId: string, name: string, pass: string): void => {};

  build() {
    Column({ space: 15 }) {
      Text('创建新用户 (管理面板)')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '新工号', text: this.empId })
        .onChange((val: string): void => {
          this.empId = val;
        })
        .height(40)

      TextInput({ placeholder: '真实姓名', text: this.name })
        .onChange((val: string): void => {
          this.name = val;
        })
        .height(40)

      TextInput({ placeholder: '初始密码', text: this.pass })
        .type(InputType.Password)
        .onChange((val: string): void => {
          this.pass = val;
        })
        .height(40)

      Row({ space: 20 }) {
        Button('取消')
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)

        Button('创建')
          .onClick((): void => {
            this.confirm(this.empId, this.name, this.pass);
            this.controller.close();
          })
          .backgroundColor(Color.Orange)
      }
      .margin({ top: 10 })
    }
    .padding(20)
    .width('90%')
  }
}

@Component
export struct ProfileTab {
  @State user: UserInfo = new UserInfo();
  @State invites: Array<InviteInfo> = [];
  @State newGroupName: string = '';

  editDialogController: CustomDialogController = new CustomDialogController({
    builder: EditProfileDialog({
      name: this.user.name,
      confirm: (name: string, pass: string): void => {
        this.submitEditProfile(name, pass);
      }
    }),
    autoCancel: true
  })

  createUserDialogController: CustomDialogController = new CustomDialogController({
    builder: CreateUserDialog({
      confirm: (empId: string, name: string, pass: string): void => {
        this.submitCreateUser(empId, name, pass);
      }
    }),
    autoCancel: true
  })

  aboutToAppear(): void {
    this.loadProfile();
    this.loadInvites();
  }

  async loadProfile(): Promise<void> {
    const res = await HttpUtil.get('/users/me');
    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      const u = new UserInfo();
      u.emp_id = (dataObj['emp_id'] as string) || '';
      u.name = (dataObj['name'] as string) || '';
      u.avatar = (dataObj['avatar'] as string) || '';
      u.role = (dataObj['role'] as string) || '';
      this.user = u;
    }
  }

  async loadInvites(): Promise<void> {
    const res = await HttpUtil.get('/groups/invites');
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      this.invites = listObj.map((item: Record<string, Object>): InviteInfo => {
        const inv = new InviteInfo();
        inv.group_id = item['group_id'] as number;
        inv.group_name = item['group_name'] as string;
        return inv;
      });
    }
  }

  async respondInvite(groupId: number, action: string): Promise<void> {
    const payload = new RespondPayload();
    payload.action = action;
    const res = await HttpUtil.post(`/groups/${groupId}/respond`, payload);
    if (res.code === 0) {
      const actionLabel: string = action === 'accept' ? '已接受邀请' : '已拒绝邀请';
      promptAction.showToast({ message: actionLabel, duration: 2000 });
      this.loadInvites();
      AppStorage.setOrCreate('refreshGroupFlag', Math.random());
    } else {
      promptAction.showToast({ message: res.message || '操作失败', duration: 2000 });
    }
  }

  async createGroup(): Promise<void> {
    if (!this.newGroupName) {
      promptAction.showToast({ message: '请输入小组名称', duration: 2000 });
      return;
    }
    const payload = new CreateGroupPayload();
    payload.name = this.newGroupName;
    const res = await HttpUtil.post('/groups/', payload);
    if (res.code === 0) {
      this.newGroupName = '';
      promptAction.showToast({ message: '小组创建成功', duration: 2000 });
      AppStorage.setOrCreate('refreshGroupFlag', Math.random());
    } else {
      promptAction.showToast({ message: res.message || '小组创建失败', duration: 2000 });
    }
  }

  async submitEditProfile(name: string, pass: string): Promise<void> {
    const payload = new EditPayload();
    payload.name = name;
    payload.password = pass;
    const res = await HttpUtil.put('/users/me', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '资料修改成功', duration: 2000 });
      this.loadProfile();
    } else {
      promptAction.showToast({ message: res.message || '资料修改失败', duration: 2000 });
    }
  }

  async submitCreateUser(empId: string, name: string, pass: string): Promise<void> {
    const payload = new CreateUserPayload();
    payload.emp_id = empId;
    payload.name = name;
    payload.password = pass;
    const res = await HttpUtil.post('/users/', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '用户创建成功', duration: 2000 });
    } else {
      promptAction.showToast({ message: res.message || '用户创建失败', duration: 2000 });
    }
  }

  handleLogout(): void {
    AppStorage.setOrCreate('access_token', '');
    router.replaceUrl({ url: 'pages/Login' });
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        // ── User Info Card ──
        Row({ space: 15 }) {
          Image(this.user.avatar ? this.user.avatar : $r('app.media.foreground'))
            .width(80)
            .height(80)
            .borderRadius(40)
            .backgroundColor('#EEEEEE')

          Column({ space: 5 }) {
            Text(this.user.name || '加载中...')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
            Text(`工号: ${this.user.emp_id}`)
              .fontColor(Color.Gray)
              .fontSize(14)
            Text(`角色: ${this.user.role}`)
              .fontColor(Color.Gray)
              .fontSize(14)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('90%')
        .padding(20)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .shadow({ radius: 10, color: '#1A000000' })
        .margin({ top: 20 })

        // ── Edit Profile Button ──
        Button('修改资料')
          .width('90%')
          .height(44)
          .onClick((): void => {
            this.editDialogController.open();
          })

        // ── Create Group Section ──
        Column({ space: 10 }) {
          Text('新建我的小组')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .width('100%')

          Row({ space: 10 }) {
            TextInput({ placeholder: '请输入新小组名称', text: this.newGroupName })
              .layoutWeight(1)
              .height(40)
              .onChange((val: string): void => {
                this.newGroupName = val;
              })

            Button('创建')
              .height(40)
              .onClick((): void => {
                this.createGroup();
              })
          }
          .width('100%')
        }
        .width('90%')
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .shadow({ radius: 6, color: '#0D000000' })

        // ── My Messages (Invites) Section ──
        Column({ space: 10 }) {
          Text('我的消息 (入组邀请)')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .width('100%')

          if (this.invites.length === 0) {
            Text('暂无邀请消息')
              .fontColor(Color.Gray)
              .fontSize(14)
              .margin({ top: 8 })
          }

          ForEach(this.invites, (invite: InviteInfo): void => {
            Row() {
              Text(`邀请加入: ${invite.group_name}`)
                .layoutWeight(1)
                .fontSize(15)

              Button('同意')
                .backgroundColor('#4CAF50')
                .fontColor(Color.White)
                .height(32)
                .margin({ right: 8 })
                .onClick((): void => {
                  this.respondInvite(invite.group_id, 'accept');
                })

              Button('拒绝')
                .backgroundColor('#F44336')
                .fontColor(Color.White)
                .height(32)
                .onClick((): void => {
                  this.respondInvite(invite.group_id, 'reject');
                })
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FAFAFA')
            .borderRadius(8)
          })
        }
        .width('90%')
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .shadow({ radius: 6, color: '#0D000000' })

        // ── Admin Panel ──
        if (this.user.role === 'admin' || this.user.role === 'super_admin') {
          Column({ space: 10 }) {
            Text('管理员面板')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            Button('创建用户')
              .width('100%')
              .height(44)
              .backgroundColor(Color.Orange)
              .onClick((): void => {
                this.createUserDialogController.open();
              })
          }
          .width('90%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .shadow({ radius: 6, color: '#0D000000' })
        }

        // ── Logout Button ──
        Button('退出登录')
          .width('90%')
          .height(44)
          .backgroundColor('#F44336')
          .fontColor(Color.White)
          .margin({ top: 8, bottom: 30 })
          .onClick((): void => {
            this.handleLogout();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .scrollable(ScrollDirection.Vertical)
  }
}
