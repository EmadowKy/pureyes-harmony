# 01-系统全局架构设计与数据流

本文面向软件架构师与系统工程师，详细阐述 Pureyes 鸿蒙多模态视觉监控与分析系统的分层架构、通信协议与端到端数据流向。

---

## 1. 全局分层架构图

系统采用前后端分离与云端大模型 API 的分层架构。工作区调查由 MVA_v2 的 ReAct 工具调用运行器驱动，前端展示多轮会话与公开执行记录：

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
        DB[(SQLite / PostgreSQL / MySQL)]
    end

    subgraph "AI 多模态分析层 MVA_v2 (PyTorch CUDA)"
        MVA2[MVA_v2 ReAct 工具调用运行器]
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

    Dev->>Backend: GET /api/workspaces/:id/video-sources
    Dev->>Backend: POST /api/workspaces/:id/segments (截取片段、可选预处理)
    Backend->>Engine: 预处理目标、人脸、语义和文字索引（若启用）
    Engine->>DB: 更新片段状态与进度
    Dev->>Backend: POST /api/workspaces/:id/qa (片段 ID 与问题)
    Backend->>DB: 保存调查会话与 processing 轮次
    Backend-->>Dev: task_id、conversation_id、turn_index
    Backend->>Engine: 启动限定视频范围的 Agent 轮次
    Engine->>LLM: 提问、有限历史上下文与工具观察
    LLM-->>Engine: 工具请求或最终回答
    Engine->>DB: 保存公开进度和终态
    Dev->>Backend: 查询状态及会话消息
    Backend-->>Dev: 工具调用记录、Markdown 结论与时间标记
```

---

## 3. 通信协议与数据格式

- **传输协议**：HTTP/1.1 与 HTTP/2；生产部署必须在反向代理层启用 HTTPS。
- **数据交互格式**：主要接口使用 JSON；视频上传使用 `multipart/form-data`，进度流使用 SSE。
- **静态资源与流媒体**：
  - 抓拍快照与缩略图：使用服务端签发的限时 `media_token` 地址。
  - 视频切片流：`/api/video/...` 支持 HTTP Range 请求；每次访问同时校验签名范围和当前小组成员关系。
