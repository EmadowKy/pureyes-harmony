# 03-后端 RESTful API 接口规范详解

本文档为 API 开发者提供 Pureyes 后端 RESTful API 的完整参考。所有 API 接口请求与响应统一使用 JSON 编码，根路径为 `/api`。

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
    "password": "admin"
  }
  ```
- **响应示例**：
  ```json
  {
    "code": 0,
    "message": "ok",
    "data": {
      "token": "eyJhbGciOiJIUzI1Ni...",
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
- **说明**：将当前 Token 写入服务端 `blacklist_tokens` 数据库表。

---

## 3. 用户管理与通讯录 API (/api/users)

| 方法 | 路径 | 权限要求 | 功能描述 |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/users/search?q={query}` | 所有登录用户 | 按工号/姓名/手机号搜索用户（返回候选卡片数据） |
| `GET` | `/api/users/list` | Admin / Super Admin | 分页查询系统全量用户列表 |
| `POST` | `/api/users/create` | Admin / Super Admin | 创建新用户账号 |
| `PUT` | `/api/users/:emp_id/role` | Super Admin | 变更用户角色 (`super_admin`/`admin`/`user`) |
| `PUT` | `/api/users/:emp_id/status` | Admin / Super Admin | 修改账号启用/停用状态 (`is_active: false`) |
| `POST` | `/api/users/:emp_id/reset_password` | Admin / Super Admin | 重置用户密码为初始密码 |
| `DELETE` | `/api/users/:emp_id` | Admin / Super Admin | 删除用户账号 |

---

## 4. 小组模块 API (/api/groups)

| 方法 | 路径 | 功能描述 |
| :--- | :--- | :--- |
| `GET` | `/api/groups/my` | 获取当前用户加入的所有小组列表 |
| `POST` | `/api/groups/create` | 创建新安防小组（创建者自动成为 Leader） |
| `GET` | `/api/groups/:id/members` | 获取该小组内的所有成员通讯录 |
| `POST` | `/api/groups/:id/members/invite` | 组长邀请新成员加入小组 |
| `DELETE` | `/api/groups/:id/members/:emp_id` | 组长将成员移出小组 |

---

## 5. 监控模块 API (/api/monitors)

| 方法 | 路径 | 功能描述 |
| :--- | :--- | :--- |
| `GET` | `/api/monitors?group_id={gid}` | 获取指定小组下的所有摄像头列表 |
| `POST` | `/api/monitors/create` | 添加新摄像头 (指定名称与 RTSP/HTTP 流地址) |
| `GET` | `/api/monitors/:id/cover` | 获取摄像头最新自动抓拍封面快照图片 |
| `GET` | `/api/monitors/:id/history` | 查询监控历史录像时间轴（支持 `granularity: day/hour/minute/second` 分级） |
| `GET` | `/api/monitors/:id/playback` | 监控历史视频定位与回放播放链接 |
| `GET` | `/api/monitors/:id/slice` | 监控指定时间段 (`start` / `end`) 历史视频切片导出 |

---

## 6. 工作区与视频切片 API (/api/workspaces)

| 方法 | 路径 | 功能描述 |
| :--- | :--- | :--- |
| `GET` | `/api/workspaces?group_id={gid}` | 获取小组下的工作区列表 |
| `POST` | `/api/workspaces/create` | 新建工作区 |
| `POST` | `/api/workspaces/:id/videos` | 导入/添加视频文件并提交切片与特征抽取任务 |
| `GET` | `/api/workspaces/:id/videos` | 查询工作区内视频片段列表（含 `status` 与 `progress`） |

---

## 7. AI 多模态视觉问答 API (/api/qa)

### 提交自然语言视觉提问
- **请求方法**：`POST`
- **路径**：`/api/qa/ask`
- **请求体**：
  ```json
  {
    "workspace_id": 1,
    "segment_ids": [10, 11],
    "prompt": "视频中穿红衣服拿黑包的人在什么时间点出现？"
  }
  ```
- **响应示例**：
  ```json
  {
    "code": 0,
    "message": "ok",
    "data": {
      "record_id": 105,
      "prompt": "视频中穿红衣服拿黑包的人在什么时间点出现？",
      "answer": "目标人员于 00:01:45 首次出现在画面右侧...",
      "timestamps": [
        { "start": 105.0, "end": 128.5, "confidence": 0.96 }
      ],
      "keyframe_url": "/api/qa/keyframes/105.jpg"
    }
  }
  ```
