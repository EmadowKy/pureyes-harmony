# 06. 鸿蒙原生能力接入

本文记录客户端实际接入的 HarmonyOS 能力、使用位置和适用范围。项目当前面向手机，工作区协作与视频 Agent 由服务端实现；它们本身不等于鸿蒙跨设备协同。

![清眸的五类鸿蒙原生能力：端侧人脸比对、桌面小部件、任务通知、交互动效、安全与隐私](/illustrations/harmony-native-features.webp)

图中结合人脸、调查、桌面卡片和系统通知的真实截图展示使用场景，下表对应具体代码与接入方式。

| 能力 | 代码位置 | 当前用途 |
| --- | --- | --- |
| Core Vision Kit 人脸比对 | `frontend/entry/src/main/ets/utils/harmonyFaces.ets`、`pages/WorkspaceDetail.ets` | 在启用手机端重分类的后端配置下，下载待分组的人脸抓拍图，在手机上调用 `faceComparator` 比对并提交分组结果。视频抽帧、人脸检测及轨迹生成仍由后端完成。 |
| Asset Store Kit | `frontend/entry/src/main/ets/utils/security.ets` | 保存会话令牌与服务器地址等本地敏感值；读取失败时由登录流程处理。服务端模型 API Key 不通过这里分发到组员手机。 |
| 隐私窗口 | `frontend/entry/src/main/ets/utils/captureProtection.ets`、`frontend/entry/src/main/ets/entryability/EntryAbility.ets` | 默认限制系统截屏和录屏；用户在账号安全页验证当前密码后可更改联合权限。设置按账号保存，启动先开启保护、验证登录后应用设置，退出登录恢复保护。需在目标设备验证系统效果。 |
| 系统凭据填充 | `frontend/entry/src/main/ets/pages/Login.ets` | 账号与密码输入框分别标注 `ContentType.USER_NAME`、`ContentType.PASSWORD`，允许系统识别凭据字段。是否提示保存及如何解锁由设备和用户设置决定。 |
| Share Kit 系统分享 | `frontend/entry/src/main/ets/pages/components/AgentConversationPanel.ets` | 已完成且有结论的调查轮次提供“分享结论”；点击后分享问题与 Markdown 原文，由用户在系统面板选择目标。不会自动分享视频、截图、令牌或服务器地址。 |
| Sensor Service Kit 触感 | `frontend/entry/src/main/ets/pages/components/AgentConversationPanel.ets` | 页面在轮询中看到任务完成时发出一次 60 ms 轻触感。设备无马达或系统禁用振动时静默退化，结果仍正常显示。 |
| Form Kit 服务卡片 | `frontend/entry/src/main/ets/investigationform/`、`utils/investigationCard.ets` | 2×2 / 2×4 小鸮卡片展示调查阶段、用时、工具步骤和同步时间；支持切换多个任务、手动刷新、空闲总览及跳转调查。 |
| Notification Kit / Background Tasks Kit | `frontend/entry/src/main/ets/utils/investigationTasks.ets` | 系统通知授权、每项调查进度与完成通知；运行期间申请 `dataTransfer` 连续后台任务，以同步服务端状态。最后一项任务结束后停止后台任务。 |
| ArkUI 页面动效 | `frontend/entry/src/main/ets/pages/` | 主栏及工作区子栏选中态、列表卡片按压与入场、个人页切换、登录输入焦点和调查工具步骤采用短时属性动画及转场；调查记录标识使用 `geometryTransition` 共享元素转场。 |
| 系统媒体／文件选择器 | `pages/WorkspaceDetail.ets`、`utils/localVideoUpload.ets` | PhotoViewPicker 选择相册视频，DocumentViewPicker 选择文件；读取用户授予的单文件 URI，私有缓存准备原生 multipart 上传，不扫描媒体库。 |

## 界面动效

调查列表进入或返回详情时，利用相同调查 ID 连接列表标识和详情标识；页面内容沿阅读方向小幅移动。工具步骤只在新增时启动入场动画，轮询更新已有步骤不重复播放。展开参数与证据时结合透明度和少量位移，避免长工具链持续跳动。这些效果由 ArkUI `animateTo`、`transition` 和 `geometryTransition` 实现；它们属于应用的交互设计，不代表接入了 HarmonyOS 7 的系统级空间计算或系统界面动画。

其他页面沿用约 130–220 ms 的轻量节奏：主栏和工作区子栏的图标底色与大小平滑变化，工作区、监控源、视频片段及人脸卡片按压时轻微缩放，列表数据与空状态切换时短暂淡入。个人页子页与成员详情使用小幅位移或淡入；登录输入框用边框颜色反馈焦点。监控视频本身与回放时间轴不做整屏转场，避免干扰查看和拖动。列表项使用稳定 ID 作为键，预处理进度变化不会反复触发入场。

## 人脸重分类的边界

手机端模式需由后端配置启用；普通用户和超级管理员都没有界面切换入口。该模式使用 Core Vision Kit 的 `faceComparator.init()`、`compareFaces()` 和 `release()`，并释放下载图片的 PixelMap。后端模式仍使用后端的人脸模型。手机端比对需要可访问的抓拍图和实际设备支持；具体阈值、隐私与准确率需用真实设备及数据验证。

## 隐私与分享

隐私窗口不等同于“检测旁人注视并自动模糊”的 AI 防窥功能。项目没有接入注视检测、姿态感知，也没有实现跨设备接续、碰一碰分享或系统级分布式任务。分享调查文字是用户明确点击后的外发操作，使用前应确认目标和内容。系统分享面板若无法启动，界面显示失败提示。

`module.json5` 声明 `ohos.permission.PRIVACY_WINDOW`、`ohos.permission.VIBRATE` 与 `ohos.permission.KEEP_BACKGROUND_RUNNING`。触感只在页面当前轮询观察到完成时发生；系统通知则由应用级任务中心管理，不依赖某个调查页。通知不显示问题、标题、答案或视频，只展示阶段、用时和工具步骤。

## 调查服务卡片的数据流

应用级任务中心每约 5 秒获取 `/api/workspaces/agent/tasks`，接口仅返回当前账号已加入小组的调查最新轮次。所有运行中任务及最近 20 条结束记录写入本地 Preferences，经 `formProvider.updateForm` 更新已添加卡片。每张卡片独立保存选择项，优先在运行任务间切换；无运行任务时展示最新记录和整体计数。三种小鸮由本地 SVG 绘制，不依赖外部图片服务。卡片显示调查标题及状态，不展示答案、视频、人脸、API Key 或令牌；标题可能来源于首问，不能视为完全脱敏。退出登录清空卡片并取消调查通知；迟到的网络响应通过代次校验丢弃。

这是**最近同步状态**，不是 Push Kit 云端推送。应用在前台及连续后台任务存续期间轮询；普通进度通知同一任务约 15 秒更新一次，完成通知在观察到状态变化时立即发出且去重。连续后台任务由系统提供常驻入口，应用不使用 SDK 不支持的普通通知 `isUnremovable` / `isOngoing` 属性。系统可因网络流量不足或用户取消而终止 `dataTransfer` 任务，不能保证应用被杀后仍通知。要实现这一能力，还需配置 Push Kit 并由服务端发送推送。

`FormExtensionAbility` 仅在添加、刷新和点击事件时执行，不进行常驻轮询。卡片的【↻】会重新读取安全登录状态，调用任务接口并更新快照；切换按钮读取本地快照。同步时间始终可见，避免将缓存当成实时状态。点击卡片或通知先走现有登录验证，再定位工作区与会话。

## 设备验证

文档新增[功能截图导览](../user-guide/11-interface-tour.md)和[通知与桌面小鸮](../user-guide/10-investigation-notifications.md)。2026-09-29 模拟器截图展示已完成调查、工具链、人脸抓拍和 2×2 空闲卡片；不证明运行中通知、2×4 卡片或真机端侧人脸比对已经验收。原有截图使用临时构建采集；当前版本默认启用保护，允许用户验证密码后更改截图录屏权限。

在 HarmonyOS 6.1 手机上验证登录填充提示、隐私窗口的截屏表现、人脸重分类、系统分享面板及完成触感。卡片需额外验证：添加桌面后的首次加载、任务运行和完成时刷新、应用退出后的同步时刻、点击后的登录校验与调查定位、用户退出登录后的清空、重复添加和删除卡片。尤其要测试无振动设备或关闭振动、分享目标不可用及网络中断。本页描述的是代码接入状态，并不代替实机验收。

动效需在真机上检查主栏与子栏切换、长列表滚动和快速返回时是否平稳；检查调查列表往返时共享标识的连续性，以及工具步骤和片段预处理进度更新时是否闪烁。低性能设备可减少位移和缩放而保留状态反馈。

通知需验证授权拒绝、并发任务独立更新、完成通知只出现一次、点击定位、后台任务被取消及强制关闭应用后的恢复。会话管理需验证普通成员无管理入口、创建者与管理员可管理、运行中拒绝删除，以及删除后视频和人脸仍保留。
