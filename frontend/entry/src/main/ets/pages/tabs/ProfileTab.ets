import { HttpUtil } from '../../utils/http'
import promptAction from '@ohos.promptAction'
import router from '@ohos.router'

export class UserInfo {
  emp_id: string = '';
  name: string = '';
  phone: string = '';
  avatar: string = '';
  role: string = '';
  is_active: boolean = true;
}

export class InviteInfo {
  group_id: number = 0;
  group_name: string = '';
  creator_id: string = '';
}

class EditPayload {
  name: string = '';
  phone: string = '';
  avatar: string = '';
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
  phone: string = '';
  password: string = '';
}

class RolePayload {
  role: string = '';
}

class StatusPayload {
  is_active: boolean = true;
}

@CustomDialog
export struct EditProfileDialog {
  controller: CustomDialogController
  @State name: string = '';
  @State phone: string = '';
  @State avatar: string = '';
  @State pass: string = '';
  confirm: (name: string, phone: string, avatar: string, pass: string) => void =
    (_name: string, _phone: string, _avatar: string, _pass: string): void => {};

  build() {
    Column({ space: 12 }) {
      Text('修改个人资料')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '姓名', text: this.name })
        .onChange((val: string): void => {
          this.name = val;
        })
        .height(40)

      TextInput({ placeholder: '手机号，不修改留空', text: this.phone })
        .onChange((val: string): void => {
          this.phone = val;
        })
        .height(40)

      TextInput({ placeholder: '头像地址，不修改留空', text: this.avatar })
        .onChange((val: string): void => {
          this.avatar = val;
        })
        .height(40)

      TextInput({ placeholder: '新密码，不修改留空', text: this.pass })
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

        Button('保存')
          .onClick((): void => {
            this.confirm(this.name, this.phone, this.avatar, this.pass);
            this.controller.close();
          })
      }
      .margin({ top: 8 })
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
  @State phone: string = '';
  @State pass: string = '';
  confirm: (empId: string, name: string, phone: string, pass: string) => void =
    (_empId: string, _name: string, _phone: string, _pass: string): void => {};

  build() {
    Column({ space: 12 }) {
      Text('创建新用户')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      TextInput({ placeholder: '工号', text: this.empId })
        .onChange((val: string): void => {
          this.empId = val;
        })
        .height(40)

      TextInput({ placeholder: '姓名', text: this.name })
        .onChange((val: string): void => {
          this.name = val;
        })
        .height(40)

      TextInput({ placeholder: '手机号，可选', text: this.phone })
        .onChange((val: string): void => {
          this.phone = val;
        })
        .height(40)

      TextInput({ placeholder: '初始密码，至少6位', text: this.pass })
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
            this.confirm(this.empId, this.name, this.phone, this.pass);
            this.controller.close();
          })
          .backgroundColor(Color.Orange)
      }
      .margin({ top: 8 })
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
  @State searchKeyword: string = '';
  @State adminUsers: Array<UserInfo> = [];
  @State selectedUser: UserInfo = new UserInfo();

  editDialogController: CustomDialogController = new CustomDialogController({
    builder: EditProfileDialog({
      confirm: (name: string, phone: string, avatar: string, pass: string): void => {
        this.submitEditProfile(name, phone, avatar, pass);
      }
    }),
    autoCancel: true
  })

  createUserDialogController: CustomDialogController = new CustomDialogController({
    builder: CreateUserDialog({
      confirm: (empId: string, name: string, phone: string, pass: string): void => {
        this.submitCreateUser(empId, name, phone, pass);
      }
    }),
    autoCancel: true
  })

  aboutToAppear(): void {
    this.loadProfile();
    this.loadInvites();
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

  parseUser(dataObj: Record<string, Object>): UserInfo {
    const u = new UserInfo();
    u.emp_id = (dataObj['emp_id'] as string) || '';
    u.name = (dataObj['name'] as string) || '';
    u.phone = (dataObj['phone'] as string) || '';
    u.avatar = (dataObj['avatar'] as string) || '';
    u.role = (dataObj['role'] as string) || '';
    u.is_active = (dataObj['is_active'] as boolean) !== false;
    return u;
  }

  async loadProfile(): Promise<void> {
    const res = await HttpUtil.get('/users/me');
    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      this.user = this.parseUser(dataObj);
      if (this.user.role === 'admin' || this.user.role === 'super_admin') {
        this.searchUsers();
      }
    }
  }

  async loadInvites(): Promise<void> {
    const res = await HttpUtil.get('/groups/invites');
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      this.invites = listObj.map((item: Record<string, Object>): InviteInfo => {
        const inv = new InviteInfo();
        inv.group_id = (item['group_id'] as number) || 0;
        inv.group_name = (item['group_name'] as string) || '';
        inv.creator_id = (item['creator_id'] as string) || '';
        return inv;
      });
    } else {
      this.invites = [];
    }
  }

  async respondInvite(groupId: number, action: string): Promise<void> {
    const payload = new RespondPayload();
    payload.action = action;
    const res = await HttpUtil.post(`/groups/${groupId}/respond`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: action === 'accept' ? '已加入小组' : '已拒绝邀请', duration: 2000 });
      this.loadInvites();
      AppStorage.setOrCreate('refreshGroupFlag', Math.random());
    } else {
      promptAction.showToast({ message: res.message || '操作失败', duration: 2000 });
    }
  }

  async createGroup(): Promise<void> {
    const groupName = this.newGroupName.trim();
    if (!groupName) {
      promptAction.showToast({ message: '请输入小组名称', duration: 2000 });
      return;
    }

    const payload = new CreateGroupPayload();
    payload.name = groupName;
    const res = await HttpUtil.post('/groups/', payload);
    if (res.code === 0) {
      this.newGroupName = '';
      promptAction.showToast({ message: '小组创建成功', duration: 2000 });
      AppStorage.setOrCreate('refreshGroupFlag', Math.random());
    } else {
      promptAction.showToast({ message: res.message || '小组创建失败', duration: 2000 });
    }
  }

  async submitEditProfile(name: string, phone: string, avatar: string, pass: string): Promise<void> {
    const payload = new EditPayload();
    payload.name = name.trim() || this.user.name;
    payload.phone = phone.trim() || this.user.phone;
    payload.avatar = avatar.trim() || this.user.avatar;
    payload.password = pass;
    const res = await HttpUtil.put('/users/me', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '资料修改成功', duration: 2000 });
      this.loadProfile();
    } else {
      promptAction.showToast({ message: res.message || '资料修改失败', duration: 2000 });
    }
  }

  async submitCreateUser(empId: string, name: string, phone: string, pass: string): Promise<void> {
    const payload = new CreateUserPayload();
    payload.emp_id = empId.trim();
    payload.name = name.trim();
    payload.phone = phone.trim();
    payload.password = pass;
    const res = await HttpUtil.post('/users/', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '用户创建成功', duration: 2000 });
      this.searchUsers();
    } else {
      promptAction.showToast({ message: res.message || '用户创建失败', duration: 2000 });
    }
  }

  async searchUsers(): Promise<void> {
    if (!(this.user.role === 'admin' || this.user.role === 'super_admin')) {
      return;
    }

    const keyword = encodeURIComponent(this.searchKeyword.trim());
    const res = await HttpUtil.get(`/users/?keyword=${keyword}`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      this.adminUsers = listObj.map((item: Record<string, Object>): UserInfo => this.parseUser(item));
    } else {
      this.adminUsers = [];
    }
  }

  async updateSelectedUserRole(role: string): Promise<void> {
    if (!this.selectedUser.emp_id) {
      return;
    }

    const payload = new RolePayload();
    payload.role = role;
    const res = await HttpUtil.put(`/users/${this.selectedUser.emp_id}/role`, payload);
    if (res.code === 0 && res.data) {
      promptAction.showToast({ message: '角色已更新', duration: 2000 });
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      this.selectedUser = this.parseUser(dataObj);
      this.searchUsers();
    } else {
      promptAction.showToast({ message: res.message || '角色更新失败', duration: 2000 });
    }
  }

  async updateSelectedUserStatus(isActive: boolean): Promise<void> {
    if (!this.selectedUser.emp_id) {
      return;
    }

    const payload = new StatusPayload();
    payload.is_active = isActive;
    const res = await HttpUtil.put(`/users/${this.selectedUser.emp_id}/status`, payload);
    if (res.code === 0 && res.data) {
      promptAction.showToast({ message: isActive ? '账号已启用' : '账号已停用', duration: 2000 });
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      this.selectedUser = this.parseUser(dataObj);
      this.searchUsers();
    } else {
      promptAction.showToast({ message: res.message || '账号状态更新失败', duration: 2000 });
    }
  }

  handleLogout(): void {
    AppStorage.setOrCreate('access_token', '');
    AppStorage.setOrCreate('currentGroupId', 0);
    router.replaceUrl({ url: 'pages/Login' });
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 15 }) {
          Image(this.user.avatar ? this.user.avatar : $r('app.media.foreground'))
            .width(72)
            .height(72)
            .borderRadius(36)
            .backgroundColor('#EEEEEE')

          Column({ space: 5 }) {
            Text(this.user.name || '加载中...')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
            Text(`工号: ${this.user.emp_id}`)
              .fontColor(Color.Gray)
              .fontSize(14)
            Text(`${this.roleLabel(this.user.role)}${this.user.phone ? ' · ' + this.user.phone : ''}`)
              .fontColor(Color.Gray)
              .fontSize(14)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('90%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(8)
        .margin({ top: 20 })

        Button('修改资料')
          .width('90%')
          .height(44)
          .onClick((): void => {
            this.editDialogController.open();
          })

        Column({ space: 10 }) {
          Text('新建小组')
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
        .borderRadius(8)

        Column({ space: 10 }) {
          Text('我的消息')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .width('100%')

          if (this.invites.length === 0) {
            Text('暂无入组邀请')
              .fontColor(Color.Gray)
              .fontSize(14)
              .margin({ top: 8 })
          }

          ForEach(this.invites, (invite: InviteInfo): void => {
            Row({ space: 8 }) {
              Column({ space: 3 }) {
                Text(`邀请加入: ${invite.group_name}`)
                  .fontSize(15)
                Text(`邀请人: ${invite.creator_id}`)
                  .fontSize(12)
                  .fontColor(Color.Gray)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button('同意')
                .backgroundColor('#2E7D32')
                .fontColor(Color.White)
                .height(32)
                .onClick((): void => {
                  this.respondInvite(invite.group_id, 'accept');
                })

              Button('拒绝')
                .backgroundColor('#C62828')
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
        .borderRadius(8)

        if (this.user.role === 'admin' || this.user.role === 'super_admin') {
          Column({ space: 10 }) {
            Row() {
              Text('用户管理')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)

              Button('创建用户')
                .height(36)
                .backgroundColor(Color.Orange)
                .onClick((): void => {
                  this.createUserDialogController.open();
                })
            }
            .width('100%')

            Row({ space: 8 }) {
              TextInput({ placeholder: '按姓名或工号搜索', text: this.searchKeyword })
                .layoutWeight(1)
                .height(40)
                .onChange((val: string): void => {
                  this.searchKeyword = val;
                })

              Button('搜索')
                .height(40)
                .onClick((): void => {
                  this.searchUsers();
                })
            }
            .width('100%')

            ForEach(this.adminUsers, (item: UserInfo): void => {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(`${item.name} (${item.emp_id})`)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                    Text(`${this.roleLabel(item.role)} · ${item.is_active ? '已启用' : '已停用'}${item.phone ? ' · ' + item.phone : ''}`)
                      .fontSize(12)
                      .fontColor(item.is_active ? '#808080' : '#C62828')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Button(this.selectedUser.emp_id === item.emp_id ? '收起' : '详情')
                    .height(32)
                    .onClick((): void => {
                      this.selectedUser = this.selectedUser.emp_id === item.emp_id ? new UserInfo() : item;
                    })
                }

                if (this.selectedUser.emp_id === item.emp_id && this.user.role === 'super_admin' && item.role !== 'super_admin') {
                  Row({ space: 8 }) {
                    Button('设为管理员')
                      .height(32)
                      .enabled(item.role !== 'admin')
                      .opacity(item.role !== 'admin' ? 1 : 0.5)
                      .onClick((): void => {
                        this.updateSelectedUserRole('admin');
                      })

                    Button('设为普通用户')
                      .height(32)
                      .enabled(item.role !== 'user')
                      .opacity(item.role !== 'user' ? 1 : 0.5)
                      .onClick((): void => {
                        this.updateSelectedUserRole('user');
                      })
                  }
                }

                if (this.selectedUser.emp_id === item.emp_id && item.role !== 'super_admin' && item.emp_id !== this.user.emp_id) {
                  Row({ space: 8 }) {
                    Button(item.is_active ? '停用账号' : '启用账号')
                      .height(32)
                      .backgroundColor(item.is_active ? '#D64545' : '#2E7D32')
                      .fontColor(Color.White)
                      .onClick((): void => {
                        this.updateSelectedUserStatus(!item.is_active);
                      })
                  }
                }
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
          .borderRadius(8)
        }

        Button('退出登录')
          .width('90%')
          .height(44)
          .backgroundColor('#D64545')
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
