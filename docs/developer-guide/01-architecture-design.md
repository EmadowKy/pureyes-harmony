# 01-系统全局架构设计与数据流

本文面向软件架构师与系统工程师，详细阐述 Pureyes 鸿蒙多模态视觉监控与分析系统的分层架构、通信协议与端到端数据流向。

---

## 1. 全局分层架构图

系统采用标准的前后端分离 + 大模型集中推理三层架构设计，AI 视觉引擎已全面升级为 **MVA_v2 (ReAct Multi-Agent 架构)**：

```mermaid
graph TB
    subgraph "前端应用层 (HarmonyOS 5.0 NEXT)"
        UI[ArkUI 界面层 Index / Tabs / WorkspaceDetail]
        State[AppStorage / LocalStorage 状态管理]
        HTTPClient[http.ets 网络层 & Token 拦截器]
    end

    subgraph "后端服务层 (Python Flask)"
        API[Flask RESTful API 路由分发]
        Auth[Auth / JWT 校验 & 黑名单熔断]
        ORM[SQLAlchemy ORM 数据访问]
        DB[(SQLite / MySQL 数据库 user.db)]
    end

    subgraph "AI 多模态分析层 MVA_v2 (PyTorch CUDA)"
        MVA2[MVA_v2 ReAct Multi-Agent 思考引擎]
        LLM[多模态视觉大语言模型 API]
        YOLO[YOLOv8 + ByteTrack 跨帧跟踪引擎]
        VectorDB[OSNet / CLIP 时空特征向量数据库]
        FFmpeg[FFmpeg 视频流转码 & 采样抽帧器]
    end

    UI --> HTTPClient
    HTTPClient -- "HTTP/HTTPS (RESTful API + JWT)" --> API
    API --> Auth
    Auth --> ORM --> DB
    API --> MVA2
    MVA2 --> FFmpeg
    MVA2 --> YOLO
    MVA2 --> VectorDB
    MVA2 --> LLM
```

---

## 2. 端到端数据流演进

以用户在客户端提出“查找视频中穿红衣服的人”为例，整体数据流流动如下：

```mermaid
sequenceDiagram
    autonumber
    actor Dev as HarmonyOS App (ArkTS)
    participant Backend as Flask API Server
    participant DB as SQLite DB
    participant Engine as MVA_v2 Engine (pipeline & agents)
    participant LLM as 多模态视觉大模型 API

    Dev->>Backend: POST /api/workspaces/:id/upload-video (上传视频源)
    Dev->>Backend: POST /api/workspaces/:id/segments (创建切片)
    Backend->>Engine: 异步启动采样切片 (Sample FPS=1.0, 1080P)
    Engine->>Engine: FFmpeg 抽帧 + YOLOv8/ByteTrack 生成 TrackID 与向量库
    Engine->>DB: 更新 WorkspaceVideoSegment 状态为 completed
    Dev->>Backend: GET /api/workspaces/:id/segments (刷新预处理进度)
    Backend-->>Dev: 返回切片就绪 (status: completed)

    Dev->>Backend: POST /api/workspaces/:id/qa (包含 segment_ids, question)
    Backend->>Engine: 启动 ReAct Agent (Thought -> Tool Call -> Observation)
    Engine->>LLM: 图像序列/TrackID + System Prompt 输入大模型
    LLM-->>Engine: 生成结构化 JSON (时间戳、片段描述、置信度)
    Engine->>DB: 保存问答记录 QARecord
    Backend-->>Dev: 返回 task_id，客户端轮询状态并展示文本回答
    Dev->>Dev: 高亮关键帧与时间轴，点击自动跳帧播放
```

---

## 3. 通信协议与数据格式

- **传输协议**：HTTP/1.1 与 HTTP/2；生产部署必须在反向代理层启用 HTTPS。
- **数据交互格式**：全站使用标准 `application/json` 规范。
- **静态资源与流媒体**：
  - 抓拍快照与缩略图：使用服务端签发的限时 `media_token` 地址。
  - 视频切片流：`/api/video/...` 支持 HTTP Range 请求；每次访问同时校验签名范围和当前小组成员关系。
