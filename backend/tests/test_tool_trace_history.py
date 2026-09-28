import json
import unittest

from app.workspaces.routes import _tool_calls_from_progress, _process_entries_from_progress, _public_progress


class ToolTraceHistoryTests(unittest.TestCase):
    def test_public_updates_and_tools_retain_order_without_private_thoughts(self):
        progress = [
            {"stage": "reasoning", "data": {"phase": "thinking", "thought": "private"}},
            {"stage": "reasoning", "data": {"phase": "commentary", "text": "先检查门口画面。", "thought": "private"}},
            {"stage": "reasoning", "data": {"phase": "action", "tool_name": "read_frames", "iteration": 1}},
            {"stage": "reasoning", "data": {"phase": "commentary", "text": "还需核验另一机位。"}},
            {"stage": "reasoning", "data": {"phase": "action", "tool_name": "track_target", "iteration": 2}},
        ]
        entries = _process_entries_from_progress(json.dumps(progress))
        self.assertEqual(["commentary", "tool", "commentary", "tool"], [entry["kind"] for entry in entries])
        self.assertEqual([0, 1], [entry["tool_index"] for entry in entries if entry["kind"] == "tool"])
        self.assertNotIn("private", json.dumps(_public_progress(progress)))
        self.assertEqual([], _process_entries_from_progress("invalid json"))

    def test_same_round_results_match_the_pending_tool_name(self):
        progress = [
            {"stage": "reasoning", "data": {"phase": "action", "iteration": 1,
             "tool_name": "read_frames", "tool_params": {}}},
            {"stage": "reasoning", "data": {"phase": "action", "iteration": 1,
             "tool_name": "search_objects", "tool_params": {}}},
            {"stage": "reasoning", "status": "completed", "data": {
             "phase": "observation", "iteration": 1, "tool_name": "read_frames",
             "summary": "已读取画面", "result_status": "completed"}},
            {"stage": "reasoning", "status": "completed", "data": {
             "phase": "observation", "iteration": 1, "tool_name": "search_objects",
             "summary": "找到目标", "result_status": "completed"}},
        ]
        calls = _tool_calls_from_progress(json.dumps(progress))
        self.assertEqual(["已读取画面", "找到目标"], [call["summary"] for call in calls])
        self.assertTrue(all(call["status"] == "completed" for call in calls))

    def test_persisted_trace_retains_early_calls_when_one_round_uses_many_tools(self):
        progress = []
        for index in range(14):
            progress.append({
                "stage": "reasoning", "status": "running",
                "data": {"phase": "action", "iteration": 1,
                         "tool_name": "read_frame_image",
                         "tool_params": {"video_id": f"video-{index % 2 + 1}",
                                         "timestamp_sec": index}},
            })
            progress.append({
                "stage": "reasoning", "status": "completed",
                "data": {"phase": "observation", "iteration": 1,
                         "tool_name": "read_frame_image", "summary": f"画面 {index}",
                         "result_status": "completed",
                         "evidence": [{"segment_id": index % 2 + 1,
                                       "timestamp_sec": index}]},
            })

        calls = _tool_calls_from_progress(json.dumps(progress))
        self.assertEqual(len(calls), 14)
        self.assertEqual([call["summary"] for call in calls],
                         [f"画面 {index}" for index in range(14)])
        self.assertEqual(calls[0]["evidence"][0]["segment_id"], 1)


if __name__ == "__main__":
    unittest.main()
