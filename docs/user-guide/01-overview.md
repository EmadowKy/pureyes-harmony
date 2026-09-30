# 清眸用户指南

清眸用于小组共享监控与视频调查。先登录并选择小组，再从【监控】查看画面、从【工作区】整理片段和调查记录、从【小组】查看成员；账号和模型配置在【我的】中管理。

## 按使用场景查找

| 我要做什么 | 阅读哪一篇 |
| :--- | :--- |
| 第一次登录、选择小组、找到主要入口 | [快速开始](02-quick-start.md) |
| 收到邀请、创建小组、查看通讯录 | [小组协作](04-group-collaboration.md) |
| 看实时监控或回放录像 | [监控与回放](05-live-monitoring.md) |
| 截取片段、查看预处理和人脸线索 | [工作区与视频片段](06-workspace-management.md) |
| 对多个片段提问、查看证据、继续追问 | [调查问答](07-ai-multimodal-qa.md) |
| 在通知栏或桌面查看调查进度 | [调查通知与桌面小部件](10-investigation-notifications.md) |
| 浏览各个功能的实际界面 | [功能截图导览](11-interface-tour.md) |
| 修改资料、密码或模型配置 | [个人中心](09-profile-and-settings.md)与[账号安全](03-authentication.md) |
| 管理员工账号（仅管理员） | [用户管理](08-admin-console.md) |

> 监控、工作区和小组通讯录需要先选择一个已加入的小组。没有可选小组时，可在【我的】新建小组，或从【我的消息】接受邀请。

## 界面演示

下面按工作区、账号邀请和监控介绍主要页面。更多界面见[功能截图导览](11-interface-tour.md)。

### 有视频、有线索的调查工作区

进入工作区后，【片段】【人脸】【问答】三个主页面保留底栏；截取视频或进入具体调查时收起底栏，点击左上角返回按钮可回到原主页面。

<div class="screenshot-grid">
<figure><img src="/screenshots/20260929/15-face-groups.webp" alt="预处理生成的人脸分组卡片" loading="lazy" /><figcaption>人脸分组与跨视频记录</figcaption></figure>
<figure><img src="/screenshots/20260929/23-investigation-references.webp" alt="调查详情展开引用的三个视频片段" loading="lazy" /><figcaption>固定证据范围与可定位的回答</figcaption></figure>
</div>

可从[工作区与视频片段](06-workspace-management.md)开始导入视频，也可直接阅读[调查问答](07-ai-multimodal-qa.md)。

### 账号与邀请

管理员可在【我的 → 用户管理】创建账号；普通成员使用管理员提供的工号和密码登录。组长发出邀请后，被邀请人到【我的 → 我的消息】接受。详见[小组协作](04-group-collaboration.md)。

![管理员用户列表中显示新建的演示成员](../image/admin-user-list.png)

| 收到邀请 | 接受后的成员列表 |
| :---: | :---: |
| ![演示成员收到清眸演示组邀请](../image/group-invitation-received.png) | ![清眸演示组已有两名正式成员](../image/group-members-active.png) |

### 工作区与监控

选择小组后，在【工作区】点击【新建】创建工作区。进入后截取视频片段，再在【问答】中选择片段提问。工作区卡片显示名称与调查轮数。详见[工作区与视频片段](06-workspace-management.md)。

![清眸演示组中建立的展厅视频排查演示工作区](../image/workspace-created.png)

【监控】页用于添加摄像头或视频流。没有设备时显示添加入口；接入后可查看实时画面、回放录像和截取片段。详见[监控与回放](05-live-monitoring.md)。

![清眸演示组的监控页提示尚未添加视频源](../image/monitor-no-video-source.png)

## 阅读顺序

首次使用建议从[快速开始](02-quick-start.md)入手；进入工作区后，按[片段](06-workspace-management.md) → [调查问答](07-ai-multimodal-qa.md)的顺序操作。管理员只需在管理账号时阅读[用户管理](08-admin-console.md)。
