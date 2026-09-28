"""Verify default native frame calls keep per-video links without model dependencies."""

import ast
import importlib
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1] / "app" / "mva_v2"
ROUTES = ROOT.parent / "workspaces" / "routes.py"


def load_native_agent():
    app = types.ModuleType("app")
    app.__path__ = []
    core = types.ModuleType("app.core")
    core.__path__ = []
    security = types.ModuleType("app.core.tool_security")
    security.resolve_selected_video = lambda items, args: next(
        (item for item in items if item["video_id"] == args.get("video_id")), None)
    mva = types.ModuleType("app.mva")
    mva.__path__ = []
    utils = types.ModuleType("app.mva.utils")
    utils.Qwen_VL = lambda *args, **kwargs: None
    utils.api_config = types.SimpleNamespace()
    package = types.ModuleType("app.mva_v2")
    package.__path__ = [str(ROOT)]
    modules = {"app": app, "app.core": core, "app.core.tool_security": security,
               "app.mva": mva, "app.mva.utils": utils, "app.mva_v2": package}
    with patch.dict(sys.modules, modules):
        native = importlib.import_module("app.mva_v2.native_agent")
    return native


def public_tool_evidence(result):
    """Run the real helper without importing the Flask app in this test environment."""
    tree = ast.parse((ROOT / "runner.py").read_text(encoding="utf-8"))
    cls = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "MVA2Runner")
    method = next(node for node in cls.body if isinstance(node, ast.FunctionDef)
                  and node.name == "_public_tool_evidence")
    method.decorator_list = []
    scope = {"Dict": dict, "List": list, "Any": object, "math": math}
    exec(compile(ast.fix_missing_locations(ast.Module(body=[method], type_ignores=[])),
                 str(ROOT / "runner.py"), "exec"), scope)
    return scope["_public_tool_evidence"](result)


def public_tool_summary(result):
    tree = ast.parse((ROOT / "runner.py").read_text(encoding="utf-8"))
    cls = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "MVA2Runner")
    method = next(node for node in cls.body if isinstance(node, ast.FunctionDef)
                  and node.name == "_public_tool_summary")
    method.decorator_list = []
    scope = {"Dict": dict, "Any": object}
    exec(compile(ast.fix_missing_locations(ast.Module(body=[method], type_ignores=[])),
                 str(ROOT / "runner.py"), "exec"), scope)
    return scope["_public_tool_summary"](result, "已完成工具核验")


def public_tool_params(params):
    tree = ast.parse(ROUTES.read_text(encoding="utf-8"))
    method = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                  and node.name == "_safe_tool_params")
    scope = {}
    exec(compile(ast.fix_missing_locations(ast.Module(body=[method], type_ignores=[])),
                 str(ROUTES), "exec"), scope)
    return scope["_safe_tool_params"](params)


class NativeFrameEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.native = load_native_agent()
        self.videos = [
            {"video_id": "a.mp4", "video_path": "/fake/a.mp4", "duration": 12,
             "meta": {"id": 11}},
            {"video_id": "b.mp4", "video_path": "/fake/b.mp4", "duration": 12,
             "meta": {"id": 22}},
        ]

    def test_batch_keeps_individual_clickable_video_times(self):
        with tempfile.TemporaryDirectory() as image_dir:
            image_path = Path(image_dir) / "frame.jpg"
            image_path.write_bytes(b"test frame")
            runner = types.SimpleNamespace(tools=types.SimpleNamespace(
                read_frame_image=lambda path, seconds, video_id: str(image_path)))
            result, images = self.native._dispatch(runner, self.videos, "read_frames", {
                "frames": [{"video_id": "a.mp4", "timestamp_sec": 3},
                           {"video_id": "b.mp4", "timestamp_sec": 8}]}, [])
            self.assertEqual(2, result["match_count"])
            self.assertEqual(2, len([part for part in images if part["type"] == "image"]))
            self.assertEqual([(11, 3.0), (22, 8.0)], [
                (item["segment_id"], item["timestamp_sec"])
                for item in public_tool_evidence(result)])

    def test_frame_trace_reports_read_count_and_failure_without_raw_error(self):
        self.assertEqual("已读取 2 张原始画面，供模型核验", public_tool_summary({
            "frames": [{"status": "image_attached"}, {"status": "image_attached"}]}))
        self.assertEqual("工具执行失败，请检查参数或稍后重试",
                         public_tool_summary({"error": "private model failure"}))

    def test_partial_failure_keeps_successful_link_and_all_failure_is_reported(self):
        with tempfile.NamedTemporaryFile(suffix=".jpg") as image:
            def read_frame(path, seconds, video_id):
                if video_id == "b.mp4":
                    raise OSError("unavailable")
                return image.name

            runner = types.SimpleNamespace(tools=types.SimpleNamespace(read_frame_image=read_frame))
            request = {"frames": [{"video_id": "a.mp4", "timestamp_sec": 3},
                                  {"video_id": "b.mp4", "timestamp_sec": 8}]}
            result, _ = self.native._dispatch(runner, self.videos, "read_frames", request, [])
            self.assertEqual(1, result["match_count"])
            self.assertEqual([11], [item["segment_id"] for item in public_tool_evidence(result)])
            failed, _ = self.native._dispatch(runner, self.videos, "read_frames", {
                "frames": [{"video_id": "b.mp4", "timestamp_sec": 8}]}, [])
            self.assertEqual(0, failed["match_count"])
            self.assertIn("error", failed)

    def test_single_frame_also_exposes_video_link(self):
        with tempfile.NamedTemporaryFile(suffix=".jpg") as image:
            runner = types.SimpleNamespace(tools=types.SimpleNamespace(
                read_frame_image=lambda path, seconds, video_id: image.name))
            result, _ = self.native._dispatch(runner, self.videos, "read_frame_image",
                                              {"video_id": "a.mp4", "timestamp_sec": 5}, [])
            self.assertEqual([11], [item["segment_id"] for item in public_tool_evidence(result)])

    def test_batch_semantic_queries_are_visible_but_bounded(self):
        params = public_tool_params({"video_id": "a.mp4", "queries": ["衣服", "车牌", "门口", "夜晚", "额外"],
                                     "video_scores": [{"video_index": 1, "relevance": 0.9}]})
        self.assertEqual(["衣服", "车牌", "门口", "夜晚"], params["queries"])
        self.assertNotIn("video_scores", params)

    def test_batch_semantic_results_have_public_summary_and_times(self):
        runner = types.SimpleNamespace(tools=types.SimpleNamespace(
            search_visual_semantics=lambda query, video_id: {
                "match_count": 1, "matches": [{"timestamp_sec": 4, "similarity": 0.8}]}))
        result, _ = self.native._dispatch(runner, self.videos,
                                          "search_visual_semantics_batch",
                                          {"video_id": "a.mp4", "queries": ["红衣", "背包"]}, [])
        self.assertEqual(2, result["match_count"])
        self.assertEqual(["红衣", "背包"], [item["class_name"] for item in result["matches"]])
        runner.tools.search_visual_semantics = lambda query, video_id: {
            "available": False, "error": "model missing", "matches": []}
        unavailable, _ = self.native._dispatch(runner, self.videos,
                                               "search_visual_semantics_batch",
                                               {"video_id": "a.mp4", "queries": ["红衣"]}, [])
        self.assertFalse(unavailable["available"])
        self.assertIn("error", unavailable)

    def test_native_loop_marks_only_read_video_and_publishes_frame_link(self):
        with tempfile.TemporaryDirectory() as image_dir:
            image_path = Path(image_dir) / "frame.jpg"
            image_path.write_bytes(b"test frame")
            responses = iter([
                {"content": "<progress_update>先核验两段视频的原始画面，避免只凭索引下结论。</progress_update>", "tool_calls": [{"id": "call-1", "function": {
                    "name": "read_frames", "arguments": json.dumps({"frames": [
                        {"video_id": "a.mp4", "timestamp_sec": 3},
                        {"video_id": "b.mp4", "timestamp_sec": 8}]})}}]},
                {"content": "根据画面，两处均有人员。\n"
                            "FRAME_OBSERVATION 1 3.0: 视频一有人\n"
                            "FRAME_OBSERVATION 2 8.0: 未读取的视频二画面", "tool_calls": []},
            ])
            observed_messages = []

            def model(messages, **kwargs):
                observed_messages.append(list(messages))
                response = next(responses)
                if response.get("tool_calls"):
                    stream = kwargs["on_content"]
                    stream("<progress_update>先核验两段视频")
                    self.assertFalse(any(event.get("data", {}).get("phase") == "commentary" for event in events))
                    stream(response["content"])
                    self.assertTrue(any(event.get("data", {}).get("phase") == "commentary" for event in events))
                    stream(response["content"])
                return response

            def read_frame(path, seconds, video_id):
                # The UI must receive the start event while the tool is still
                # executing, rather than both events after it has returned.
                actions = [event for event in events
                           if event.get("data", {}).get("phase") == "action"]
                self.assertEqual(1, len(actions))
                self.assertEqual("read_frames", actions[0]["data"]["tool_name"])
                self.assertFalse(any(event.get("data", {}).get("phase") == "observation"
                                     for event in events))
                return str(image_path) if video_id == "a.mp4" else None

            events = []
            tools = types.SimpleNamespace(
                read_frame_image=read_frame,
                spatiotemporal_search=lambda *args, **kwargs: {})
            runner = types.SimpleNamespace(
                tools=tools, max_feedback_loops=3,
                _public_tool_summary=lambda result, fallback: fallback,
                _public_tool_times=lambda result: [],
                _public_tool_evidence=public_tool_evidence,
                _public_tool_details=lambda result: [])
            with patch.object(self.native, "Qwen_VL", model):
                answer = self.native.execute_native(runner, self.videos,
                                                     [{"role": "system", "content": ""}],
                                                     "两个视频分别有什么", events.append)
            self.assertIn("两处均有人员", answer)
            self.assertNotIn("FRAME_OBSERVATION", answer)
            self.assertNotIn("未读取的视频二画面", answer)
            public_updates = [event for event in events if event.get("data", {}).get("phase") == "commentary"]
            self.assertEqual(1, len(public_updates))
            self.assertEqual("先核验两段视频的原始画面，避免只凭索引下结论。", public_updates[0]["data"]["text"])
            phases = [event.get("data", {}).get("phase") for event in events]
            self.assertLess(phases.index("commentary"), phases.index("action"))
            observations = [event for event in events if event.get("data", {}).get("phase") == "observation"]
            self.assertEqual(1, len(observations))
            self.assertIn("tool_seconds", observations[0]["data"])
            self.assertEqual([11], [link["segment_id"] for link in observations[0]["data"]["evidence"]])
            memories = [event for event in events if event.get("stage") == "evidence_memory"]
            self.assertEqual("a.mp4", memories[0]["data"]["evidence_cards"][0]["video_id"])
            guidance = [message["content"] for message in observed_messages[-1]
                        if message.get("role") == "system" and isinstance(message.get("content"), str)
                        and "逐视频探索优先级" in message["content"]][-1]
            self.assertIn("a.mp4): 相关性 0.50，已有证据充分度 0.00，已探索", guidance)
            self.assertIn("b.mp4): 相关性 0.50，已有证据充分度 0.00，尚未探索", guidance)

    def budget_runner(self, rounds=10):
        return types.SimpleNamespace(
            tools=types.SimpleNamespace(spatiotemporal_search=lambda *a, **k: {}),
            max_feedback_loops=rounds,
            _public_tool_summary=lambda result, fallback: fallback,
            _public_tool_times=lambda result: [],
            _public_tool_evidence=lambda result: [],
            _public_tool_details=lambda result: [])

    def test_more_than_twelve_frames_and_six_rounds_allow_late_tracking(self):
        requests = []
        model_rounds = []

        def model(messages, **kwargs):
            iteration = len(model_rounds) + 1
            model_rounds.append(iteration)
            self.assertFalse(self.native.api_config.force_answer)
            if iteration <= 7:
                args = {"frames": [{"video_id": "a.mp4", "timestamp_sec": (iteration - 1) + offset / 4}
                                   for offset in range(4)]}
                name = "read_frames"
            elif iteration == 8:
                name, args = "track_target", {"video_id": "a.mp4", "track_id": "person_1"}
            else:
                return {"content": "已检查画面并核验跨镜候选，不能确认同一人。"}
            return {"tool_calls": [{"id": str(iteration), "function": {
                "name": name, "arguments": json.dumps(args)}}]}

        def dispatch(runner, videos, name, args, files):
            requests.append((name, args))
            return ({"frames": [dict(frame, status="image_attached") for frame in args["frames"]]}, []) if name == "read_frames" else ({}, [])

        with patch.object(self.native, "Qwen_VL", model), patch.object(self.native, "_dispatch", dispatch):
            answer = self.native.execute_native(self.budget_runner(), self.videos, [{"role": "system", "content": ""}], "是否同一人", None)
        self.assertEqual(9, len(model_rounds))
        self.assertEqual(28, sum(len(args["frames"]) for name, args in requests if name == "read_frames"))
        self.assertEqual("track_target", requests[-1][0])
        self.assertIn("不能确认", answer)

    def test_loop_guard_is_system_not_user_and_allows_incomplete_answer(self):
        question = "是否同一个人"
        calls = []

        def model(messages, **kwargs):
            calls.append(list(messages))
            if len(calls) == 1:
                self.assertFalse(self.native.api_config.force_answer)
                return {"content": "缺少可比对目标，无法确认。"}
            self.assertTrue(self.native.api_config.force_answer)
            return {"content": "核验未完成，无法确认身份。"}

        with patch.object(self.native, "Qwen_VL", model):
            answer = self.native.execute_native(self.budget_runner(2), self.videos,
                [{"role": "system", "content": ""}, {"role": "user", "content": question}], question, None)
        guards = [item for item in calls[-1] if "系统运行保护" in str(item.get("content"))]
        self.assertEqual(["system"], [item["role"] for item in guards])
        self.assertEqual([question], [item["content"] for item in calls[-1] if item["role"] == "user"])
        self.assertIn("未完成", answer)
        self.assertFalse(self.native.api_config.force_answer)

    def test_no_identity_candidates_only_triggers_one_reminder(self):
        with patch.object(self.native, "Qwen_VL", return_value={"content": "没有可靠候选，不能确认身份。"}) as model:
            answer = self.native.execute_native(self.budget_runner(), self.videos, [{"role": "system", "content": ""}], "是否同一个人", None)
        self.assertEqual(2, model.call_count)
        self.assertIn("不能确认", answer)

    def test_public_updates_are_optional_and_do_not_leak_internal_observations(self):
        updates, answer = self.native._extract_progress_updates(
            "<think><progress_update>隐藏推理</progress_update></think>"
            "<progress_update>已核验画面，接着检查另一视频。</progress_update>结论。")
        self.assertEqual(["已核验画面，接着检查另一视频。"], updates)
        self.assertEqual("结论。", answer)
        self.assertEqual(([], "普通答案"), self.native._extract_progress_updates("普通答案"))
        self.assertEqual(([], ""), self.native._extract_progress_updates(
            "<progress_update>FRAME_OBSERVATION a.mp4 1: 内部记录</progress_update>"))
        self.assertEqual(([], "结论。"), self.native._extract_progress_updates(
            "结论。<progress_update>未结束的说明"))


if __name__ == "__main__":
    unittest.main()
