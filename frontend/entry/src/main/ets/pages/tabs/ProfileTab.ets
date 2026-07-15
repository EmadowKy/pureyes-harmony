import { HttpUtil } from '../../utils/http'
import promptAction from '@ohos.promptAction'
import router from '@ohos.router'
import photoAccessHelper from '@ohos.file.photoAccessHelper'

export class UserInfo {
  emp_id: string = '';
  name: string = '';
  phone: string = '';
  avatar: string = '';
  role: string = '';
  is_active: boolean = true;
  llm_api_key: string = '';
  llm_base_url: string = '';
  llm_model: string = '';
}

export class InviteInfo {
  group_id: number = 0;
  group_name: string = '';
  creator_id: string = '';
}

class EditProfilePayload {
  name: string = '';
  phone: string = '';
}

class AvatarPayload {
  avatar: string = '';
}

class PasswordPayload {
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
  confirm: (name: string, phone: string) => void =
    (_name: string, _phone: string): void => {};

  build() {
    Column({ space: 12 }) {
      Text('修改资料')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      TextInput({ placeholder: '姓名，留空保持原值', text: this.name })
        .onChange((val: string): void => {
          this.name = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      TextInput({ placeholder: '手机号，留空保持原值', text: this.phone })
        .onChange((val: string): void => {
          this.phone = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      Row({ space: 20 }) {
        Button('取消')
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)

        Button('保存')
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.confirm(this.name, this.phone);
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
export struct ChangePasswordDialog {
  controller: CustomDialogController
  @State pass: string = '';
  @State confirmPass: string = '';
  confirm: (pass: string, confirmPass: string) => void =
    (_pass: string, _confirmPass: string): void => {};

  build() {
    Column({ space: 12 }) {
      Text('修改密码')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))

      TextInput({ placeholder: '新密码，至少6位', text: this.pass })
        .type(InputType.Password)
        .onChange((val: string): void => {
          this.pass = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      TextInput({ placeholder: '再次输入新密码', text: this.confirmPass })
        .type(InputType.Password)
        .onChange((val: string): void => {
          this.confirmPass = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      Row({ space: 20 }) {
        Button('取消')
          .onClick((): void => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)

        Button('保存')
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.confirm(this.pass, this.confirmPass);
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
        .fontColor($r('app.color.app_text_primary'))

      TextInput({ placeholder: '工号', text: this.empId })
        .onChange((val: string): void => {
          this.empId = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      TextInput({ placeholder: '姓名', text: this.name })
        .onChange((val: string): void => {
          this.name = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      TextInput({ placeholder: '手机号，可选', text: this.phone })
        .onChange((val: string): void => {
          this.phone = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

      TextInput({ placeholder: '初始密码，至少6位', text: this.pass })
        .type(InputType.Password)
        .onChange((val: string): void => {
          this.pass = val;
        })
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))

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
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
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
  @State llmApiKey: string = '';
  @State llmBaseUrl: string = '';
  @State llmModel: string = '';
  @State showUserManagement: boolean = false;

  editDialogController: CustomDialogController = new CustomDialogController({
    builder: EditProfileDialog({
      confirm: (name: string, phone: string): void => {
        this.submitEditProfile(name, phone);
      }
    }),
    autoCancel: true
  })

  passwordDialogController: CustomDialogController = new CustomDialogController({
    builder: ChangePasswordDialog({
      confirm: (pass: string, confirmPass: string): void => {
        this.submitChangePassword(pass, confirmPass);
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

  isAdminUser(): boolean {
    return this.user.role === 'admin' || this.user.role === 'super_admin';
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
    u.llm_api_key = (dataObj['llm_api_key'] as string) || '';
    u.llm_base_url = (dataObj['llm_base_url'] as string) || '';
    u.llm_model = (dataObj['llm_model'] as string) || '';
    return u;
  }

  async loadProfile(): Promise<void> {
    const res = await HttpUtil.get('/users/me');
    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      this.user = this.parseUser(dataObj);
      this.llmApiKey = this.user.llm_api_key || '';
      this.llmBaseUrl = this.user.llm_base_url || '';
      this.llmModel = this.user.llm_model || '';
      if (this.isAdminUser()) {
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

  async chooseAvatar(): Promise<void> {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;

    try {
      const result = await picker.select(options);
      if (result.photoUris && result.photoUris.length > 0) {
        this.submitAvatar(result.photoUris[0]);
      }
    } catch (err) {
      console.error('Avatar picker failed', JSON.stringify(err));
      promptAction.showToast({ message: '未选择头像', duration: 2000 });
    }
  }

  async submitAvatar(avatar: string): Promise<void> {
    if (!avatar) {
      return;
    }

    const payload = new AvatarPayload();
    payload.avatar = avatar;
    const res = await HttpUtil.put('/users/me', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '头像已更新', duration: 2000 });
      this.loadProfile();
    } else {
      promptAction.showToast({ message: res.message || '头像更新失败', duration: 2000 });
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

  async submitEditProfile(name: string, phone: string): Promise<void> {
    const payload = new EditProfilePayload();
    payload.name = name.trim() || this.user.name;
    payload.phone = phone.trim() || this.user.phone;
    const res = await HttpUtil.put('/users/me', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '资料修改成功', duration: 2000 });
      this.loadProfile();
    } else {
      promptAction.showToast({ message: res.message || '资料修改失败', duration: 2000 });
    }
  }

  async submitChangePassword(pass: string, confirmPass: string): Promise<void> {
    const nextPass = pass.trim();
    if (nextPass.length < 6) {
      promptAction.showToast({ message: '密码至少需要6位', duration: 2000 });
      return;
    }
    if (nextPass !== confirmPass.trim()) {
      promptAction.showToast({ message: '两次输入的密码不一致', duration: 2000 });
      return;
    }

    const payload = new PasswordPayload();
    payload.password = nextPass;
    const res = await HttpUtil.put('/users/me', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '密码修改成功', duration: 2000 });
    } else {
      promptAction.showToast({ message: res.message || '密码修改失败', duration: 2000 });
    }
  }

  async submitSaveApiConfig(): Promise<void> {
    class ApiConfigPayload {
      llm_api_key: string = '';
      llm_base_url: string = '';
      llm_model: string = '';
    }
    const payload = new ApiConfigPayload();
    payload.llm_api_key = this.llmApiKey.trim();
    payload.llm_base_url = this.llmBaseUrl.trim();
    payload.llm_model = this.llmModel.trim();

    const res = await HttpUtil.put('/users/me', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: 'API 配置保存成功', duration: 2000 });
      this.loadProfile();
    } else {
      promptAction.showToast({ message: res.message || 'API 配置保存失败', duration: 2000 });
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
    if (!this.isAdminUser()) {
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

  openUserManagement(): void {
    this.showUserManagement = true;
    this.searchUsers();
  }

  handleLogout(): void {
    AppStorage.setOrCreate('access_token', '');
    AppStorage.setOrCreate('currentGroupId', 0);
    router.replaceUrl({ url: 'pages/Login' });
  }

  @Builder ProfileHeader() {
    Row({ space: 15 }) {
      Image(this.user.avatar ? this.user.avatar : $r('app.media.foreground'))
        .width(72)
        .height(72)
        .borderRadius(36)
        .backgroundColor($r('app.color.app_card_subtle_bg'))
        .onClick((): void => {
          this.chooseAvatar();
        })

      Column({ space: 5 }) {
        Text(this.user.name || '加载中...')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
        Text(`工号: ${this.user.emp_id}`)
          .fontColor($r('app.color.app_text_secondary'))
          .fontSize(14)
        Text(`${this.roleLabel(this.user.role)}${this.user.phone ? ' · ' + this.user.phone : ''}`)
          .fontColor($r('app.color.app_text_secondary'))
          .fontSize(14)

        Button('更换头像')
          .height(32)
          .backgroundColor($r('app.color.app_primary_soft'))
          .fontColor($r('app.color.app_primary'))
          .onClick((): void => {
            this.chooseAvatar();
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('90%')
    .padding(18)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(10)
    .margin({ top: 20 })
  }

  @Builder AccountSettings() {
    Column({ space: 12 }) {
      Text('账号设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .width('100%')

      Row() {
        Column({ space: 3 }) {
          Text('个人资料')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_text_primary'))
          Text('姓名、手机号')
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('修改')
          .height(32)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.editDialogController.open();
          })
      }
      .width('100%')

      Row() {
        Column({ space: 3 }) {
          Text('登录密码')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_text_primary'))
          Text('单独修改密码')
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('修改')
          .height(32)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.passwordDialogController.open();
          })
      }
      .width('100%')
    }
    .width('90%')
    .padding(16)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(10)
  }

  @Builder AdminEntry() {
    Column({ space: 10 }) {
      Text('管理员工具')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .width('100%')

      Row() {
        Column({ space: 3 }) {
          Text('用户管理')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_text_primary'))
          Text('搜索、创建、启停账号')
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('进入')
          .height(34)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.openUserManagement();
          })
      }
      .width('100%')
    }
    .width('90%')
    .padding(16)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(10)
  }

  @Builder GroupActions() {
    Column({ space: 10 }) {
      Text('新建小组')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .width('100%')

      Row({ space: 10 }) {
        TextInput({ placeholder: '请输入新小组名称', text: this.newGroupName })
          .layoutWeight(1)
          .height(40)
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_input_bg'))
          .onChange((val: string): void => {
            this.newGroupName = val;
          })

        Button('创建')
          .height(40)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.createGroup();
          })
      }
      .width('100%')
    }
    .width('90%')
    .padding(16)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(10)
  }

  @Builder InviteSection() {
    Column({ space: 10 }) {
      Text('我的消息')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .width('100%')

      if (this.invites.length === 0) {
        Text('暂无入组邀请')
          .fontColor($r('app.color.app_text_secondary'))
          .fontSize(14)
          .margin({ top: 8 })
      }

      ForEach(this.invites, (invite: InviteInfo): void => {
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Text(`邀请加入: ${invite.group_name}`)
              .fontSize(15)
              .fontColor($r('app.color.app_text_primary'))
            Text(`邀请人: ${invite.creator_id}`)
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('同意')
            .backgroundColor($r('app.color.app_success'))
            .fontColor(Color.White)
            .height(32)
            .onClick((): void => {
              this.respondInvite(invite.group_id, 'accept');
            })

          Button('拒绝')
            .backgroundColor($r('app.color.app_danger'))
            .fontColor(Color.White)
            .height(32)
            .onClick((): void => {
              this.respondInvite(invite.group_id, 'reject');
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.app_card_subtle_bg'))
        .borderRadius(10)
      })
    }
    .width('90%')
    .padding(16)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(10)
  }

  @Builder ApiConfigSection() {
    Column({ space: 10 }) {
      Text('大模型 API 配置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .width('100%')

      Text('配置保存在当前用户下，用于云端视频分析。若没有配置环境变量，可以使用阿里云百炼 API Key。')
        .fontSize(12)
        .fontColor($r('app.color.app_text_secondary'))
        .width('100%')

      TextInput({ placeholder: 'API KEY (如: sk-xxx)', text: this.llmApiKey })
        .width('100%')
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .onChange((val: string): void => {
          this.llmApiKey = val;
        })

      TextInput({ placeholder: 'BASE URL (如: https://.../compatible-mode/v1)', text: this.llmBaseUrl })
        .width('100%')
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .onChange((val: string): void => {
          this.llmBaseUrl = val;
        })

      TextInput({ placeholder: 'MODEL (如: qwen3.7-plus)', text: this.llmModel })
        .width('100%')
        .height(40)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_input_bg'))
        .onChange((val: string): void => {
          this.llmModel = val;
        })

      Button('保存 API 配置')
        .width('100%')
        .height(40)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick((): void => {
          this.submitSaveApiConfig();
        })
    }
    .width('90%')
    .padding(16)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(10)
  }

  @Builder ProfileHome() {
    Scroll() {
      Column({ space: 16 }) {
        this.ProfileHeader()
        this.AccountSettings()
        this.GroupActions()
        this.InviteSection()

        if (this.isAdminUser()) {
          this.AdminEntry()
        }

        this.ApiConfigSection()

        Button('退出登录')
          .width('90%')
          .height(44)
          .backgroundColor($r('app.color.app_danger'))
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
    .backgroundColor($r('app.color.app_page_bg'))
    .scrollable(ScrollDirection.Vertical)
  }

  @Builder AdminManagementPage() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Button('返回')
          .height(36)
          .backgroundColor($r('app.color.app_card_subtle_bg'))
          .fontColor($r('app.color.app_text_primary'))
          .onClick((): void => {
            this.showUserManagement = false;
            this.selectedUser = new UserInfo();
          })

        Column({ space: 2 }) {
          Text('用户管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
          Text('管理员可搜索和创建用户，超级管理员可调整角色')
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('创建')
          .height(36)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.createUserDialogController.open();
          })
      }
      .width('90%')
      .padding({ top: 20, bottom: 4 })

      Row({ space: 8 }) {
        TextInput({ placeholder: '按姓名或工号搜索', text: this.searchKeyword })
          .layoutWeight(1)
          .height(40)
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_input_bg'))
          .onChange((val: string): void => {
            this.searchKeyword = val;
          })

        Button('搜索')
          .height(40)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.searchUsers();
          })
      }
      .width('90%')

      List({ space: 10 }) {
        if (this.adminUsers.length === 0) {
          ListItem() {
            Text('暂无用户')
              .fontSize(14)
              .fontColor($r('app.color.app_text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(24)
          }
        }

        ForEach(this.adminUsers, (item: UserInfo): void => {
          ListItem() {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Column({ space: 3 }) {
                  Text(`${item.name || item.emp_id} (${item.emp_id})`)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                  Text(`${this.roleLabel(item.role)} · ${item.is_active ? '已启用' : '已停用'}${item.phone ? ' · ' + item.phone : ''}`)
                    .fontSize(12)
                    .fontColor(item.is_active ? '#808080' : '#C62828')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(this.selectedUser.emp_id === item.emp_id ? '收起' : '详情')
                  .height(32)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .onClick((): void => {
                    this.selectedUser = this.selectedUser.emp_id === item.emp_id ? new UserInfo() : item;
                  })
              }

              if (this.selectedUser.emp_id === item.emp_id && this.user.role === 'super_admin' && item.role !== 'super_admin') {
                Row({ space: 8 }) {
                  Button('设为管理员')
                    .height(32)
                    .backgroundColor($r('app.color.app_primary'))
                    .fontColor(Color.White)
                    .enabled(item.role !== 'admin')
                    .opacity(item.role !== 'admin' ? 1 : 0.5)
                    .onClick((): void => {
                      this.updateSelectedUserRole('admin');
                    })

                  Button('设为普通用户')
                    .height(32)
                    .backgroundColor($r('app.color.app_primary'))
                    .fontColor(Color.White)
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
                    .backgroundColor(item.is_active ? $r('app.color.app_danger') : $r('app.color.app_success'))
                    .fontColor(Color.White)
                    .onClick((): void => {
                      this.updateSelectedUserStatus(!item.is_active);
                    })
                }
              }
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.app_card_bg'))
            .borderRadius(10)
          }
        })
      }
      .width('90%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.app_page_bg'))
  }

  build() {
    if (this.showUserManagement && this.isAdminUser()) {
      this.AdminManagementPage()
    } else {
      this.ProfileHome()
    }
  }
}
