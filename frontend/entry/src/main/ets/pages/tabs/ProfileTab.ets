import { HttpUtil } from '../../utils/http'
import promptAction from '@ohos.promptAction'
import router from '@ohos.router'
import photoAccessHelper from '@ohos.file.photoAccessHelper'

const PAGE_HOME = 'home';
const PAGE_INFO = 'info';
const PAGE_SECURITY = 'security';
const PAGE_MESSAGES = 'messages';
const PAGE_CREATE_GROUP = 'createGroup';
const PAGE_ADMIN = 'admin';
const PAGE_USER_SEARCH = 'userSearch';
const PAGE_API_CONFIG = 'apiConfig';

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

export class SentInviteInfo {
  group_id: number = 0;
  group_name: string = '';
  emp_id: string = '';
  name: string = '';
  status: string = '';
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

      TextInput({ placeholder: '姓名，可选', text: this.name })
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
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.confirm(this.empId, this.name, this.phone, this.pass);
            this.controller.close();
          })
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
  @State activePage: string = PAGE_HOME;
  @State invites: Array<InviteInfo> = [];
  @State sentInvites: Array<SentInviteInfo> = [];
  @State adminUsers: Array<UserInfo> = [];
  @State selectedUser: UserInfo = new UserInfo();
  @State showUserDetail: boolean = false;
  @State userDetailReadonly: boolean = false;

  @State editName: string = '';
  @State editPhone: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State resetPassword: string = '';
  @State resetConfirmPassword: string = '';
  @State deleteConfirm: boolean = false;
  @State newGroupName: string = '';
  @State searchKeyword: string = '';
  @State llmApiKey: string = '';
  @State llmBaseUrl: string = '';
  @State llmModel: string = '';

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

  userStatusLabel(user: UserInfo): string {
    return user.is_active ? '正常' : '已停用';
  }

  canOperateTarget(target: UserInfo): boolean {
    return this.isAdminUser() && target.emp_id.length > 0 && target.role !== 'super_admin' && target.emp_id !== this.user.emp_id;
  }

  canChangeTargetRole(target: UserInfo): boolean {
    return this.user.role === 'super_admin' && this.canOperateTarget(target);
  }

  sentInviteStatusLabel(status: string): string {
    return status === 'accepted' ? '已加入' : '等待确认';
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

  async loadSentInvites(): Promise<void> {
    const groupRes = await HttpUtil.get('/groups/');
    if (groupRes.code !== 0 || !groupRes.data) {
      this.sentInvites = [];
      return;
    }

    const groups = JSON.parse(groupRes.data) as Array<Record<string, Object>>;
    const nextInvites: Array<SentInviteInfo> = [];
    for (let i = 0; i < groups.length; i++) {
      const group = groups[i];
      const isCreator = (group['is_creator'] as boolean) || false;
      if (!isCreator) {
        continue;
      }

      const groupId = (group['id'] as number) || 0;
      const groupName = (group['name'] as string) || '';
      const creatorId = (group['creator_id'] as string) || '';
      const memberRes = await HttpUtil.get(`/groups/${groupId}/members?include_pending=1`);
      if (memberRes.code !== 0 || !memberRes.data) {
        continue;
      }

      const members = JSON.parse(memberRes.data) as Array<Record<string, Object>>;
      for (let j = 0; j < members.length; j++) {
        const member = members[j];
        const empId = (member['emp_id'] as string) || '';
        if (!empId || empId === creatorId) {
          continue;
        }

        const sent = new SentInviteInfo();
        sent.group_id = groupId;
        sent.group_name = groupName;
        sent.emp_id = empId;
        sent.name = (member['name'] as string) || empId;
        sent.status = (member['status'] as string) || 'pending';
        nextInvites.push(sent);
      }
    }

    this.sentInvites = nextInvites;
  }

  async loadMessages(): Promise<void> {
    await this.loadInvites();
    await this.loadSentInvites();
  }

  openPage(page: string): void {
    this.activePage = page;
    if (page === PAGE_INFO) {
      this.editName = this.user.name;
      this.editPhone = this.user.phone;
    } else if (page === PAGE_SECURITY) {
      this.newPassword = '';
      this.confirmPassword = '';
    } else if (page === PAGE_MESSAGES) {
      this.loadMessages();
    } else if (page === PAGE_CREATE_GROUP) {
      this.newGroupName = '';
    } else if (page === PAGE_ADMIN) {
      this.selectedUser = new UserInfo();
      this.showUserDetail = false;
      this.userDetailReadonly = false;
      this.deleteConfirm = false;
      this.searchKeyword = '';
      this.searchUsers();
    } else if (page === PAGE_USER_SEARCH) {
      this.selectedUser = new UserInfo();
      this.showUserDetail = false;
      this.userDetailReadonly = true;
      this.deleteConfirm = false;
      this.searchKeyword = '';
      this.adminUsers = [];
    } else if (page === PAGE_API_CONFIG) {
      this.llmApiKey = this.user.llm_api_key || '';
      this.llmBaseUrl = this.user.llm_base_url || '';
      this.llmModel = this.user.llm_model || '';
    }
  }

  backHome(): void {
    this.activePage = PAGE_HOME;
    this.selectedUser = new UserInfo();
    this.showUserDetail = false;
    this.userDetailReadonly = false;
    this.deleteConfirm = false;
    this.loadProfile();
    this.loadInvites();
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

  async submitEditProfile(): Promise<void> {
    const payload = new EditProfilePayload();
    payload.name = this.editName.trim() || this.user.name;
    payload.phone = this.editPhone.trim() || this.user.phone;
    const res = await HttpUtil.put('/users/me', payload);
    if (res.code === 0) {
      promptAction.showToast({ message: '个人信息已保存', duration: 2000 });
      this.loadProfile();
    } else {
      promptAction.showToast({ message: res.message || '保存失败', duration: 2000 });
    }
  }

  async submitChangePassword(): Promise<void> {
    const nextPass = this.newPassword.trim();
    if (nextPass.length < 6) {
      promptAction.showToast({ message: '密码至少需要6位', duration: 2000 });
      return;
    }
    if (nextPass !== this.confirmPassword.trim()) {
      promptAction.showToast({ message: '两次输入的密码不一致', duration: 2000 });
      return;
    }

    const payload = new PasswordPayload();
    payload.password = nextPass;
    const res = await HttpUtil.put('/users/me', payload);
    if (res.code === 0) {
      this.newPassword = '';
      this.confirmPassword = '';
      promptAction.showToast({ message: '密码修改成功', duration: 2000 });
    } else {
      promptAction.showToast({ message: res.message || '密码修改失败', duration: 2000 });
    }
  }

  async respondInvite(groupId: number, action: string): Promise<void> {
    const payload = new RespondPayload();
    payload.action = action;
    const res = await HttpUtil.post(`/groups/${groupId}/respond`, payload);
    if (res.code === 0) {
      promptAction.showToast({ message: action === 'accept' ? '已加入小组' : '已拒绝邀请', duration: 2000 });
      this.loadMessages();
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
      this.backHome();
    } else {
      promptAction.showToast({ message: res.message || '小组创建失败', duration: 2000 });
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

  async searchPublicUsers(): Promise<void> {
    const keyword = this.searchKeyword.trim();
    if (!keyword) {
      this.adminUsers = [];
      promptAction.showToast({ message: '请输入姓名、工号或手机号', duration: 2000 });
      return;
    }

    const res = await HttpUtil.get(`/users/search?keyword=${encodeURIComponent(keyword)}`);
    if (res.code === 0 && res.data) {
      const listObj = JSON.parse(res.data) as Array<Record<string, Object>>;
      this.adminUsers = listObj.map((item: Record<string, Object>): UserInfo => this.parseUser(item));
    } else {
      this.adminUsers = [];
      promptAction.showToast({ message: res.message || '用户搜索失败', duration: 2000 });
    }
  }

  async openUserDetail(user: UserInfo): Promise<void> {
    this.selectedUser = user;
    this.userDetailReadonly = false;
    this.resetPassword = '';
    this.resetConfirmPassword = '';
    this.deleteConfirm = false;
    this.showUserDetail = true;

    const empId = encodeURIComponent(user.emp_id);
    const res = await HttpUtil.get(`/users/${empId}`);
    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      this.selectedUser = this.parseUser(dataObj);
    } else if (res.code !== 0) {
      promptAction.showToast({ message: res.message || '用户详情加载失败', duration: 2000 });
    }
  }

  openReadonlyUserDetail(user: UserInfo): void {
    this.selectedUser = user;
    this.userDetailReadonly = true;
    this.resetPassword = '';
    this.resetConfirmPassword = '';
    this.deleteConfirm = false;
    this.showUserDetail = true;
  }

  closeUserDetail(): void {
    this.showUserDetail = false;
    this.selectedUser = new UserInfo();
    this.userDetailReadonly = false;
    this.resetPassword = '';
    this.resetConfirmPassword = '';
    this.deleteConfirm = false;
  }

  async updateSelectedUserRole(role: string): Promise<void> {
    if (!this.selectedUser.emp_id) {
      return;
    }

    const payload = new RolePayload();
    payload.role = role;
    const empId = encodeURIComponent(this.selectedUser.emp_id);
    const res = await HttpUtil.put(`/users/${empId}/role`, payload);
    if (res.code === 0 && res.data) {
      promptAction.showToast({ message: '角色已更新', duration: 2000 });
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      this.selectedUser = this.parseUser(dataObj);
      this.searchUsers();
    } else {
      promptAction.showToast({ message: res.message || '角色更新失败', duration: 2000 });
    }
  }

  async resetSelectedUserPassword(): Promise<void> {
    if (!this.canOperateTarget(this.selectedUser)) {
      promptAction.showToast({ message: '该用户不可操作', duration: 2000 });
      return;
    }

    const nextPass = this.resetPassword.trim();
    if (nextPass.length < 6) {
      promptAction.showToast({ message: '初始密码至少需要6位', duration: 2000 });
      return;
    }
    if (nextPass !== this.resetConfirmPassword.trim()) {
      promptAction.showToast({ message: '两次输入的密码不一致', duration: 2000 });
      return;
    }

    const payload = new PasswordPayload();
    payload.password = nextPass;
    const empId = encodeURIComponent(this.selectedUser.emp_id);
    const res = await HttpUtil.put(`/users/${empId}/password`, payload);
    if (res.code === 0 && res.data) {
      const dataObj = JSON.parse(res.data) as Record<string, Object>;
      this.selectedUser = this.parseUser(dataObj);
      this.resetPassword = '';
      this.resetConfirmPassword = '';
      promptAction.showToast({ message: '密码已初始化', duration: 2000 });
      this.searchUsers();
    } else {
      promptAction.showToast({ message: res.message || '密码初始化失败', duration: 2000 });
    }
  }

  async deleteSelectedUser(): Promise<void> {
    if (!this.canOperateTarget(this.selectedUser)) {
      promptAction.showToast({ message: '该用户不可删除', duration: 2000 });
      return;
    }

    if (!this.deleteConfirm) {
      this.deleteConfirm = true;
      return;
    }

    const empId = encodeURIComponent(this.selectedUser.emp_id);
    const res = await HttpUtil.del(`/users/${empId}`);
    if (res.code === 0) {
      promptAction.showToast({ message: '用户已删除', duration: 2000 });
      this.closeUserDetail();
      this.searchUsers();
    } else {
      promptAction.showToast({ message: res.message || '删除用户失败', duration: 2000 });
    }
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
        Text(this.roleLabel(this.user.role))
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

  @Builder PageHeader(title: string, subtitle: string) {
    Row({ space: 12 }) {
      Button('返回')
        .height(36)
        .backgroundColor($r('app.color.app_card_subtle_bg'))
        .fontColor($r('app.color.app_text_primary'))
        .onClick((): void => {
          this.backHome();
        })

      Column({ space: 2 }) {
        Text(title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.app_text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('90%')
    .padding({ top: 20, bottom: 4 })
  }

  @Builder MenuItem(title: string, subtitle: string, page: string, badge: string) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_primary'))
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.app_text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (badge.length > 0) {
        Text(badge)
          .fontSize(12)
          .fontColor($r('app.color.app_primary'))
          .backgroundColor($r('app.color.app_primary_soft'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(10)
          .margin({ right: 10 })
      }

      Button('进入')
        .height(32)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick((): void => {
          this.openPage(page);
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.app_card_bg'))
    .borderRadius(10)
  }

  @Builder ProfileHome() {
    Scroll() {
      Column({ space: 12 }) {
        this.ProfileHeader()

        Column({ space: 10 }) {
          this.MenuItem('个人信息', '姓名、手机号、头像', PAGE_INFO, '')
          this.MenuItem('账号安全', '修改登录密码', PAGE_SECURITY, '')
          this.MenuItem('我的消息', '入组邀请和发出邀请状态', PAGE_MESSAGES, this.invites.length > 0 ? `${this.invites.length}` : '')
          this.MenuItem('新建小组', '创建后自动成为组长', PAGE_CREATE_GROUP, '')

          if (this.isAdminUser()) {
            this.MenuItem('用户管理', '查询、创建和管理用户账号', PAGE_ADMIN, '')
          } else {
            this.MenuItem('用户搜索', '按姓名、工号或手机号查找用户', PAGE_USER_SEARCH, '')
          }

          this.MenuItem('大模型 API 配置', '保存当前用户的模型调用参数', PAGE_API_CONFIG, '')
        }
        .width('90%')

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

  @Builder InfoPage() {
    Scroll() {
      Column({ space: 14 }) {
        this.PageHeader('个人信息', '修改姓名、手机号和头像')

        Column({ space: 14 }) {
          Row({ space: 14 }) {
            Image(this.user.avatar ? this.user.avatar : $r('app.media.foreground'))
              .width(64)
              .height(64)
              .borderRadius(32)
              .backgroundColor($r('app.color.app_card_subtle_bg'))

            Column({ space: 6 }) {
              Text(this.user.name || this.user.emp_id)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_text_primary'))
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
          .width('100%')

          TextInput({ placeholder: '姓名', text: this.editName })
            .width('100%')
            .height(42)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((val: string): void => {
              this.editName = val;
            })

          TextInput({ placeholder: '手机号', text: this.editPhone })
            .width('100%')
            .height(42)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((val: string): void => {
              this.editPhone = val;
            })

          Button('保存')
            .width('100%')
            .height(42)
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .onClick((): void => {
              this.submitEditProfile();
            })
        }
        .width('90%')
        .padding(16)
        .backgroundColor($r('app.color.app_card_bg'))
        .borderRadius(10)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
    .scrollable(ScrollDirection.Vertical)
  }

  @Builder SecurityPage() {
    Column({ space: 14 }) {
      this.PageHeader('账号安全', '修改登录密码')

      Column({ space: 12 }) {
        TextInput({ placeholder: '新密码，至少6位', text: this.newPassword })
          .type(InputType.Password)
          .width('100%')
          .height(42)
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_input_bg'))
          .onChange((val: string): void => {
            this.newPassword = val;
          })

        TextInput({ placeholder: '再次输入新密码', text: this.confirmPassword })
          .type(InputType.Password)
          .width('100%')
          .height(42)
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_input_bg'))
          .onChange((val: string): void => {
            this.confirmPassword = val;
          })

        Button('保存')
          .width('100%')
          .height(42)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.submitChangePassword();
          })
      }
      .width('90%')
      .padding(16)
      .backgroundColor($r('app.color.app_card_bg'))
      .borderRadius(10)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.app_page_bg'))
  }

  @Builder MessagesPage() {
    Scroll() {
      Column({ space: 14 }) {
        this.PageHeader('我的消息', '入组邀请和发出邀请状态')

        Button('刷新')
          .width('90%')
          .height(38)
          .backgroundColor($r('app.color.app_primary_soft'))
          .fontColor($r('app.color.app_primary'))
          .onClick((): void => {
            this.loadMessages();
          })

        Column({ space: 10 }) {
          Text('收到的邀请')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
            .width('100%')

          if (this.invites.length === 0) {
            Text('暂无待处理入组邀请')
              .fontSize(14)
              .fontColor($r('app.color.app_text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          }

          ForEach(this.invites, (invite: InviteInfo): void => {
            Row({ space: 8 }) {
              Column({ space: 3 }) {
                Text(invite.group_name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.app_text_primary'))
                Text(`邀请人: ${invite.creator_id}`)
                  .fontSize(12)
                  .fontColor($r('app.color.app_text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button('同意')
                .height(32)
                .backgroundColor($r('app.color.app_success'))
                .fontColor(Color.White)
                .onClick((): void => {
                  this.respondInvite(invite.group_id, 'accept');
                })

              Button('拒绝')
                .height(32)
                .backgroundColor($r('app.color.app_danger'))
                .fontColor(Color.White)
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

        Column({ space: 10 }) {
          Text('发出的邀请')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
            .width('100%')

          if (this.sentInvites.length === 0) {
            Text('暂无发出的邀请状态')
              .fontSize(14)
              .fontColor($r('app.color.app_text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          }

          ForEach(this.sentInvites, (invite: SentInviteInfo): void => {
            Row() {
              Column({ space: 3 }) {
                Text(invite.name || invite.emp_id)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.app_text_primary'))
                Text(`小组: ${invite.group_name} · 工号: ${invite.emp_id}`)
                  .fontSize(12)
                  .fontColor($r('app.color.app_text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.sentInviteStatusLabel(invite.status))
                .fontSize(12)
                .fontColor(invite.status === 'accepted' ? $r('app.color.app_success') : '#B45309')
                .backgroundColor($r('app.color.app_card_subtle_bg'))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(10)
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
        .margin({ bottom: 24 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
    .scrollable(ScrollDirection.Vertical)
  }

  @Builder CreateGroupPage() {
    Column({ space: 14 }) {
      this.PageHeader('新建小组', '创建小组后自动成为组长')

      Column({ space: 12 }) {
        TextInput({ placeholder: '请输入小组名称', text: this.newGroupName })
          .width('100%')
          .height(42)
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_input_bg'))
          .onChange((val: string): void => {
            this.newGroupName = val;
          })

        Button('创建小组')
          .width('100%')
          .height(42)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick((): void => {
            this.createGroup();
          })
      }
      .width('90%')
      .padding(16)
      .backgroundColor($r('app.color.app_card_bg'))
      .borderRadius(10)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.app_page_bg'))
  }

  @Builder ApiConfigPage() {
    Scroll() {
      Column({ space: 14 }) {
        this.PageHeader('大模型 API 配置', '保存当前用户的模型调用参数')

        Column({ space: 12 }) {
          TextInput({ placeholder: 'API KEY (如: sk-xxx)', text: this.llmApiKey })
            .width('100%')
            .height(42)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((val: string): void => {
              this.llmApiKey = val;
            })

          TextInput({ placeholder: 'BASE URL (如: https://.../compatible-mode/v1)', text: this.llmBaseUrl })
            .width('100%')
            .height(42)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((val: string): void => {
              this.llmBaseUrl = val;
            })

          TextInput({ placeholder: 'MODEL (如: qwen3.7-plus)', text: this.llmModel })
            .width('100%')
            .height(42)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_input_bg'))
            .onChange((val: string): void => {
              this.llmModel = val;
            })

          Button('保存')
            .width('100%')
            .height(42)
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
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_page_bg'))
    .scrollable(ScrollDirection.Vertical)
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
    .borderRadius(8)
  }

  @Builder UserDetailOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.closeUserDetail();
        })

      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Image(this.selectedUser.avatar ? this.selectedUser.avatar : $r('app.media.foreground'))
            .width(58)
            .height(58)
            .borderRadius(29)
            .backgroundColor($r('app.color.app_card_subtle_bg'))

          Column({ space: 4 }) {
            Text(this.selectedUser.name || this.selectedUser.emp_id)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
            Text(`工号: ${this.selectedUser.emp_id}`)
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
              this.closeUserDetail();
            })
        }
        .width('100%')

        Scroll() {
          Column({ space: 12 }) {
            Column({ space: 8 }) {
              this.DetailRow('工号', this.selectedUser.emp_id)
              this.DetailRow('姓名', this.selectedUser.name)
              this.DetailRow('手机号', this.selectedUser.phone)
              this.DetailRow('身份', this.roleLabel(this.selectedUser.role))
              this.DetailRow('头像', this.selectedUser.avatar ? '已上传' : '未设置')
              this.DetailRow('账号状态', this.userStatusLabel(this.selectedUser))
              if (!this.userDetailReadonly) {
                this.DetailRow('密码', '已设置（不可查看）')
              }
            }
            .width('100%')
            .padding({ left: 2, right: 2 })

            if (this.userDetailReadonly) {
              Text('用户搜索仅用于查看基础资料，账号管理操作仅管理员可用。')
                .width('100%')
                .fontSize(13)
                .fontColor($r('app.color.app_text_secondary'))
                .backgroundColor($r('app.color.app_card_subtle_bg'))
                .padding(12)
                .borderRadius(8)
            } else if (!this.canOperateTarget(this.selectedUser)) {
              Text(this.selectedUser.role === 'super_admin' ? '超级管理员账号不可在用户管理中操作' : '不能对当前登录账号执行管理操作')
                .width('100%')
                .fontSize(13)
                .fontColor($r('app.color.app_text_secondary'))
                .backgroundColor($r('app.color.app_card_subtle_bg'))
                .padding(12)
                .borderRadius(8)
            } else {
              Column({ space: 10 }) {
                Text('初始化密码')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.app_text_primary'))
                  .width('100%')

                TextInput({ placeholder: '新初始密码，至少6位', text: this.resetPassword })
                  .type(InputType.Password)
                  .height(40)
                  .fontColor($r('app.color.app_text_primary'))
                  .backgroundColor($r('app.color.app_input_bg'))
                  .onChange((val: string): void => {
                    this.resetPassword = val;
                  })

                TextInput({ placeholder: '再次输入新初始密码', text: this.resetConfirmPassword })
                  .type(InputType.Password)
                  .height(40)
                  .fontColor($r('app.color.app_text_primary'))
                  .backgroundColor($r('app.color.app_input_bg'))
                  .onChange((val: string): void => {
                    this.resetConfirmPassword = val;
                  })

                Button('初始化密码')
                  .width('100%')
                  .height(40)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .onClick((): void => {
                    this.resetSelectedUserPassword();
                  })
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.app_card_subtle_bg'))
              .borderRadius(8)

              if (this.canChangeTargetRole(this.selectedUser)) {
                Column({ space: 10 }) {
                  Text('身份设置')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                    .width('100%')

                  Row({ space: 8 }) {
                    Button('设为管理员')
                      .layoutWeight(1)
                      .height(38)
                      .backgroundColor($r('app.color.app_primary'))
                      .fontColor(Color.White)
                      .enabled(this.selectedUser.role !== 'admin')
                      .opacity(this.selectedUser.role !== 'admin' ? 1 : 0.5)
                      .onClick((): void => {
                        this.updateSelectedUserRole('admin');
                      })

                    Button('设为普通用户')
                      .layoutWeight(1)
                      .height(38)
                      .backgroundColor($r('app.color.app_primary'))
                      .fontColor(Color.White)
                      .enabled(this.selectedUser.role !== 'user')
                      .opacity(this.selectedUser.role !== 'user' ? 1 : 0.5)
                      .onClick((): void => {
                        this.updateSelectedUserRole('user');
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.app_card_subtle_bg'))
                .borderRadius(8)
              }

              Column({ space: 10 }) {
                Text('删除用户')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.app_danger'))
                  .width('100%')

                Text('删除后该账号无法登录，已创建的小组和记录会转交给当前管理员。')
                  .fontSize(12)
                  .fontColor($r('app.color.app_text_secondary'))
                  .width('100%')

                if (this.deleteConfirm) {
                  Row({ space: 8 }) {
                    Button('取消')
                      .layoutWeight(1)
                      .height(38)
                      .backgroundColor($r('app.color.app_card_subtle_bg'))
                      .fontColor($r('app.color.app_text_primary'))
                      .onClick((): void => {
                        this.deleteConfirm = false;
                      })

                    Button('确认删除')
                      .layoutWeight(1)
                      .height(38)
                      .backgroundColor($r('app.color.app_danger'))
                      .fontColor(Color.White)
                      .onClick((): void => {
                        this.deleteSelectedUser();
                      })
                  }
                  .width('100%')
                } else {
                  Button('删除用户')
                    .width('100%')
                    .height(38)
                    .backgroundColor($r('app.color.app_danger'))
                    .fontColor(Color.White)
                    .onClick((): void => {
                      this.deleteSelectedUser();
                    })
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.app_card_bg'))
              .border({ width: 1, color: $r('app.color.app_danger') })
              .borderRadius(8)
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
      }
      .width('88%')
      .height('82%')
      .padding(16)
      .backgroundColor($r('app.color.app_card_bg'))
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
  }

  @Builder UserSearchPage() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        this.PageHeader('用户搜索', '查询用户基础资料')

        Row({ space: 8 }) {
          TextInput({ placeholder: '输入姓名、工号或手机号', text: this.searchKeyword })
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
              this.searchPublicUsers();
            })
        }
        .width('90%')

        List({ space: 10 }) {
          if (this.adminUsers.length === 0) {
            ListItem() {
              Text(this.searchKeyword.trim().length === 0 ? '请输入关键词后搜索用户' : '未找到匹配用户')
                .fontSize(14)
                .fontColor($r('app.color.app_text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(24)
            }
          }

          ForEach(this.adminUsers, (item: UserInfo): void => {
            ListItem() {
              Row({ space: 10 }) {
                Image(item.avatar ? item.avatar : $r('app.media.foreground'))
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor($r('app.color.app_card_subtle_bg'))

                Column({ space: 4 }) {
                  Text(item.name || item.emp_id)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                  Text(`工号: ${item.emp_id}`)
                    .fontSize(12)
                    .fontColor($r('app.color.app_text_secondary'))
                  Text(`${this.roleLabel(item.role)} · ${this.userStatusLabel(item)}${item.phone ? ' · ' + item.phone : ''}`)
                    .fontSize(12)
                    .fontColor(item.is_active ? '#808080' : '#C62828')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button('查看')
                  .height(34)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .onClick((): void => {
                    this.openReadonlyUserDetail(item);
                  })
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

      if (this.showUserDetail) {
        this.UserDetailOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder AdminManagementPage() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        this.PageHeader('用户管理', '查询、创建、查看和维护用户账号')

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

          Button('创建')
            .height(40)
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .onClick((): void => {
              this.createUserDialogController.open();
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
              Row({ space: 10 }) {
                Image(item.avatar ? item.avatar : $r('app.media.foreground'))
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor($r('app.color.app_card_subtle_bg'))

                Column({ space: 4 }) {
                  Text(item.name || item.emp_id)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.app_text_primary'))
                  Text(`工号: ${item.emp_id}`)
                    .fontSize(12)
                    .fontColor($r('app.color.app_text_secondary'))
                  Text(`${this.roleLabel(item.role)} · ${this.userStatusLabel(item)}${item.phone ? ' · ' + item.phone : ''}`)
                    .fontSize(12)
                    .fontColor(item.is_active ? '#808080' : '#C62828')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button('查看')
                  .height(34)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .onClick((): void => {
                    this.openUserDetail(item);
                  })
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

      if (this.showUserDetail) {
        this.UserDetailOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    if (this.activePage === PAGE_INFO) {
      this.InfoPage()
    } else if (this.activePage === PAGE_SECURITY) {
      this.SecurityPage()
    } else if (this.activePage === PAGE_MESSAGES) {
      this.MessagesPage()
    } else if (this.activePage === PAGE_CREATE_GROUP) {
      this.CreateGroupPage()
    } else if (this.activePage === PAGE_ADMIN && this.isAdminUser()) {
      this.AdminManagementPage()
    } else if (this.activePage === PAGE_USER_SEARCH) {
      this.UserSearchPage()
    } else if (this.activePage === PAGE_API_CONFIG) {
      this.ApiConfigPage()
    } else {
      this.ProfileHome()
    }
  }
}
