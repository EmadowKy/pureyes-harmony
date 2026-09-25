"""Stable video metadata context supplied before Agent tool use."""

import math


def format_video_context(index, item):
    meta = item.get("meta") or {}
    fps, count = item.get("fps"), item.get("frame_count")
    physical = (f"{fps:.2f} FPS、{count} 帧" if isinstance(fps, (int, float)) and math.isfinite(fps)
                and fps > 0 and type(count) is int and count > 0 else "帧率和总帧数未知")
    status = meta.get("status") or "未知"
    info = f"；索引状态: {status}"
    if status == "completed":
        if meta.get("sample_fps"):
            info += f"；索引采样: {meta['sample_fps']} FPS"
        if meta.get("resolution"):
            info += f"；索引画质: {meta['resolution']}"
    return (f"  - 视频 {index} (序号: \"{index}\", 视频名称/备注: \"{item['remark']}\", "
            f"文件名: \"{item['video_id']}\", 时长: {item['duration']:.1f} 秒；片段物理信息: {physical}{info})")
