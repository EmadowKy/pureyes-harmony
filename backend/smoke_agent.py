"""Preflight and optional real multi-video Agent smoke test.

Environment: PUREYES_SMOKE_URL (https://host/api), PUREYES_SMOKE_EMP_ID,
PUREYES_SMOKE_PASSWORD, PUREYES_SMOKE_WORKSPACE_ID,
PUREYES_SMOKE_SEGMENT_IDS (at least two comma-separated IDs),
PUREYES_SMOKE_MODEL_CONFIG_ID. Run with --submit only when API usage is intended.
"""

import argparse
import os
import sys
import time
from urllib.parse import urlparse

import requests


def setting(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"请设置 {name}")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--submit", action="store_true", help="实际提交任务并调用模型 API")
    parser.add_argument("--question", default="请分别描述这两个视频的关键事件，并比较发生顺序。")
    parser.add_argument("--expect", help="答案中必须包含的短语；不能代替人工核验")
    parser.add_argument("--require-tools", action="store_true", help="要求公开工具记录非空")
    parser.add_argument("--timeout", type=int, default=1200)
    args = parser.parse_args()

    base = setting("PUREYES_SMOKE_URL").rstrip("/")
    parsed = urlparse(base)
    if parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in
                                          {"localhost", "127.0.0.1", "::1"}):
        raise ValueError("远程测试地址必须使用 HTTPS")
    if not base.endswith("/api"):
        base += "/api"
    workspace_id = int(setting("PUREYES_SMOKE_WORKSPACE_ID"))
    config_id = int(setting("PUREYES_SMOKE_MODEL_CONFIG_ID"))
    segment_ids = list(dict.fromkeys(int(value.strip()) for value in
                                     setting("PUREYES_SMOKE_SEGMENT_IDS").split(",")))
    if len(segment_ids) < 2:
        raise ValueError("至少选择两个不同的视频片段")

    session = requests.Session()

    def call(method, path, **kwargs):
        response = session.request(method, base + path, timeout=15, **kwargs)
        response.raise_for_status()
        body = response.json()
        if body.get("code") != 0:
            raise RuntimeError(f"{path}: {body.get('message')}")
        return body.get("data")

    health = call("GET", "/health")
    if health.get("service") != "backend":
        raise RuntimeError("目标地址不是 Pureyes 后端")
    login = call("POST", "/auth/login", json={"emp_id": setting("PUREYES_SMOKE_EMP_ID"),
                                                  "password": setting("PUREYES_SMOKE_PASSWORD")})
    session.headers["Authorization"] = "Bearer " + login["access_token"]
    available = call("GET", f"/workspaces/{workspace_id}/model-configs")
    if config_id not in {item["id"] for item in available}:
        raise RuntimeError("所选模型配置对该工作区不可用")
    segments = call("GET", f"/workspaces/{workspace_id}/segments")
    selected = [item for item in segments if item["id"] in segment_ids]
    if len(selected) != len(segment_ids):
        raise RuntimeError("有片段不属于当前工作区")
    if any(item["status"] in ("pending", "processing") for item in selected):
        raise RuntimeError("请等待片段预处理结束")
    print(f"预检通过：{len(selected)} 个视频，模型配置 {config_id}，工作区 {workspace_id}")
    if not args.submit:
        print("未提交任务；确认测试素材和 API 费用后添加 --submit")
        return

    created = call("POST", f"/workspaces/{workspace_id}/qa", json={
        "question": args.question, "segment_ids": segment_ids, "model_config_id": config_id,
    })
    task_id, conversation_id = created["task_id"], created["conversation_id"]
    print(f"调查已提交：{task_id}，会话 {conversation_id}")
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        time.sleep(3)
        status = call("GET", f"/workspaces/qa/{task_id}/status")
        if status["status"] in ("completed", "failed", "stopped"):
            break
    else:
        raise TimeoutError(f"超过 {args.timeout} 秒；任务仍可在客户端查看或停止：{task_id}")
    if status["status"] != "completed":
        raise RuntimeError(f"调查结束状态：{status['status']}；{status.get('error') or ''}")
    messages = call("GET", f"/workspaces/agent/conversations/{conversation_id}/messages")["messages"]
    turn = next(item for item in messages if item["id"] == task_id)
    tools = turn.get("tool_calls") or []
    answer = status.get("answer") or ""
    if args.require_tools and not tools:
        raise AssertionError("调查完成，但没有公开工具调用记录")
    if args.expect and args.expect not in answer:
        raise AssertionError(f"答案不含预期短语：{args.expect}")
    print(f"完成：{len(tools)} 次工具调用，答案 {len(answer)} 字；请人工核对视频证据和时间点")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, TimeoutError, AssertionError, requests.RequestException) as exc:
        print(f"冒烟测试失败：{exc}", file=sys.stderr)
        sys.exit(1)
