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
        TabContent() { MonitorTab() }.tabBar(this.TabBuilder(0, '监控', $r('sys.symbol.video')))
        TabContent() { WorkspaceTab() }.tabBar(this.TabBuilder(1, '工作区', $r('sys.symbol.folder')))
        TabContent() { GroupTab() }.tabBar(this.TabBuilder(2, '小组', $r('sys.symbol.person_2')))
        TabContent() { ProfileTab() }.tabBar(this.TabBuilder(3, '我的', $r('sys.symbol.person_crop_circle')))
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

## 4. HarmonyOS 系统符号与 UI 规范

为了遵循 HarmonyOS NEXT 的设计美学，前端淘汰了传统打包 PNG/SVG 图片的做法，全面升级为 HarmonyOS 系统级 Symbol 图标资源：

| 业务功能 | 系统符号引用 | 视觉呈现与效果 |
| :--- | :--- | :--- |
| **实时监控** | `$r('sys.symbol.video')` | 视频摄像机标态符号 |
| **工作区/文件夹** | `$r('sys.symbol.folder')` | 资料文件袋符号 |
| **团队/小组** | `$r('sys.symbol.person_2')` | 双人协同沟通符号 |
| **个人中心** | `$r('sys.symbol.person_crop_circle')` | 圆形头像骨架符号 |
| **新增/创建** | `$r('sys.symbol.plus_circle')` | 柔和带圈加号按钮 |
| **播放/预览** | `$r('sys.symbol.play_circle')` | 视频播放多媒体符号 |

```typescript
// 渲染 SymbolIcon 的代码规范
SymbolIcon($r('sys.symbol.plus_circle'))
  .fontSize(24)
  .fontColor([$r('sys.color.ohos_id_color_emphasize')])
```
