# Pureyes 清眸

面向 HarmonyOS 的小组视频调查应用。成员在工作区整理多个监控或上传视频的片段，提出问题，查看 Agent 的工具执行记录、证据时间点与回答，并在同一调查中继续追问。

![清眸客户端、Flask 服务、视频索引与调查 Agent 的总体架构示意](docs/illustrations/pureyes-architecture.png)

> 上图是功能架构示意；实际界面请看[用户指南中的设备截图](docs/user-guide/01-overview.md#界面演示)。

## 主要功能

| 功能 | 使用方式 |
| :--- | :--- |
| 小组协作 | 选择小组，共享监控、工作区与调查记录；组长邀请成员。 |
| 视频与片段 | 接入监控或上传视频，在工作区截取片段并按需建立检索索引。 |
| 多视频调查 | 在一轮问题中选择多个片段，查看工具步骤、视频时间点及 Markdown 回答。 |
| 连续追问 | 已加入小组的成员可在上一轮结束后追问；运行中可停止本轮。 |
| 人脸线索 | 按片段查看与调整人脸分组；实际归类方式由服务端配置。 |
| 模型配置 | 个人维护自己的 API 配置，小组长可建立供本组使用的配置。 |

![导入视频、截取片段、预处理、跨视频提问与核对证据的流程示意](docs/illustrations/multi-video-investigation.png)

## 文档入口

- [在线使用说明](http://116.62.178.139/) · [快速开始](docs/user-guide/02-quick-start.md) · [调查问答](docs/user-guide/07-ai-multimodal-qa.md)
- [开发者文档](docs/developer-guide/01-architecture-design.md) · [Agent 工具与运行机制](docs/developer-guide/04-ai-mva-engine.md)
- [服务器部署](docs/server-deployment/01-requirements-and-env.md) · [部署步骤](docs/server-deployment/02-backend-deployment-guide.md)

用户界面中的“使用说明”入口也会打开在线文档。首次使用需要管理员提供账号，并选择或加入小组；没有小组时可在【我的】创建小组或接受邀请。

## 仓库结构

| 路径 | 内容 |
| :--- | :--- |
| `frontend/` | HarmonyOS ArkTS 客户端 |
| `backend/` | Flask API、视频处理、检索与调查 Agent |
| `docs/user-guide/` | 面向用户和管理员的操作说明 |
| `docs/developer-guide/` | 前后端与 AI 模块设计 |
| `docs/server-deployment/` | 环境、模型文件和部署维护 |

示意图用于解释工作流程，不能代替实际截图、算法评测或身份鉴定结果；视频中的人脸归类及跨镜头关联需要人工核对。
