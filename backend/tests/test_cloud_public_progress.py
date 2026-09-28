"""Public progress is delivered during SSE consumption, not after return."""
import json
import unittest
from unittest.mock import Mock, patch

from app.mva import utils


class CloudPublicProgressTests(unittest.TestCase):
    def test_content_callback_runs_before_stream_finishes_and_ignores_reasoning(self):
        previous = dict(utils.api_config.__dict__)
        updates = []

        def event(delta):
            return ("data: " + json.dumps({"choices": [{"delta": delta}]})).encode()

        def stream():
            yield event({"reasoning_content": "private reasoning"})
            self.assertEqual([], updates)
            yield event({"content": "<progress_update>先查看"})
            self.assertEqual(["<progress_update>先查看"], updates)
            yield event({"content": "门口画面。</progress_update>"})
            self.assertEqual(2, len(updates))
            yield b"data: [DONE]"

        response = Mock(status_code=200)
        response.iter_lines.side_effect = stream
        session = Mock()
        session.post.return_value = response
        try:
            utils.api_config.__dict__.clear()
            utils.api_config.api_key = "test-only"
            utils.api_config.base_url = "https://model.example.test/v1"
            with patch.object(utils, "validate_llm_base_url", return_value=utils.api_config.base_url), \
                    patch.object(utils.requests, "Session", return_value=session):
                result = utils.Qwen_VL([{"role": "user", "content": "测试"}],
                                       tools=[], on_content=updates.append)
            self.assertEqual(updates[-1], result["content"])
            self.assertNotIn("private reasoning", result["content"])
            self.assertEqual(1, session.post.call_count)
        finally:
            utils.api_config.__dict__.clear()
            utils.api_config.__dict__.update(previous)


if __name__ == "__main__":
    unittest.main()
