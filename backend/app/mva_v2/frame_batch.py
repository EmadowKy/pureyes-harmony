"""Validate bounded multi-video frame requests before accessing media files."""

import math

MAX_FRAMES_PER_CALL = 4


def validate_frame_batch(video_items, requests):
    if not isinstance(requests, list) or not 1 <= len(requests) <= MAX_FRAMES_PER_CALL:
        raise ValueError(f"frames 必须包含 1 到 {MAX_FRAMES_PER_CALL} 个视频时间点。")
    selected = {item["video_id"]: (i, item) for i, item in enumerate(video_items, 1)}
    frames, seen = [], set()
    for request in requests:
        if not isinstance(request, dict) or not isinstance(request.get("video_id"), str):
            raise ValueError("每个时间点必须包含所选视频的 video_id 和数字 timestamp_sec。")
        match, seconds = selected.get(request["video_id"]), request.get("timestamp_sec")
        if (not match or type(seconds) not in (int, float) or not math.isfinite(seconds)
                or seconds < 0 or seconds > float(match[1].get("duration") or 0)):
            raise ValueError("截图视频不属于本轮选择范围，或时间点超出了该视频片段。")
        key = (request["video_id"], float(seconds))
        if key in seen:
            raise ValueError("同一个视频时间点不能重复请求。")
        seen.add(key); frames.append((match[0], match[1], float(seconds)))
    return frames
