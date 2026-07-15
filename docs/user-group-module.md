# 用户与小组模块说明

更新时间：2026-07-16 02:40:00 +08:00

本文说明当前 `用户（包含小组管理）` 分工负责的功能范围、页面结构、接口合同和对接注意事项。实现尽量独立在 `backend/app/users`、`backend/app/groups`、`backend/app/user_center` 与前端 `ProfileTab`、`GroupTab` 内，不改变监控、工作区、视频分析等其他模块的调用方式。

## 功能边界

已实现：

- 用户登录沿用 `/api/auth/login`，服务初始化时自动创建超级管理员 `admin/admin`。
- “我的”首页展示头像、姓名、工号、身份，并提供清晰的功能入口，退出登录固定在底部。
- 用户可从相册选择头像；个人信息、账号安全、我的消息、新建小组拆分为独立页面，每页都有返回入口。
- 个人信息页可修改姓名、手机号、头像；账号安全页单独修改当前用户密码。
- 我的消息页展示收到的入组邀请，以及自己发出的邀请状态。
- 普通用户在“我的”页拥有“用户搜索”入口，可按姓名、工号、手机号搜索用户并只读查看基础资料。
- 管理员和超级管理员在“我的”页拥有“用户管理”入口，可查询所有用户、创建用户、查看用户详情、初始化密码、删除用户。
- 超级管理员可以将普通用户设为管理员，也可以将管理员设回普通用户。
- 管理员不能操作超级管理员，也不能在用户管理中操作自己。
- 删除用户是物理删除账号；若被删除用户创建过小组、工作区或问答记录，归属会转交给当前操作管理员，避免破坏其他模块数据。
- 所有用户都可以创建小组，创建者自动成为组长。
- 用户可以加入多个小组，前端通过全局小组选择切换当前小组。
- 小组成员可以查看同组所有正式成员的基础信息，包括工号、姓名、手机号、头像。
- 小组页展示成员通讯录，点击成员可弹出基础信息详情。
- 只有组长可以邀请其他用户入组；输入工号、姓名或手机号时，页面会显示候选用户的头像、工号、姓名。
- 组长可以查看待确认邀请、撤回邀请、移除成员、修改小组名称。
- 非组长成员可以主动退出小组；组长不能直接退出自己创建的小组，避免无人管理。

暂不负责：

- 监控录制、切片、直播转码。
- 工作区问答、模型推理和问答记录页面。
- 人脸识别、目标检测等后续视觉能力。

## 主要文件

后端：

- `backend/app/user_center/permissions.py`：当前用户、角色权限、小组成员权限、组长权限。
- `backend/app/user_center/serializers.py`：用户、小组、成员关系统一序列化。
- `backend/app/users/routes.py`：个人资料、只读用户搜索、管理员用户管理、超级管理员角色管理、密码初始化、删除用户。
- `backend/app/groups/routes.py`：小组、邀请、成员管理。
- `backend/tests/test_user_group_api.py`：用户/小组核心接口测试。

前端：

- `frontend/entry/src/main/ets/pages/tabs/ProfileTab.ets`
  - “我的”首页。
  - 个人信息、账号安全、我的消息、新建小组。
  - 普通用户只读用户搜索。
  - 管理员/超级管理员用户管理。
  - 头像相册选择、大模型 API 配置、退出登录。
- `frontend/entry/src/main/ets/pages/tabs/GroupTab.ets`
  - 当前小组信息。
  - 成员通讯录。
  - 成员基础信息弹层。
  - 组长邀请面板、候选用户预览、撤回邀请、移除成员、修改组名。
  - 非组长退出小组。
- `frontend/entry/src/main/ets/utils/http.ets`
  - 统一 HTTP 请求封装，包含 `GET`、`POST`、`PUT`、`DELETE`。

## 权限模型

角色：

- `super_admin`：超级管理员，服务初始化时创建，默认工号 `admin`，密码 `admin`。
- `admin`：管理员，可查询、创建、删除用户，可初始化密码。
- `user`：普通用户，可维护个人资料、搜索用户、创建小组、参与小组。

用户管理权限：

- 普通用户只能使用 `/api/users/search` 做只读用户搜索。
- 管理员/超级管理员可使用 `/api/users/` 查询所有用户并创建用户。
- 管理员/超级管理员可初始化普通用户或管理员的密码。
- 管理员/超级管理员可删除普通用户或管理员。
- 管理员不能操作超级管理员。
- 任何管理员都不能在用户管理中删除或初始化自己的账号。
- 只有超级管理员可调用角色调整接口。

小组权限：

- `Group.creator_id` 是组长。
- 只有组长可以邀请、撤回邀请、移除成员、修改组名。
- `GroupMember.status="pending"` 表示已邀请但未接受。
- `GroupMember.status="accepted"` 表示正式成员。
- 普通小组成员只能看到正式成员列表，不会看到待处理邀请。
- 监控和工作区模块继续只需要判断 `GroupMember(status="accepted")`，不会被待处理邀请影响。

## 主要接口

接口统一使用项目原有响应格式：

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

### 用户

`GET /api/users/me`

返回当前用户。

`PUT /api/users/me`

修改当前用户资料、头像、密码或大模型 API 配置。

```json
{
  "name": "张三",
  "phone": "13800000000",
  "avatar": "file://media/Photo/1/IMG.jpg",
  "password": "optional-new-password",
  "llm_api_key": "sk-xxx",
  "llm_base_url": "https://example.com/v1",
  "llm_model": "qwen-plus"
}
```

`GET /api/users/search?keyword=张三`

普通登录用户可用的只读搜索接口。支持姓名、工号、手机号模糊搜索，只返回基础资料，不返回 API Key 等私密配置。

`GET /api/users/?keyword=张三`

管理员/超级管理员查询所有用户。支持姓名和工号模糊搜索。

`POST /api/users/`

管理员/超级管理员创建用户。

```json
{
  "emp_id": "u001",
  "name": "张三",
  "phone": "13800000000",
  "password": "pass1234"
}
```

`GET /api/users/<emp_id>`

查看用户详情。本人、管理员/超级管理员、同组正式成员可访问。

`PUT /api/users/<emp_id>/password`

管理员/超级管理员初始化用户密码。不可操作超级管理员或当前操作账号。

```json
{
  "password": "newpass123"
}
```

`DELETE /api/users/<emp_id>`

管理员/超级管理员删除用户。不可删除超级管理员或当前操作账号。删除前会将该用户创建的小组、工作区和问答记录转交给当前操作管理员。

`PUT /api/users/<emp_id>/role`

仅超级管理员可用。

```json
{
  "role": "admin"
}
```

`PUT /api/users/<emp_id>/status`

保留的管理员接口，用于启用/停用账号。当前前端用户管理已改为删除用户，不再把停用账号作为主要操作。

### 小组

`GET /api/groups/`

返回当前用户已加入的小组，包含 `member_count`、`pending_count`、`is_creator`。

`POST /api/groups/`

创建小组，创建者自动成为组长。

```json
{
  "name": "小区A组"
}
```

`GET /api/groups/<group_id>`

返回当前小组详情。要求当前用户是正式成员。

`PUT /api/groups/<group_id>`

组长修改小组名称。

```json
{
  "name": "小区A组-东门"
}
```

`POST /api/groups/<group_id>/invite`

组长邀请用户入组。

```json
{
  "emp_id": "u001"
}
```

`GET /api/groups/invites`

当前用户收到的待处理邀请。

`POST /api/groups/<group_id>/respond`

当前用户处理入组邀请。

```json
{
  "action": "accept"
}
```

`GET /api/groups/<group_id>/members`

正式成员列表。所有正式小组成员可访问。

`GET /api/groups/<group_id>/members?include_pending=1`

组长可查看正式成员和待处理邀请。

`DELETE /api/groups/<group_id>/members/<emp_id>`

组长移除成员或撤回待处理邀请。

`POST /api/groups/<group_id>/leave`

非组长成员退出小组。

## 对接返回结构

小组成员列表保留顶层字段，便于 ArkTS 前端直接渲染，也同时包含 `user` 子对象，方便后续规范化使用。

```json
{
  "emp_id": "u001",
  "name": "张三",
  "phone": "13800000000",
  "avatar": "",
  "role": "user",
  "status": "accepted",
  "is_creator": false,
  "user": {
    "emp_id": "u001",
    "name": "张三",
    "phone": "13800000000",
    "avatar": "",
    "role": "user"
  }
}
```

普通用户搜索返回基础字段：

```json
{
  "emp_id": "u001",
  "name": "张三",
  "phone": "13800000000",
  "avatar": "",
  "role": "user",
  "is_active": true
}
```

## 验证记录

2026-07-16：

- 本地 DevEco/Hvigor 执行 `assembleApp --no-daemon`，前端构建通过。
- 已安装 HAP 到本机 HarmonyOS 模拟器并启动成功。
- 远程服务器 `/root/autodl-tmp/pureyes-harmony` 已同步本轮改动。
- 远程 `pureyes` 环境执行 `python -m unittest tests.test_user_group_api`，用户/小组接口测试通过。
- 远程实际服务完成普通用户搜索、管理员用户删除和密码初始化冒烟验证。
- 远程后端健康检查 `/api/health` 正常。

## 测试方式

后端测试只在远程服务器运行：

```bash
cd /root/autodl-tmp/pureyes-harmony/backend
conda activate pureyes
python -m unittest tests.test_user_group_api
```

测试使用临时 SQLite 数据库，通过 `DATABASE_URL` 环境变量隔离，不会写入正式 `backend/user.db`。

前端本地构建：

```powershell
$env:NODE_HOME='D:\Huawei\DevEco Studio\tools\node'
$env:JAVA_HOME='D:\Huawei\DevEco Studio\jbr'
$env:DEVECO_SDK_HOME='D:\Huawei\DevEco Studio\sdk'
$env:PATH="$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"

cd D:\VSCode_MyCode\C4_AI\pureyes-harmony\frontend
& 'D:\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleApp --no-daemon
```
