---
name: pureyes-investigation
description: 查询 Pureyes 清眸的视频调查进度，或打开已有调查继续核验证据与追问。使用清眸当前登录账号的权限。
---

## 触发场景

用户明确要求操作 Pureyes／清眸的视频调查时使用，例如：

- “清眸调查进行到哪一步了？”“清眸有几项任务还在运行？”
- “看看店内藏物调查完成了吗。”“继续清眸里的货车调查。”
- “打开刚才列出的第二项调查。”（使用前一次结果中对应的 conversationId）

本 Skill 只查询进度或打开已有会话。用户要求分析一段新视频、发起新调查、停止任务、删除会话、导出或分享录像时不调用。打开会话不自动发送追问、重跑任务或创建新会话。不要将“继续调查”解释为自动继续计算。

## 能力契约

### 场景 1：查询调查进度（getInvestigationProgress）

#### 执行参数

省略 arg1 查询整体进度；指定 arg1 查询某项调查。优先使用上次返回的 conversationId，也可使用用户说出的完整或部分调查标题。

```text
exec-cli(command: ohos-arkTSScript --skillName 'pureyes-investigation' --scriptPath 'scripts/InvestigationSkill.ets' --functionName 'getInvestigationProgress' --args '{}')
exec-cli(command: ohos-arkTSScript --skillName 'pureyes-investigation' --scriptPath 'scripts/InvestigationSkill.ets' --functionName 'getInvestigationProgress' --args '{"arg1":"店内藏物"}')
```

```json
{"args":{"type":"object","properties":{"arg1":{"type":"string","maxLength":160,"description":"调查标题或返回结果中的 conversationId；留空查询整体进度"}},"additionalProperties":false}}
```

#### 执行返回值

整体进度示例：

```json
{"type":"result","status":"success","data":{"activeCount":1,"completedCount":2,"conversationCount":3,"checkedAt":"2026-10-25T02:00:00.000Z","scope":"当前账号可访问的运行中调查和最近结束记录","tasks":[{"conversationId":"example-case","title":"店内藏物线索核查","status":"processing","stage":"正在核验画面","steps":4,"elapsed":"01:20"}]}}
```

单项进度成功时 data 为 `{ "task": { ... }, "checkedAt": "..." }`。任务字段同 tasks 中的项目。status 是任务真实状态；failed、stopped 不得表述为调查成功。checkedAt 是查询时间，elapsed 是任务运行时间。最近结束记录最多 20 项；整体查询展示最多 20 项任务，不能说清眸所有历史调查都已列出。

### 场景 2：打开已有调查（openInvestigation）

#### 执行参数

```text
exec-cli(command: ohos-arkTSScript --skillName 'pureyes-investigation' --scriptPath 'scripts/InvestigationSkill.ets' --functionName 'openInvestigation' --args '{"arg1":"example-case"}')
```

```json
{"args":{"type":"object","properties":{"arg1":{"type":"string","maxLength":160,"description":"调查标题或 conversationId；省略时仅在有唯一可访问调查时打开"}},"additionalProperties":false}}
```

#### 执行返回值

```json
{"type":"result","status":"success","data":{"task":{"conversationId":"example-case","title":"店内藏物线索核查","status":"completed","stage":"结论已生成","steps":8,"elapsed":"02:15"},"opened":true}}
```

opened=true 仅表示系统已接受打开会话的请求，页面仍会校验登录及工作区权限。不得据此声称发起了新一轮分析。

### 共同失败分支

两个方法均可能返回以下失败：

```json
{"type":"result","status":"failed","errCode":"ERR_INVALID_PARAMS","suggestion":"请提供一项调查名称或编号，也可以查询整体进度"}
```
```json
{"type":"result","status":"failed","errCode":"ERR_LOGIN_REQUIRED","suggestion":"请先打开清眸，登录当前服务器后再试"}
```
```json
{"type":"result","status":"failed","errCode":"ERR_NOT_FOUND","suggestion":"最近调查中没有找到这项记录，请打开清眸确认调查名称"}
```
```json
{"type":"result","status":"failed","errCode":"ERR_AMBIGUOUS","suggestion":"有多项调查符合要求，请选择具体调查后再试","data":{"candidates":[{"conversationId":"case-a","title":"货车调查 A","status":"completed","stage":"结论已生成","steps":8,"elapsed":"02:15"},{"conversationId":"case-b","title":"货车调查 B","status":"processing","stage":"正在核验画面","steps":2,"elapsed":"00:30"}]}}
```
```json
{"type":"result","status":"failed","errCode":"ERR_UNAVAILABLE","suggestion":"暂时无法读取调查进度，请检查网络后重试"}
```
```json
{"type":"result","status":"failed","errCode":"ERR_OPEN_FAILED","suggestion":"未能打开调查，请打开清眸后重试"}
```

ERR_AMBIGUOUS 时让用户选择候选项，再用对应 conversationId 调用；不要自行猜选。ERR_LOGIN_REQUIRED 时引导用户在清眸内登录，不索取密码、令牌或 API Key。ERR_NOT_FOUND 不意味着其他工作区或更早历史中不存在该调查。网络失败不能表述为没有运行任务。不得补写结果中没有的调查结论、人员身份或视频内容。

返回值统一 Schema：

```json
{
  "type":"object",
  "required":["type","status"],
  "properties":{
    "type":{"const":"result"},
    "status":{"enum":["success","failed"]},
    "data":{"type":"object"},
    "errCode":{"enum":["ERR_INVALID_PARAMS","ERR_LOGIN_REQUIRED","ERR_NOT_FOUND","ERR_AMBIGUOUS","ERR_UNAVAILABLE","ERR_OPEN_FAILED"]},
    "suggestion":{"type":"string","minLength":1}
  },
  "oneOf":[
    {"properties":{"status":{"const":"success"}},"required":["data"]},
    {"properties":{"status":{"const":"failed"}},"required":["errCode","suggestion"]}
  ],
  "additionalProperties":false
}
```
