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

## 开发测试要点

开发测试覆盖设备兼容性、权限、任务生命周期和异常恢复。

- **系统能力**：在目标设备上检查凭据填充、截图与录屏权限、端侧人脸归类、分享面板与完成触感；覆盖禁用振动、分享目标不可用和网络中断。
- **服务卡片**：检查 2×2 / 2×4 尺寸下的首次加载、任务切换、手动刷新、运行与完成状态、登录校验、调查定位、重复添加和删除，以及退出登录后的清空。

- **交互动效**：检查主栏与子栏切换、长列表滚动、快速返回、共享标识转场及工具步骤与预处理进度更新。低性能设备可减少位移和缩放，保留状态反馈。

- **通知与权限**：检查授权拒绝、并发任务独立更新、完成通知去重、点击定位及后台任务取消后的恢复；确认会话菜单符合用户权限，运行中拒绝删除，删除会话后视频和人脸记录保留。

界面与操作说明见[功能截图导览](../user-guide/11-interface-tour.md)和[调查通知与桌面小部件](../user-guide/10-investigation-notifications.md)。
