# 06. 鸿蒙原生能力接入

清眸通过 HarmonyOS 系统能力实现端侧人脸比对、桌面调查卡片、任务通知、交互动效及隐私保护。手机负责交互与状态展示，服务端负责视频处理、工作区协作和调查 Agent 运行。

![清眸的五类鸿蒙原生能力：端侧人脸比对、桌面小部件、任务通知、交互动效、安全与隐私](/illustrations/harmony-native-features.webp)

下表列出各项能力的代码位置与用途。

| 能力 | 代码位置 | 用途 |
| --- | --- | --- |
| Core Vision Kit 人脸比对 | `frontend/entry/src/main/ets/utils/harmonyFaces.ets`、`pages/WorkspaceDetail.ets` | 在启用手机端重分类的后端配置下，下载待分组的人脸抓拍图，在手机上调用 `faceComparator` 比对并提交分组结果。视频抽帧、人脸检测及轨迹生成仍由后端完成。 |
| Asset Store Kit | `frontend/entry/src/main/ets/utils/security.ets` | 保存会话令牌与服务器地址等本地敏感值；读取失败时由登录流程处理。服务端模型 API Key 不通过这里分发到组员手机。 |
| 隐私窗口 | `frontend/entry/src/main/ets/utils/captureProtection.ets`、`frontend/entry/src/main/ets/entryability/EntryAbility.ets` | 默认限制系统截屏和录屏；用户在窗口隐私页验证当前密码后可更改联合权限。设置按账号保存，启动先开启保护、验证登录后应用设置，退出登录恢复保护。 |
| 系统凭据填充 | `frontend/entry/src/main/ets/pages/Login.ets` | 账号与密码输入框分别标注 `ContentType.USER_NAME`、`ContentType.PASSWORD`，允许系统识别凭据字段。是否提示保存及如何解锁由设备和用户设置决定。 |
| Share Kit 系统分享 | `frontend/entry/src/main/ets/pages/components/AgentConversationPanel.ets` | 已完成且有结论的调查轮次提供“分享结论”；点击后分享问题与 Markdown 原文，由用户在系统面板选择目标。不会自动分享视频、截图、令牌或服务器地址。 |
| Sensor Service Kit 触感 | `frontend/entry/src/main/ets/pages/components/AgentConversationPanel.ets` | 页面在轮询中看到任务完成时发出一次 60 ms 轻触感。设备无马达或系统禁用振动时静默退化，结果仍正常显示。 |
| Form Kit 服务卡片 | `frontend/entry/src/main/ets/investigationform/`、`utils/investigationCard.ets` | 2×2 / 2×4 小鸮卡片展示调查阶段、用时、工具步骤和同步时间；支持切换多个任务、手动刷新、空闲总览及跳转调查。 |
| Notification Kit / Background Tasks Kit | `frontend/entry/src/main/ets/utils/investigationTasks.ets` | 系统通知授权、每项调查进度与完成通知；运行期间申请 `dataTransfer` 连续后台任务，以同步服务端状态。最后一项任务结束后停止后台任务。 |
| Window Kit 闪控窗／闪控球 | `utils/investigationFloat.ets`、`utils/investigationFloatState.ets`、`pages/InvestigationFloatWindow.ets` | HarmonyOS 7 上由用户主动开启跨应用任务窗口，支持系统窗球联动、多任务切换、阶段与耗时展示，以及返回所选调查。 |
| ArkUI 页面动效 | `frontend/entry/src/main/ets/pages/` | 主栏及工作区子栏选中态、列表卡片按压与入场、个人页切换、登录输入焦点和调查工具步骤采用短时属性动画及转场；调查记录标识使用 `geometryTransition` 共享元素转场。 |
| 系统媒体／文件选择器 | `pages/WorkspaceDetail.ets`、`utils/localVideoUpload.ets` | PhotoViewPicker 选择相册视频，DocumentViewPicker 选择文件；读取用户授予的单文件 URI，私有缓存准备原生 multipart 上传，不扫描媒体库。 |

## 界面动效

调查列表进入或返回详情时，利用相同调查 ID 连接列表标识和详情标识，页面内容沿阅读方向小幅移动。工具步骤只在首次出现时启动入场动画，轮询更新已有步骤不重复播放。展开参数与证据时结合透明度和少量位移。这些效果由 ArkUI `animateTo`、`transition` 和 `geometryTransition` 实现。

其他页面沿用约 130–220 ms 的轻量节奏：主栏和工作区子栏的图标底色与大小平滑变化，工作区、监控源、视频片段及人脸卡片按压时轻微缩放，列表数据与空状态切换时短暂淡入。个人页子页与成员详情使用小幅位移或淡入；登录输入框用边框颜色反馈焦点。监控视频本身与回放时间轴不做整屏转场，避免干扰查看和拖动。列表项使用稳定 ID 作为键，预处理进度变化不会反复触发入场。

## 端侧人脸归类

归类模式由后端的 `FACE_RECOGNITION_BACKEND` 配置：`server` 使用服务端人脸模型，`harmony` 由支持 Core Vision Kit 的手机读取抓拍图并完成比对。配置方法见[模型环境变量](../server-deployment/01-requirements-and-env.md#_4-视觉模型路径环境变量)。

手机端依次调用 `faceComparator.init()`、`compareFaces()` 和 `release()`，按比对结果提交分组指派，处理结束后释放下载图片的 PixelMap。抓拍下载需要有效登录状态和工作区小组权限；相似度阈值应结合目标视频的清晰度、遮挡和拍摄角度进行校准。

## 隐私与分享

隐私窗口通过系统权限控制截图与录屏。用户在【我的 → 窗口隐私】切换开关后，服务端验证当前账号密码，再应用新设置；退出登录恢复保护。

点击【分享结论】后，Share Kit 打开系统分享面板，由用户选择接收目标。分享内容包含问题和 Markdown 结论，视频与截图留在应用内。分享面板启动失败时，页面显示错误提示。

`module.json5` 声明 `ohos.permission.PRIVACY_WINDOW`、`ohos.permission.VIBRATE` 与 `ohos.permission.KEEP_BACKGROUND_RUNNING`。触感只在页面当前轮询观察到完成时发生；系统通知则由应用级任务中心管理，不依赖某个调查页。通知不显示问题、标题、答案或视频，只展示阶段、用时和工具步骤。

## 调查服务卡片的数据流

应用级任务中心每约 5 秒获取 `/api/workspaces/agent/tasks`，接口返回当前账号已加入小组的调查最新轮次。所有运行中任务及最近 20 条结束记录写入本地 Preferences，经 `formProvider.updateForm` 更新已添加卡片。每张卡片独立保存选择项，优先在运行任务间切换；无运行任务时展示最新记录和整体计数。三种小鸮状态由本地 SVG 绘制。

卡片显示调查标题及状态，答案、视频、人脸和凭据保留在应用内。标题可由首问生成，公开桌面展示前可在会话菜单中修改。退出登录清空卡片并取消调查通知；迟到的网络响应通过代次校验丢弃。

状态通过前台及连续后台任务期间的轮询同步。普通进度通知同一任务约 15 秒更新一次，完成通知在观察到状态变化后立即发出并去重。系统为 `dataTransfer` 连续后台任务提供常驻入口；系统终止后台任务或应用进程后，同步暂停，重新打开应用时恢复。

`FormExtensionAbility` 仅在添加、刷新和点击事件时执行，不进行常驻轮询。卡片的【↻】会重新读取安全登录状态，调用任务接口并更新快照；切换按钮读取本地快照。同步时间始终可见，避免将缓存当成实时状态。点击卡片或通知先走现有登录验证，再定位工作区与会话。

## 闪控窗与闪控球

### 系统能力与签名授权

闪控使用 `@kit.ArkUI` 的 `floatView`（API 26）与 `floatingBall`，不使用应用内遮罩模拟悬浮窗。调用前通过 `deviceInfo.apiAvailable('26.0.0')`、系统能力与两个模块的可用性检查；最低 API 23 的应用仍可构建，不支持闪控的设备使用现有通知、卡片和应用内进度。

`module.json5` 声明以下权限：

| 权限 | 授权条件 |
| --- | --- |
| `ohos.permission.FLOAT_VIEW` | 用户授权；声明用途说明与使用场景，首次主动开启时申请，拒绝后再次点击才进入系统授权设置。 |
| `ohos.permission.USE_FLOAT_BALL` | 系统授权，用于创建与绑定闪控球。 |

SDK 26.0.0.105 的权限定义中，两项均为 `system_basic`、`provisionEnable: true`。接入设备前，需按华为应用能力申请流程取得对应授权，并重新生成包含权限的签名 Profile；仅在模块声明权限或获得运行时弹窗授权并不足够。检查 Profile 的 `acls.allowed-acls`，不要手改已签名 Profile、提升应用等级或将密钥提交到仓库。构建与签名通过不替代设备上的权限验收。

权限申请需描述真实业务场景：用户主动开启视频调查进度展示，查看阶段、用时与步骤，点击返回核验证据，不展示营销内容或敏感画面。华为[闪控球权限申请答复](https://developer.huawei.com/consumer/cn/forum/topic/0204223829402686257)对开放场景作了限制；不在列举范围的场景可提交 UX 设计等材料申请例外审核。清眸的视频调查进度应按实际用途说明，不套用其他业务类型，是否批准以审核结果为准。接口参考见 [floatView](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-floatview)。

### 状态与交互

任务中心每次成功获取 `/api/workspaces/agent/tasks` 后把状态传入 `InvestigationFloat.update()`，再通过独立 `LocalStorage` 提供给窗口页面；窗口不读取接口密钥，不单独轮询，也不下载画面。只复制任务与路由标识、通用阶段、步骤数和耗时，不复制标题、问题、答案及工具参数。退出登录先清空共享快照，再关闭系统窗口；通过代次校验丢弃迟到的授权结果和窗口更新。

先创建两个控制器，设置窗口页面，再调用 `floatView.bind()`，最后启动闪控窗；系统负责收起为球和点击展开。初始尺寸约为 280×220 vp，根据设备像素密度及系统尺寸、宽高比约束调整，窗口内可滚动。串行队列避免创建、更新、关闭互相穿插；`start()` 返回后继续等待 `STARTED`，关闭时等待窗和球的 `STOPPED` 回调后再解绑，并设有超时清理。

窗口每秒更新本地耗时，闪控球普通内容更新至多每 10 秒一次，所选任务状态变化立即更新；网络数据仍来自任务中心。请求失败时冻结计时，超过 20 秒没有新快照的运行中任务标记同步中断，终态用时不再增加。已完成任务不会仅因后台停止轮询而被误报为中断。追问替换任务 ID 时继续跟随同一会话，删除记录后选择仍有权限的其他任务或显示空状态。

完成时保留结果状态，不自动打开主界面。只有用户点击【查看】才调用 `restoreMainWindow()`，沿用通知与卡片的登录及工作区校验，再关闭闪控；未申请自动拉起主窗口权限。用户或系统关闭窗口后，后续轮询不会重新创建窗口，服务器调查不受关闭影响。系统取消后台同步时显示提示，恢复同步后清除；进程被终止后需要重新打开应用。

### 验证

`frontend/tests/investigationFloat.test.cjs` 覆盖任务选择与切换、追问跟随、隐私字段、密度与比例约束、过期与断网计时、拒绝授权、重复开启、窗球切换、异步关闭、返回路由，以及退出登录与迟到授权竞态。`investigationTasks.test.cjs` 验证任务中心与通知、卡片、闪控之间的状态分发。

设备验收需使用具备闪控能力的 HarmonyOS 7 环境及已授权 Profile，检查系统授权弹窗、跨应用展示、窗球联动、旋转与字体放大、并发调查、断网恢复、完成返回、主动关闭及退出登录。模块测试使用模拟系统接口，不代表系统窗口已在设备上运行。

## 沉浸光感与调查动效

API 26 的 ArkUI 沉浸光感用于主导航、工作区底栏、菜单、模型选择及小型系统弹窗。入口模块通过 `ohos.arkui.UIMaterial.state = enable` 开启；底栏使用原生 `Tabs`、`BottomTabBarStyle` 和 `barFloatingStyle`，不在普通 `Row` 上模拟系统材质。原生材质的表现随设备算力、系统光感强度和深浅色模式调整。

`utils/appMotion.ets` 集中管理动效时长、材质兼容分支和系统“减弱动效”监听。API 23—25 保留普通原生底栏，不调用 API 26 材质接口。进入工作区页面时采用短距离位移与淡入；切换页面的待执行动画会取消，页面退出后不保留动画计时器。

调查中的引用片段、工具参数与过程记录采用展开收起和箭头旋转。新工具步骤出现时提供轻量反馈，已有工具轮询更新不重复播放整条消息的入场动画；任务结束时，运行区域收起并过渡到答案。会话列表与调查详情继续使用共享标识转场。

片段预览由原生弹窗承载，打开与关闭采用短时过渡。包含视频的预览弹窗禁用沉浸材质，保持不透明阅读底色，不在持续播放的视频上叠加折射和模糊。普通界面也避免反复嵌套材质。

系统开启“减弱动效”后，这些自定义位移、旋转和入场过渡时长归零；状态、内容与操作入口仍保留。系统材质效果由系统设置管理。

参考：[开启沉浸光感](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-enable)、[功耗优化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-constraints)。

## 开发测试要点

开发测试覆盖设备兼容性、权限、任务生命周期和异常恢复。

- **系统能力**：在目标设备上检查凭据填充、截图与录屏权限、端侧人脸归类、分享面板与完成触感；覆盖禁用振动、分享目标不可用和网络中断。
- **服务卡片**：检查 2×2 / 2×4 尺寸下的首次加载、任务切换、手动刷新、运行与完成状态、登录校验、调查定位、重复添加和删除，以及退出登录后的清空。

- **交互动效**：检查主栏与子栏切换、长列表滚动、快速返回、共享标识转场及工具步骤与预处理进度更新。低性能设备可减少位移和缩放，保留状态反馈。

- **通知与权限**：检查授权拒绝、并发任务独立更新、完成通知去重、点击定位及后台任务取消后的恢复；确认会话菜单符合用户权限，运行中拒绝删除，删除会话后视频和人脸记录保留。

界面与操作说明见[功能截图导览](../user-guide/11-interface-tour.md)和[调查通知与桌面小部件](../user-guide/10-investigation-notifications.md)。
