import os
import subprocess
from datetime import datetime, timedelta
from app.core.config import get_ffmpeg_path
import uuid

VIDEO_STORAGE_BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "storage", "streams"))
SLICE_OUTPUT_BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "storage", "slices"))

def slice_video(monitor_id: int, start_time_str: str, end_time_str: str) -> str:
    """
    Slices real surveillance recording files corresponding to a monitor within a time range.
    Raises Exception if no recording file is found.
    """
    os.makedirs(SLICE_OUTPUT_BASE, exist_ok=True)
    
    # Parse dates from frontend ISO strings
    # Frontend may pass strings ending with Z or with fractional seconds
    clean_start_str = start_time_str.replace("Z", "")
    clean_end_str = end_time_str.replace("Z", "")
    
    try:
        start_time = datetime.fromisoformat(clean_start_str)
        end_time = datetime.fromisoformat(clean_end_str)
    except Exception as parse_err:
        raise ValueError(f"无法解析的时间格式. 开始: {start_time_str}, 结束: {end_time_str}. 错误: {parse_err}")

    monitor_dir = os.path.join(VIDEO_STORAGE_BASE, str(monitor_id))
    if not os.path.exists(monitor_dir) or not os.path.isdir(monitor_dir):
        raise FileNotFoundError(f"未找到摄像头 {monitor_id} 的任何录像存储文件夹。")

    # Retrieve and parse segment files
    segments = []
    for file in os.listdir(monitor_dir):
        if file.endswith(".mp4"):
            basename = os.path.splitext(file)[0]
            try:
                # File time is start time of the segment
                file_start = datetime.strptime(basename, "%Y%m%d_%H%M%S")
                # Each segment is 60 seconds long
                file_end = file_start + timedelta(seconds=60)
                segments.append({
                    "path": os.path.join(monitor_dir, file),
                    "start": file_start,
                    "end": file_end
                })
            except:
                pass

    # Find segments overlapping with [start_time, end_time]
    overlapping_segments = []
    for seg in segments:
        # Overlap condition: start1 < end2 and start2 < end1
        if seg["start"] < end_time and start_time < seg["end"]:
            overlapping_segments.append(seg)

    if not overlapping_segments:
        raise FileNotFoundError(
            f"摄像头 {monitor_id} 在请求时间段 [{start_time.strftime('%Y-%m-%d %H:%M:%S')} 至 "
            f"{end_time.strftime('%Y-%m-%d %H:%M:%S')}] 内没有任何监控录像文件记录。"
        )

    # Sort segments by start time
    overlapping_segments.sort(key=lambda x: x["start"])
    
    # Calculate crop start and end offsets relative to the start of the first segment
    base_time = overlapping_segments[0]["start"]
    start_offset = max(0.0, (start_time - base_time).total_seconds())
    end_offset = (end_time - base_time).total_seconds()
    duration = end_offset - start_offset
    
    if duration <= 0:
        raise ValueError(f"裁剪时长必须大于0，计算所得时长为: {duration} 秒。")

    # Generate output path
    output_filename = f"{monitor_id}_{uuid.uuid4().hex[:8]}.mp4"
    output_path = os.path.join(SLICE_OUTPUT_BASE, output_filename)

    # Write a temporary concat list file for FFmpeg demuxer
    concat_list_path = os.path.join(SLICE_OUTPUT_BASE, f"list_{uuid.uuid4().hex[:8]}.txt")
    with open(concat_list_path, "w", encoding="utf-8") as f:
        for seg in overlapping_segments:
            # Escape path single quotes for ffmpeg format
            escaped_path = seg["path"].replace("'", "'\\''")
            f.write(f"file '{escaped_path}'\n")

    # Run FFmpeg to concatenate and slice precisely
    # We re-encode with libx264 + aac to ensure keyframes are aligned and fully playable
    cmd = [
        get_ffmpeg_path("ffmpeg"), "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", concat_list_path,
        "-ss", f"{start_offset:.3f}",
        "-t", f"{duration:.3f}",
        "-c:v", "libx264", "-preset", "fast",
        "-c:a", "aac",
        output_path
    ]
    
    try:
        print(f"[Slicer] Concatenating and slicing segments for monitor {monitor_id}: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        
        # Cleanup temp list file
        if os.path.exists(concat_list_path):
            os.remove(concat_list_path)
            
        if result.returncode != 0:
            raise RuntimeError(f"FFmpeg 物理裁剪合并监控流时发生异常: {result.stderr}")
            
        if not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
            raise RuntimeError("FFmpeg 未能生成裁剪录像文件，或文件大小为 0。")
            
        return output_filename
    except (FileNotFoundError, OSError) as err:
        if getattr(err, 'winerror', None) == 2 or getattr(err, 'errno', None) == 2 or "系统找不到指定的文件" in str(err):
            raise RuntimeError("系统找不到 ffmpeg 可执行文件！请确认已将 FFmpeg 安装并加入系统 PATH 环境变量。") from err
        raise err
    except Exception as err:
        if os.path.exists(concat_list_path):
            try:
                os.remove(concat_list_path)
            except:
                pass
        raise err
