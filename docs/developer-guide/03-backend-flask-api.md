# 03-后端 RESTful API 接口规范详解

本文档为 API 开发者提供 Pureyes 后端主要 REST API 参考。除视频上传使用 `multipart/form-data`、任务进度流使用 SSE 外，请求与响应以 JSON 为主，根路径为 `/api`。

---

## 1. 全局响应状态码规范

所有 JSON 响应遵循如下统一包装结构：

```json
{
  "code": 0,
  "message": "ok",
  "data": { ... }
}
```

- `code: 0` 表示逻辑执行成功。
- `code: 400` 表示参数校验错误或业务冲突。
- `code: 401` 表示未提供有效 JWT Token、Token 已加入黑名单或账号已被停用。
- `code: 403` 表示权限不足（例如普通用户调用管理员接口）。
- `code: 500` 表示服务器内部错误。

---

## 2. 身份认证模块 API (/api/auth)

### 2.1 用户登录
- **请求方法**：`POST`
- **路径**：`/api/auth/login`
- **请求体**：
  ```json
  {
    "emp_id": "admin",
    "password": "<部署时设置的管理员密码>"
  }
  ```
- **响应示例**：
  ```json
  {
    "code": 0,
    "message": "ok",
    "data": {
      "access_token": "eyJhbGciOiJIUzI1Ni...",
      "refresh_token": "eyJhbGciOiJIUzI1Ni...",
      "user": {
        "emp_id": "admin",
        "name": "超级管理员",
        "role": "super_admin",
        "is_active": true
      }
    }
  }
  ```

### 2.2 退出登录
- **请求方法**：`POST`
- **路径**：`/api/auth/logout`
- **Headers**：`Authorization: Bearer <token>`
- **说明**：撤销当前用户已有的访问令牌、刷新令牌和签名媒体地址。

---

## 3. 用户管理与通讯录 API (/api/users)

| 方法 | 路径 | 权限要求 | 功能描述 |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/users/search?keyword={query}` | 所有登录用户 | 按工号/姓名/手机号搜索用户（只读公开字段） |
| `GET` | `/api/users/` | Admin / Super Admin | 查询系统用户列表 |
| `POST` | `/api/users/` | Admin / Super Admin | 创建新用户账号 |
| `PUT` | `/api/users/:emp_id/role` | Super Admin | 在 `admin` 与 `user` 之间调整角色；内置超级管理员不可变更 |
| `PUT` | `/api/users/:emp_id/status` | Admin / Super Admin | 修改账号启用/停用状态 (`is_active: false`) |
| `PUT` | `/api/users/:emp_id/password` | Admin / Super Admin | 设置新的初始化密码 |
| `DELETE` | `/api/users/:emp_id` | Admin / Super Admin | 删除用户账号 |

---

## 4. 小组模块 API (/api/groups)

| 方法 | 路径 | 功能描述 |
| :--- | :--- | :--- |
| `GET` | `/api/groups/` | 获取当前用户加入的所有小组列表 |
| `POST` | `/api/groups/` | 创建新安防小组（创建者自动成为 Leader） |
| `GET` | `/api/groups/:id/members` | 获取该小组内的所有成员通讯录 |
| `POST` | `/api/groups/:id/invite` | 组长邀请新成员加入小组 |
| `DELETE` | `/api/groups/:id/members/:emp_id` | 组长将成员移出小组 |

---

## 5. 监控模块 API (/api/monitors)

| 方法 | 路径 | 功能描述 |
| :--- | :--- | :--- |
| `GET` | `/api/monitors/:group_id` | 获取指定小组下的所有摄像头列表 |
| `POST` | `/api/monitors/:group_id` | 组长添加摄像头 (指定名称与 RTSP/HTTP 流地址) |
| `GET` | `/api/monitors/:id/cover` | 获取摄像头最新自动抓拍封面快照图片 |
| `GET` | `/api/monitors/:id/history` | 查询连续录像的可回放范围（含正在写入的 fragmented MP4；支持 `granularity: day/hour/minute/second` 进度条精度） |
| `GET` | `/api/monitors/:id/playback` | 按绝对时间定位已完成或正在写入的录像，返回签名播放地址与片内偏移；不暴露存储文件名 |
| `GET` | `/api/monitors/:id/slice` | 监控指定时间段 (`start` / `end`) 历史视频切片导出 |

---

## 6. 工作区与视频切片 API (/api/workspaces)

| 方法 | 路径 | 功能描述 |
| :--- | :--- | :--- |
| `GET` | `/api/workspaces/:group_id` | 获取小组下的工作区列表 |
| `POST` | `/api/workspaces/:group_id` | 新建工作区 |
| `GET` | `/api/workspaces/:id/video-sources` | 列出同组监控历史、工作区上传文件及可用示例视频 |
| `POST` | `/api/workspaces/:id/upload-video` | 上传工作区私有视频源 |
| `POST` | `/api/workspaces/:id/segments` | 从视频源或监控历史创建切片 |
| `GET` | `/api/workspaces/:id/segments` | 查询工作区切片（含 `status`、`progress` 与签名媒体地址） |
| `PUT` | `/api/workspaces/segments/:segment_id` | 编辑片段备注 |
| `DELETE` | `/api/workspaces/segments/:segment_id` | 删除未被调查记录引用的片段及其特征和视频文件 |
| `POST` | `/api/workspaces/segments/:segment_id/preprocess` | 启动目标与人脸特征预处理 |
| `DELETE` | `/api/workspaces/segments/:segment_id/features` | 清理该切片的预处理特征 |
| `GET` | `/api/workspaces/:id/faces` | 列出工作区人脸分组，可用 `segment_id` 筛选；旧版分组返回 `is_legacy` |
| `GET` | `/api/workspaces/:id/faces/:group_id/records` | 获取某个人脸分组的出现记录，可用 `segment_id` 筛选 |
| `POST` | `/api/workspaces/:id/faces/merge` | `source_group_id`、`target_group_id`：合并分组 |
| `POST` | `/api/workspaces/:id/faces/records/:record_id/move` | `target_group_id`：移动单条记录；省略则单独成组 |
| `GET` | `/api/workspaces/face-backend` | 只读查询后端配置的人脸归类模式；无修改接口 |
| `GET` | `/api/workspaces/:id/faces/harmony/queue` | 获取最多 30 条待手机归类记录、剩余数及已归类分组代表抓拍 |
| `POST` | `/api/workspaces/:id/faces/harmony/classify` | 提交 `assignments: [{"record_id":1,"target_group_id":2}]`；每条新分组可指向自己的分组 ID |

上传使用 `file` 表单字段，支持 `.mp4`、`.avi`、`.mov`、`.mkv`、`.webm`。创建片段时：监控源传 `source_type: "monitor"`、`monitor_id`、`start_time`、`end_time`；上传／示例源传 `video_name` 或 `filepath`，以及以秒为单位的 `start_offset`、`end_offset`（最长两小时）。可选字段包括 `remark`、`enable_preprocess`（默认 `true`）、`sample_fps`（默认 `1.0`）与 `resolution`（默认 `1080P`）。客户端预设 0.5／1／2 FPS 和 480P／720P／1080P／4K；服务端允许大于 0 且不超过 30 FPS 的有限数值，并校验画质枚举。关闭预处理的片段状态为 `none`，开启后依次进入 `pending`／`processing`，最终为 `completed` 或 `failed`。

片段为 `pending`／`processing`、被运行中的问答使用，或仍被调查历史引用时，删除返回 HTTP 409。运行中的问答还会阻止清除或重建该片段特征，以免破坏当前任务的证据。

人脸分组修改要求当前用户仍为工作区小组成员，且工作区没有等待或正在预处理的片段，否则返回 HTTP 409。重新预处理片段会重新生成该片段的人脸记录。
手机归类必须由小组成员提交；目标分组须属于相同工作区，且先前已有归类记录或在本批次中先完成归类。待归类记录不会进入 Agent 的人脸线索工具结果。归类模式只能由运维在后端设置 `FACE_RECOGNITION_BACKEND=server|harmony` 并重启服务；接口和应用均不能修改。

---

## 7. AI 多模态视觉问答 API

### 7.0 模型配置 API

| 方法 | 路径 | 用途 |
| :--- | :--- | :--- |
| `GET` | `/api/model-configs[?group_id=...]` | 本人的个人配置及已加入小组的共享配置；指定小组时限制共享列表 |
| `POST` | `/api/model-configs` | 新建配置，提交 `scope`、`name`、`api_key`、`base_url`、`model`；小组配置另传 `group_id` |
| `PUT` | `/api/model-configs/:config_id` | 修改名称、地址、模型或密钥；密钥可省略以保持原值，范围与归属不可修改 |
| `DELETE` | `/api/model-configs/:config_id` | 删除配置 |
| `GET` | `/api/workspaces/:id/model-configs` | 可在当前工作区问答中选择的个人及小组配置 |

读接口只返回 `api_key_configured`，绝不返回密钥。个人配置仅本人可修改；小组配置仅该组创建者可修改，已接受邀请的组员可查看和使用。提交轮次时重新校验配置归属与工作区小组；任务在内存中固定该轮密钥、地址和模型，结束即清理，数据库轮次只保存配置名称标签。

### 7.1 创建调查与提交追问

`POST /api/workspaces/:workspace_id/qa` 创建一轮任务：

```json
{
  "segment_ids": [10, 11],
  "question": "视频中穿红衣服拿黑包的人何时出现？",
  "model_config_id": 5
}
```

响应 `data` 包含 `task_id`、`conversation_id`、`turn_index`。继续同一调查时，传 `{"conversation_id":"已有会话 ID","question":"后来去了哪里？","model_config_id":5}`；服务端始终沿用首轮选定的片段范围，忽略追问中额外的片段选择。问题不能为空、最长 4000 字；首轮需选择 1–20 个当前工作区片段。片段正在预处理时返回冲突；同一调查只能同时运行一轮，重复提交返回 HTTP 409。不同组员可在上一轮结束后追问，每轮必须选择本人个人配置或当前小组共享配置。

### 7.2 查询与控制调查

| 方法 | 路径 | 用途 |
| :--- | :--- | :--- |
| `GET` | `/api/workspaces/:id/agent/conversations` | 工作区调查列表，含最近一轮状态及轮数 |
| `GET` | `/api/workspaces/agent/conversations/:conversation_id/messages` | 按轮次返回问题、状态、答案及整理后的 `tool_calls` |
| `GET` | `/api/workspaces/qa/:task_id/status` | 当前状态、公开进度、答案／错误和会话定位 |
| `GET` | `/api/workspaces/qa/:task_id/stream` | 带 JWT 的 SSE 进度与终态事件 |
| `POST` | `/api/workspaces/qa/:task_id/stop` | 组员停止正在运行的 Agent 轮次 |
| `GET` | `/api/workspaces/:id/qa` | 历史问答记录（兼容旧记录） |
| `DELETE` | `/api/workspaces/qa/:task_id` | 删除已结束的问答轮次；运行中返回 409 |

状态为 `processing`、`completed`、`failed` 或 `stopped`。`status` 和 SSE 的公开进度仅提供阶段、脱敏后的工具参数与观察结果，不返回模型内部思考；`messages` 的 `tool_calls` 提供可展开的调用记录。客户端按任务及会话状态轮询，也可消费 SSE。服务端以数据库记录状态和心跳恢复卡住的任务，并以 `AGENT_TASK_TIMEOUT_SECONDS` 控制单轮时限（默认 1200 秒）。所有工作区、问答、视频、人脸和媒体接口都会再次校验当前用户是否仍为所属小组成员；媒体文件通过限时签名地址访问。
