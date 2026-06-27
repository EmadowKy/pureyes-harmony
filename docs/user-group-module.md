# 用户与小组模块说明

更新时间：2026-06-27 18:51:45 +08:00

本文说明当前由 `用户（包含小组管理）` 分工负责的功能范围、接口合同和对接注意事项。实现尽量独立在 `backend/app/users`、`backend/app/groups`、`backend/app/user_center` 与前端 `ProfileTab`、`GroupTab` 内，不改变监控与工作区模块的调用方式。

## 功能边界

已实现：

- 用户登录沿用 `/api/auth/login`，初始化超级管理员为 `admin/admin`。
- 用户可以查看和修改自己的姓名、手机号、头像和密码，工号不可修改。
- 管理员和超级管理员可以创建用户、按姓名或工号搜索用户、查看所有用户信息。
- 超级管理员可以把普通用户设置为管理员，也可以把管理员降为普通用户。
- 所有用户可以创建小组，并自动成为该小组组长。
- 用户可以加入多个小组，前端通过左上角全局下拉切换当前小组。
- 组长可以按工号邀请其他用户入组，邀请以 `pending` 成员状态保存。
- 被邀请用户可以在“我的消息”中同意或拒绝入组邀请。
- 小组成员可以查看组内成员基本信息。
- 组长可以查看待确认邀请、撤回邀请、移除普通成员、修改小组名称。
- 非组长成员可以主动退出小组；组长不能直接退出自己创建的小组，避免无人管理。

暂不负责：

- 监控录制、切片和直播转码。
- 工作区问答、模型推理和问答记录。
- 人脸识别、目标检测等后续视觉能力。

## 后端文件

- `backend/app/user_center/permissions.py`：当前用户、角色权限、小组成员权限、组长权限。
- `backend/app/user_center/serializers.py`：用户、小组、成员关系统一序列化。
- `backend/app/users/routes.py`：个人资料、管理员用户管理、超级管理员角色管理。
- `backend/app/groups/routes.py`：小组、邀请、成员管理。
- `backend/tests/test_user_group_api.py`：用户/小组核心接口测试。

## 前端文件

- `frontend/entry/src/main/ets/pages/tabs/ProfileTab.ets`
  - 个人资料展示与修改。
  - 创建小组。
  - 入组邀请消息处理。
  - 管理员搜索/创建用户。
  - 超级管理员调整用户角色。
- `frontend/entry/src/main/ets/pages/tabs/GroupTab.ets`
  - 当前小组详情。
  - 成员列表。
  - 组长邀请、撤回邀请、移除成员、修改组名。
  - 非组长退出小组。
- `frontend/entry/src/main/ets/utils/http.ets`
  - 新增 `HttpUtil.del()`，用于成员移除接口。

## 权限模型

角色：

- `super_admin`：唯一超级管理员，服务器初始化时创建，工号 `admin`，密码 `admin`。
- `admin`：管理员，可以查询和创建用户。
- `user`：普通用户。

小组权限：

- `Group.creator_id` 是组长，只有组长可以邀请、撤回邀请、移除成员、修改组名。
- `GroupMember.status="pending"` 表示已邀请但未接受。
- `GroupMember.status="accepted"` 表示正式成员。
- 监控和工作区模块继续只需要判断 `GroupMember(status="accepted")`，不会被待处理邀请影响。

## 主要接口

### 用户

`GET /api/users/me`

返回当前用户。

`PUT /api/users/me`

请求体：

```json
{
  "name": "张三",
  "phone": "13800000000",
  "avatar": "https://example.com/avatar.png",
  "password": "optional-new-password"
}
```

`GET /api/users/?keyword=张三`

管理员/超级管理员查询用户。`keyword` 支持姓名和工号模糊搜索。

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

查看用户详情。本人、管理员/超级管理员、同组成员可以访问。

`PUT /api/users/<emp_id>/role`

仅超级管理员可用。

```json
{
  "role": "admin"
}
```

`PUT /api/users/<emp_id>/status`

管理员/超级管理员启用或停用用户。

```json
{
  "is_active": true
}
```

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

组长邀请用户。

```json
{
  "emp_id": "u001"
}
```

`GET /api/groups/invites`

当前用户收到的待处理邀请。

`POST /api/groups/<group_id>/respond`

当前用户处理邀请。

```json
{
  "action": "accept"
}
```

`GET /api/groups/<group_id>/members`

正式成员列表。

`GET /api/groups/<group_id>/members?include_pending=1`

组长可查看正式成员和待处理邀请。

`DELETE /api/groups/<group_id>/members/<emp_id>`

组长移除成员或撤回待处理邀请。

`POST /api/groups/<group_id>/leave`

非组长成员退出小组。

## 对接返回结构

接口统一使用项目原有响应格式：

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

小组成员列表同时保留旧前端依赖的顶层字段：

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
    "name": "张三"
  }
}
```

这样既能兼容原来的 `GroupTab`，也方便后续更规范地使用 `user` 子对象。

## 远程后端检查记录

2026-06-27 18:51:45 +08:00：

- 远程正式仓库 `/root/autodl-tmp/pureyes-harmony` 已放置本地模型目录 `models/Qwen3-VL-2B-Instruct`，模型大小约 4.0 GB。
- 远程 `backend/configs/model.yaml` 已指向相对路径 `../../models/Qwen3-VL-2B-Instruct`；配合 `deploy/run_backend_autodl.py` 从 `backend/configs` 作为工作目录启动，可解析到仓库内模型目录。
- 已在远程 `pureyes` Conda 环境设置 `HF_HUB_OFFLINE=1`、`TRANSFORMERS_OFFLINE=1` 后运行 `python deploy/check_env.py --require-local-model`，通过。
- 已在远程用 `AutoProcessor.from_pretrained(..., local_files_only=True)` 和 `Qwen3VLForConditionalGeneration.from_pretrained(..., local_files_only=True, device_map="cuda:0")` 做实际加载冒烟测试，通过；加载后显存占用约 3.96 GB。
- 已通过本机 SSH 隧道把模拟器访问转发到远程后端，DevEco 模拟器完成 `admin/admin` 登录、用户页展示、空小组态展示、创建测试小组 `UITest0627`、小组页成员列表刷新测试。测试小组写入远程正式数据库，便于后续继续联调。

2026-06-27 18:22:19 +08:00：

- 已在远程临时目录 `/root/autodl-tmp/pureyes-harmony-codex-test` 同步本次改动。
- 已在远程 `pureyes` Conda 环境运行 `python -m compileall -q backend`，通过。
- 已在远程 `pureyes` Conda 环境运行 `python -m unittest discover -s backend/tests -p "test_*.py"`，2 个用户/小组接口用例通过。
- 已在本机 DevEco/Hvigor 环境运行前端 `assembleApp`，通过。当前项目未配置签名，构建日志提示跳过 HAP/App 签名，这是现有工程配置问题，不影响 ArkTS 编译验证。

2026-06-27 18:16:14 +08:00：

- 远程仓库路径：`/root/autodl-tmp/pureyes-harmony`
- Python 环境：`/root/miniconda3/envs/pureyes/bin/python`，Python 3.10.12
- GPU：NVIDIA GeForce RTX 4090，24564 MiB
- PyTorch：`2.7.0+cu126`，CUDA 可用
- Transformers：`4.57.6`
- FFmpeg/FFprobe：可用
- 当前大模型状态：`backend/configs/model.yaml` 已指向 `../../models/Qwen3-VL-2B-Instruct`，并且远程 `/root/autodl-tmp/pureyes-harmony/models/Qwen3-VL-2B-Instruct` 目录已存在；离线环境检查和实际 CUDA 加载测试已通过。

## 测试方式

后端测试只在远程服务器运行：

```bash
cd /root/autodl-tmp/pureyes-harmony
conda activate pureyes
python -m unittest discover -s backend/tests -p "test_*.py"
```

测试使用临时 SQLite 数据库，通过 `DATABASE_URL` 环境变量隔离，不会写入正式 `backend/user.db`。
