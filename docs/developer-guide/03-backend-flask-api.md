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
| `GET` | `/api/monitors/:id/history` | 查询监控历史录像时间轴（支持 `granularity: day/hour/minute/second` 分级） |
| `GET` | `/api/monitors/:id/playback` | 监控历史视频定位与回放播放链接 |
| `GET` | `/api/monitors/:id/slice` | 监控指定时间段 (`start` / `end`) 历史视频切片导出 |

---

## 6. 工作区与视频切片 API (/api/workspaces)

| 方法 | 路径 | 功能描述 |
| :--- | :--- | :--- |
| `GET` | `/api/workspaces/:group_id` | 获取小组下的工作区列表 |
| `POST` | `/api/workspaces/:group_id` | 新建工作区 |
| `POST` | `/api/workspaces/:id/upload-video` | 上传工作区私有视频源 |
| `POST` | `/api/workspaces/:id/segments` | 从视频源或监控历史创建切片 |
| `GET` | `/api/workspaces/:id/segments` | 查询工作区切片（含 `status`、`progress` 与签名媒体地址） |
| `POST` | `/api/workspaces/segments/:segment_id/preprocess` | 启动目标与人脸特征预处理 |
| `DELETE` | `/api/workspaces/segments/:segment_id/features` | 清理该切片的预处理特征 |

---

## 7. AI 多模态视觉问答 API

### 提交自然语言视觉提问
- **请求方法**：`POST`
- **路径**：`/api/workspaces/:workspace_id/qa`
- **请求体**：
  ```json
  {
    "segment_ids": [10, 11],
    "question": "视频中穿红衣服拿黑包的人在什么时间点出现？"
  }
  ```
- **响应示例**：
  ```json
  {
    "code": 0,
    "message": "ok",
    "data": {
      "task_id": "6f8f..."
    }
  }
  ```

任务提交后使用 `GET /api/workspaces/qa/:task_id/status` 查询状态，或使用带 JWT 的 `GET /api/workspaces/qa/:task_id/stream` 获取 SSE 进度。所有工作区、问答、视频、人脸和媒体接口都会再次校验当前用户是否仍为所属小组成员；媒体文件只能通过服务端返回的限时签名地址访问。
