# 06. 鸿蒙原生能力接入

本文记录客户端实际接入的 HarmonyOS 能力、使用位置和适用范围。项目当前面向手机，工作区协作与视频 Agent 由服务端实现；它们本身不等于鸿蒙跨设备协同。

| 能力 | 代码位置 | 当前用途 |
| --- | --- | --- |
| Core Vision Kit 人脸比对 | `frontend/entry/src/main/ets/utils/harmonyFaces.ets`、`pages/WorkspaceDetail.ets` | 在启用手机端重分类的后端配置下，下载待分组的人脸抓拍图，在手机上调用 `faceComparator` 比对并提交分组结果。视频抽帧、人脸检测及轨迹生成仍由后端完成。 |
| Asset Store Kit | `frontend/entry/src/main/ets/utils/security.ets` | 保存会话令牌与服务器地址等本地敏感值；读取失败时由登录流程处理。服务端模型 API Key 不通过这里分发到组员手机。 |
| 隐私窗口 | `frontend/entry/src/main/ets/entryability/EntryAbility.ets`、`frontend/entry/src/main/module.json5` | 主窗口调用 `setWindowPrivacyMode(true)`，限制系统截屏和录屏。需在目标设备验证系统效果；调用失败会记录日志。 |
| 系统凭据填充 | `frontend/entry/src/main/ets/pages/Login.ets` | 账号与密码输入框分别标注 `ContentType.USER_NAME`、`ContentType.PASSWORD`，允许系统识别凭据字段。是否提示保存及如何解锁由设备和用户设置决定。 |
| Share Kit 系统分享 | `frontend/entry/src/main/ets/pages/components/AgentConversationPanel.ets` | 已完成且有结论的调查轮次提供“分享结论”；点击后分享问题与 Markdown 原文，由用户在系统面板选择目标。不会自动分享视频、截图、令牌或服务器地址。 |
| Sensor Service Kit 触感 | `frontend/entry/src/main/ets/pages/components/AgentConversationPanel.ets` | 页面在轮询中看到任务完成时发出一次 60 ms 轻触感。设备无马达或系统禁用振动时静默退化，结果仍正常显示。 |
| Form Kit 服务卡片 | `frontend/entry/src/main/ets/investigationform/`、`utils/investigationCard.ets` | 2×2 桌面卡片展示最近一次打开的调查状态、工具步骤数和最近同步时间，点击后在登录验证通过时进入对应工作区的调查轮次。 |

## 人脸重分类的边界

手机端模式需由后端配置启用；普通用户和超级管理员都没有界面切换入口。该模式使用 Core Vision Kit 的 `faceComparator.init()`、`compareFaces()` 和 `release()`，并释放下载图片的 PixelMap。后端模式仍使用后端的人脸模型。手机端比对需要可访问的抓拍图和实际设备支持；具体阈值、隐私与准确率需用真实设备及数据验证。

## 隐私与分享

隐私窗口不等同于“检测旁人注视并自动模糊”的 AI 防窥功能。项目没有接入注视检测、姿态感知，也没有实现跨设备接续、碰一碰分享或系统级分布式任务。分享调查文字是用户明确点击后的外发操作，使用前应确认目标和内容。系统分享面板若无法启动，界面显示失败提示。

`module.json5` 声明 `ohos.permission.PRIVACY_WINDOW` 与 `ohos.permission.VIBRATE`。触感只在页面当前轮询观察到完成时发生；应用退出或未打开调查页时不会推送通知。

## 调查服务卡片的数据流

调查页加载会话及轮询任务时，将工作区 ID、会话 ID、状态、阶段、工具步骤数和同步时刻写入本地 Preferences，并通过 Form Kit 的 `formProvider.updateForm` 主动更新已添加的卡片。`FormExtensionAbility` 在卡片添加、系统请求刷新和移除时维护卡片 ID；卡片只显示脱敏状态，不显示问题、结论、视频、人脸、API Key 或令牌。退出登录或会话失效时清空卡片内容。

这是**最近同步状态**，不是云端实时推送：只有应用中调查页处于运行或重新打开会话时才从服务端获取并推送状态；应用关闭后，桌面卡片不会自行轮询服务端，因而可能暂时显示“调查进行中”。卡片始终展示最近同步时间。点击卡片会先走现有的服务端会话验证，再定位到工作区；无有效登录时进入登录页。卡片只保存最近查看的一轮调查，而不是全组任务总览。

## 设备验证

在 HarmonyOS 6.1 手机上验证登录填充提示、隐私窗口的截屏表现、人脸重分类、系统分享面板及完成触感。卡片需额外验证：添加桌面后的首次加载、任务运行和完成时刷新、应用退出后的同步时刻、点击后的登录校验与调查定位、用户退出登录后的清空、重复添加和删除卡片。尤其要测试无振动设备或关闭振动、分享目标不可用及网络中断。本页描述的是代码接入状态，并不代替实机验收。
