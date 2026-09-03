# 02-鸿蒙前端 ArkTS 架构与组件设计

本文档面向鸿蒙前端开发人员，详细拆解工程目录结构、ArkTS 页面组件设计、网络请求拦截器机制以及系统 Symbol 矢量符号的使用规范。

---

## 1. 前端源码目录结构 (frontend/)

```text
frontend/
├── AppScope/                      # 应用全局配置 (app.json5, 图标资源)
├── entry/src/main/
│   ├── module.json5               # 模块配置 (权限: INTERNET, 页面路由配置)
│   └── ets/
│       ├── entryability/          # UIAbility 生命周期入口
│       ├── pages/                 # 主页面集合
│       │   ├── Index.ets          # 主框架页 (Tabs 容器与底部导航栏)
│       │   ├── Login.ets          # 登录页 (凭据记忆、Token 校验)
│       │   ├── WorkspaceDetail.ets# 工作区详情页 (切片设置、MVA 问答面板)
│       │   └── tabs/              # 四大底部 Tab 视图组件
│       │       ├── MonitorTab.ets # 监控设备卡片网格
│       │       ├── WorkspaceTab.ets# 工作区管理列表
│       │       ├── GroupTab.ets   # 小组通讯录与成员卡片选择器
│       │       └── ProfileTab.ets # 个人中心、控制台入口与设置
│       └── utils/                 # 工具库
│           ├── http.ets            # Network 请求封装、Base URL 管理与 Token 拦截
│           └── security.ets        # 账号安全工具与首选项存储
```

---

## 2. ArkTS 页面与 Tab 状态设计

应用主框架采用鸿蒙原生的 `Tabs` 结合自定义 `TabContent` 架构，实现无缝手势滑动与沉浸式体验：

```typescript
// Index.ets 核心逻辑示例
@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  private controller: TabsController = new TabsController();

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
        TabContent() { MonitorTab() }.tabBar(this.NavBarItem(0, '监控', NavIconType.Monitor))
        TabContent() { WorkspaceTab() }.tabBar(this.NavBarItem(1, '工作区', NavIconType.Workspace))
        TabContent() { GroupTab() }.tabBar(this.NavBarItem(2, '小组', NavIconType.Group))
        TabContent() { ProfileTab() }.tabBar(this.NavBarItem(3, '我的', NavIconType.Profile))
      }
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
  }
}
```

---

## 3. HTTP 请求封装与 Token 拦截器 (http.ets)

前端基于 `@ohos.net.http` 实现了统一的异步 HTTP 封装：

- **Base URL 管理**：导出 `BASE_HOST` 与 `BASE_URL`，方便在模拟器 (`10.0.2.2:6006`)、真机及公网环境之间灵活切换。
- **请求头拦截器 (Interceptor)**：自动注入 Authorization 标头：
  ```typescript
  let headers: Record<string, string> = {
    'Content-Type': 'application/json'
  };
  let token = AppStorage.Get<string>('user_token');
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  ```
- **401 Unauthorized 错误拦截**：当服务器返回 401（Token 无效、过期或账号被禁用）时，自动清除本地 Token 并重定向拉起 `Login.ets` 页面。

---

## 4. Pureyes 视觉系统与图标规范

界面采用“取证控制台”视觉方向：中性雾灰承载长时间工作，深海军蓝表示主流程工具，钴蓝只表示选择与可跳转内容，琥珀色用于实时、待处理和关键刻线。设计语言来自调查卷宗、时间轴和视频标注轨，不使用通用管理后台常见的渐变色块、大面积蓝色胶囊和漂浮阴影。

### 4.1 色彩语义

颜色统一从 `resources/base/element/color.json` 和 `resources/dark/element/color.json` 读取，页面代码不应继续新增无语义的蓝色、灰色常量。

| Token | 浅色模式 | 用途 |
| :--- | :--- | :--- |
| `app_page_bg` | `#F1F3F2` | 中性雾灰页面背景 |
| `app_card_bg` | `#FCFDFC` | 调查卡片与内容面板 |
| `app_text_primary` | `#0C2942` | 深海军蓝标题与正文 |
| `app_surface_inverted` | `#0C2942` | 主流程工具键背景 |
| `app_selection` | `#2F6FCE` | 当前选择、时间戳和链接 |
| `app_accent` | `#F0A51B` | 实时、待处理和选中刻线 |
| `app_success` | `#20765F` | 在线、完成状态 |
| `app_danger` | `#B94949` | 删除、失败状态 |

### 4.2 控件尺度

- 页面标题使用 24–26vp，正文使用 13–16vp，工具标签使用 10–12vp。
- 通用图标按钮使用 32–36vp 方形热区和 7–8vp 圆角；头像、状态点等具有明确圆形语义的元素才使用圆形。
- 主流程操作使用 40vp 高的深色矩形工具键，圆角 8vp，并以左侧 3vp 琥珀刻线标记优先级。
- 次级、返回、刷新等操作使用透明底加 1vp 边框；删除仅在最终确认步骤使用实心危险色。
- 参数和筛选项使用下划线式分段选择器，选中项显示 3vp 琥珀底线，不使用一排实心胶囊。
- 卡片圆角以 8–12vp 为主，通过 1vp 边框、左侧状态轨和间距建立层次；常规列表卡片不使用阴影。

### 4.3 操作层级

同一个页面不得把所有动作都画成同样的实心圆角按钮。按下面的层级选择样式：

| 层级 | 典型动作 | 样式 |
| :--- | :--- | :--- |
| 主流程 | 添加视频源、截取片段、新建问答、提交分析 | 深色矩形工具键 + 琥珀刻线 |
| 次级 | 刷新、返回、取消、关闭 | 透明底 + 细边框 |
| 参数 | 帧率、清晰度、时间范围 | 下划线分段选择器 |
| 状态 | 在线、分析中、完成、失败 | 文本、状态点或左侧状态轨 |
| 危险 | 删除记录、移除成员 | 普通阶段仅描边；最终确认可实心红色 |

### 4.4 图标分工

返回、删除、编辑、搜索等通用操作必须使用 HarmonyOS `SymbolGlyph`，以保证小尺寸清晰度、动态换色和系统一致性：

| 通用操作 | 当前符号 |
| :--- | :--- |
| 个人中心 | `$r('sys.symbol.person')` |
| 返回上一级 | `$r('sys.symbol.chevron_left')` |
| 返回工作区首页 | `$r('sys.symbol.house')` |
| 进入详情 | `$r('sys.symbol.chevron_right')` |
| 新增 | `$r('sys.symbol.plus')` |
| 编辑 | `$r('sys.symbol.pencil_line')` |
| 删除 | `$r('sys.symbol.trash')` |
| 关闭/取消 | `$r('sys.symbol.xmark')` |
| 保存/确认 | `$r('sys.symbol.checkmark')` |
| 刷新 | `$r('sys.symbol.arrow_clockwise')` |
| 搜索 | `$r('sys.symbol.magnifyingglass')` |
| 查看 | `$r('sys.symbol.eye')` |
| 发送邀请 | `$r('sys.symbol.paperplane')` |
| 设置 | `$r('sys.symbol.gearshape')` |
| 密码与密钥 | `$r('sys.symbol.lock')` / `$r('sys.symbol.key')` |

```typescript
SymbolGlyph($r('sys.symbol.chevron_left'))
  .fontSize(18)
  .fontColor([$r('app.color.app_text_primary')])
```

主要业务入口使用审核通过的 Pureyes 光学图标。资源统一为 512×512 RGBA PNG，保存在 `resources/base/media/`，选中和未选中状态通过容器背景与透明度区分，不对图片动态染色：

| 业务功能 | 媒体资源 | 主要使用位置 |
| :--- | :--- | :--- |
| 实时监控 | `business_monitor.png` | 主导航、监控空状态 |
| 工作空间 | `business_workspace.png` | 主导航、工作区卡片 |
| AI 问答 | `business_ai_qa.png` | 工作区问答子页 |
| 人员追踪 | `business_person_tracking.png` | 人脸轨迹空状态 |
| 片段剪辑 | `business_clip_trim.png` | 工作区片段子页 |
| 人脸库 | `business_face_library.png` | 工作区人脸子页 |
| 团队协作 | `business_team.png` | 主导航、小组空状态 |
| 安全服务器 | `business_secure_server.png` | 登录页服务器入口 |

```typescript
Image($r('app.media.business_monitor'))
  .width(24)
  .height(24)
  .objectFit(ImageFit.Contain)
```

新增品牌化功能图标时，必须先提交图标清单和预览图进行人工审核；审核通过后再生成独立资源、清理透明通道并接入。品牌图片不得替代返回、Home、刷新、删除等系统操作图标。

---

## 5. 鸿蒙星盾安全与隐私特性集成

前端在构建通用业务的同时，深度集成了 HarmonyOS 官方主推的星盾安全与隐私特性：

1. **密码保管箱与自动填充** (`Login.ets`)：
   使用 `.contentType(ContentType.USER_NAME)` 与 `.contentType(ContentType.PASSWORD)` 标记输入框，打通鸿蒙密码保管箱加密存储与生物特征（指纹/人脸）解锁填充。
2. **窗口隐私防窥防截屏/录屏** (`EntryAbility.ets`)：
   配置 `ohos.permission.PRIVACY_WINDOW` 并调用 `win.setWindowPrivacyMode(true)`，阻断截屏录屏与后台卡片预览泄漏。
