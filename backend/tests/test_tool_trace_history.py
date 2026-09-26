import json
import unittest

from app.workspaces.routes import _tool_calls_from_progress


class ToolTraceHistoryTests(unittest.TestCase):
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
