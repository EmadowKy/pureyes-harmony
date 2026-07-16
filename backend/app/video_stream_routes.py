"""视频播放路由 - 提供视频文件访问服务（支持实时转码）"""

import os
import subprocess
import tempfile
import uuid
import time
import threading
import hashlib
from flask import Blueprint, send_file, abort, Response, request, send_from_directory
from werkzeug.exceptions import HTTPException
from concurrent.futures import ThreadPoolExecutor
from app.core.config import get_ffmpeg_path

video_stream_bp = Blueprint('video_stream', __name__, url_prefix='/api/video')

current_file = os.path.abspath(__file__)
BACKEND_DIR = os.path.dirname(os.path.dirname(current_file))

print(f"[DEBUG] video_stream_routes.py current file: {current_file}")
print(f"[DEBUG] video_stream_bp BACKEND_DIR: {BACKEND_DIR}")

executor = ThreadPoolExecutor(max_workers=2)
transcoded_cache = {}
MAX_CACHE_SIZE = 5
OFFSET_CACHE_SIZE = 20


def _serve_offset_video(video_path: str, offset_seconds: int):
    if offset_seconds <= 0:
        return None

    try:
        source_mtime = int(os.path.getmtime(video_path))
        cache_key = hashlib.md5(f"accurate-v2:{video_path}:{source_mtime}:{offset_seconds}".encode("utf-8")).hexdigest()
        offset_dir = os.path.join(BACKEND_DIR, 'temp', 'playback_offsets')
        os.makedirs(offset_dir, exist_ok=True)
        output_path = os.path.join(offset_dir, f"{cache_key}.mp4")

        if not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
            cmd = [
                get_ffmpeg_path('ffmpeg'), '-y',
                '-i', video_path,
                '-ss', str(offset_seconds),
                '-t', '20',
                '-c:v', 'libx264', '-preset', 'veryfast',
                '-pix_fmt', 'yuv420p',
                '-an',
                '-movflags', '+faststart',
                output_path
            ]
            print(f"[INFO] Creating accurate offset playback: offset={offset_seconds}, source={video_path}")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
            if result.returncode != 0 or not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
                print(f"[ERROR] Offset slice failed: {result.stderr[-500:]}")
                return None

            cached_files = sorted(
                [os.path.join(offset_dir, name) for name in os.listdir(offset_dir) if name.endswith('.mp4')],
                key=lambda item: os.path.getmtime(item)
            )
            while len(cached_files) > OFFSET_CACHE_SIZE:
                old_path = cached_files.pop(0)
                try:
                    os.remove(old_path)
                except OSError:
                    pass

        return send_file(output_path, mimetype='video/mp4')
    except Exception as e:
        print(f"[ERROR] Offset playback exception: {e}")
        return None


def _normalize_video_path(video_path: str) -> str:
    """
    将前端传入路径规范化为 backend 下的相对路径。
    支持：
    - uploads/xxx.mp4
    - C:/.../backend/uploads/xxx.mp4
    - C:\\...\\backend\\uploads\\xxx.mp4
    """
    raw = (video_path or "").strip()
    p = raw.replace("\\", "/").lstrip("/")

    marker = "backend/uploads/"
    idx = p.lower().find(marker)
    if idx != -1:
        p = p[idx + len("backend/"):]

    if ":" in p and not p.startswith("uploads/"):
        p = f"uploads/{os.path.basename(p)}"

    p = p.replace("\\", "/").lstrip("/")
    return p


def _check_video_compatible(video_path: str) -> tuple:
    """
    使用 ffprobe 检查视频是否为浏览器兼容格式。
    返回 (is_compatible, codec_info, needs_transcode)
    """
    try:
        cmd = [
            get_ffmpeg_path('ffprobe'), '-v', 'quiet', '-print_format', 'json',
            '-show_streams', '-show_format', video_path
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        if result.returncode != 0:
            return False, "ffprobe failed", True

        import json
        info = json.loads(result.stdout)

        video_stream = None
        audio_stream = None
        for stream in info.get('streams', []):
            if stream.get('codec_type') == 'video':
                video_stream = stream
            elif stream.get('codec_type') == 'audio':
                audio_stream = stream

        if not video_stream:
            return False, "No video stream", True

        video_codec = video_stream.get('codec_name', '')
        profile = video_stream.get('profile', '').lower()

        is_h264 = video_codec == 'h264'
        is_high_or_baseline = 'high' in profile or 'baseline' in profile or 'main' in profile
        is_baseline_only = 'baseline' in profile

        if is_h264 and is_high_or_baseline:
            needs_transcode = False
            return True, f"h264 {profile}", False

        if is_h264:
            return False, f"h264 {profile} (unsupported)", True

        return False, f"{video_codec} (unsupported)", True

    except subprocess.TimeoutExpired:
        return False, "ffprobe timeout", True
    except Exception as e:
        print(f"[WARN] ffprobe error: {e}")
        return False, str(e), True


def _transcode_video(video_path: str, output_path: str) -> bool:
    """
    使用 ffmpeg 将视频转码为网页兼容格式。
    H.264 High/Baseline Profile + AAC + moov 前置
    """
    try:
        cmd = [
            get_ffmpeg_path('ffmpeg'), '-y', '-i', video_path,
            '-c:v', 'libx264', '-profile:v', 'high', '-preset', 'fast',
            '-pix_fmt', 'yuv420p',
            '-c:a', 'aac', '-b:a', '128k',
            '-movflags', '+faststart',
            '-max_muxing_queue_size', '9999',
            output_path
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300
        )

        if result.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            print(f"[INFO] Transcoded successfully: {video_path} -> {output_path}")
            return True

        print(f"[ERROR] Transcode failed: {result.stderr[-500:]}")
        return False

    except subprocess.TimeoutExpired:
        print(f"[ERROR] Transcode timeout: {video_path}")
        return False
    except Exception as e:
        print(f"[ERROR] Transcode exception: {e}")
        return False


@video_stream_bp.route('/<path:video_path>')
def serve_video(video_path):
    """
    提供视频文件访问（支持实时转码）
    GET /api/video/<path>
    查询参数:
        - transcode=1 强制转码
        - check=1     仅检查兼容性，返回 JSON
    """
    try:
        check_only = request.args.get('check') == '1'
        force_transcode = request.args.get('transcode') == '1'

        safe_video_path = _normalize_video_path(video_path)
        full_path = os.path.abspath(os.path.join(BACKEND_DIR, safe_video_path))

        print(f"[DEBUG] Requested video: {video_path}")
        print(f"[DEBUG] Normalized path: {safe_video_path}")
        print(f"[DEBUG] Full path: {full_path}")
        print(f"[DEBUG] File exists: {os.path.exists(full_path)}")

        if not full_path.startswith(BACKEND_DIR + os.sep) and full_path != BACKEND_DIR:
            abort(403, description="Access denied")

        if not os.path.exists(full_path):
            abort(404, description=f"Video not found: {safe_video_path}")

        if not os.path.isfile(full_path):
            abort(400, description="Not a file")

        if check_only:
            is_compat, codec_info, needs_tc = _check_video_compatible(full_path)
            return {
                'compatible': is_compat,
                'codec': codec_info,
                'needs_transcode': needs_tc,
                'path': video_path
            }

        try:
            offset_seconds = max(0, int(float(request.args.get('offset') or 0)))
        except ValueError:
            offset_seconds = 0
        offset_response = _serve_offset_video(full_path, offset_seconds)
        if offset_response is not None:
            return offset_response

        cache_key = safe_video_path

        if cache_key in transcoded_cache:
            tc_path, tc_time = transcoded_cache[cache_key]
            if os.path.exists(tc_path):
                print(f"[CACHE] Using cached transcoded: {tc_path}")
                return send_file(tc_path, mimetype='video/mp4')
            else:
                del transcoded_cache[cache_key]

        is_compat, codec_info, needs_tc = _check_video_compatible(full_path)
        print(f"[INFO] Video compatibility: {is_compat}, codec: {codec_info}, needs_transcode: {needs_tc}")

        if is_compat and not force_transcode:
            return send_file(full_path, mimetype='video/mp4')

        if not needs_tc and not force_transcode:
            return send_file(full_path, mimetype='video/mp4')

        print(f"[INFO] Starting transcode for: {video_path}")

        tc_filename = f"{uuid.uuid4().hex}.mp4"
        tc_dir = os.path.join(BACKEND_DIR, 'temp', 'transcoded')
        os.makedirs(tc_dir, exist_ok=True)
        tc_path = os.path.join(tc_dir, tc_filename)

        success = _transcode_video(full_path, tc_path)

        if success and os.path.exists(tc_path):
            if len(transcoded_cache) >= MAX_CACHE_SIZE:
                oldest = min(transcoded_cache.items(), key=lambda x: x[1][1])
                old_path = oldest[1][0]
                del transcoded_cache[oldest[0]]
                try:
                    if os.path.exists(old_path):
                        os.remove(old_path)
                except:
                    pass

            transcoded_cache[cache_key] = (tc_path, os.path.getmtime(tc_path))

            return send_file(tc_path, mimetype='video/mp4')
        else:
            abort(500, description="Video transcoding failed")

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error serving video: {e}")
        abort(500, description=f"Internal server error: {str(e)}")


@video_stream_bp.route('/example/<path:video_path>')
def serve_example_video(video_path):
    """
    提供 example 目录下的视频访问服务。
    """
    try:
        example_dir = os.path.abspath(os.path.join(BACKEND_DIR, "..", "example"))
        full_path = os.path.abspath(os.path.join(example_dir, video_path))
        
        # 安全性校验：防止路径穿越
        if not full_path.startswith(example_dir + os.sep) and full_path != example_dir:
            abort(403, description="Access denied")
            
        if not os.path.exists(full_path):
            abort(404, description=f"Example video not found: {video_path}")
            
        return send_file(full_path, mimetype='video/mp4')
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error serving example video: {e}")
        abort(500, description=f"Internal server error: {str(e)}")


from app.models.monitor import Monitor

LIVE_STREAM_BASE = os.path.abspath(os.path.join(BACKEND_DIR, "storage", "live"))
live_converters = {}
live_converters_lock = threading.Lock()


def stop_all_live_converters():
    """
    Kills all running live transcoder processes.
    """
    global live_converters
    with live_converters_lock:
        print("[LiveStream] Stopping all live transcoders...")
        for monitor_id, proc in list(live_converters.items()):
            if proc.poll() is None:
                try:
                    proc.terminate()
                    proc.wait(timeout=2)
                except Exception:
                    try:
                        proc.kill()
                    except Exception:
                        pass
        live_converters.clear()

@video_stream_bp.route('/live/<int:monitor_id>/index.m3u8')
def live_stream_index(monitor_id):
    monitor = Monitor.query.get(monitor_id)
    if not monitor or not monitor.stream_url:
        abort(404, description="Monitor or stream URL not found")
        
    output_dir = os.path.join(LIVE_STREAM_BASE, str(monitor_id))
    os.makedirs(output_dir, exist_ok=True)
    
    # Start live converter if not running
    with live_converters_lock:
        is_running = False
        if monitor_id in live_converters:
            proc = live_converters[monitor_id]
            if proc.poll() is None:
                is_running = True
            else:
                del live_converters[monitor_id]
                
        if not is_running:
            # Build command
            cmd = [get_ffmpeg_path("ffmpeg"), "-y"]
            if monitor.stream_url.strip().lower().startswith("rtsp://"):
                cmd.extend(["-rtsp_transport", "tcp"])
            cmd.extend([
                "-i", monitor.stream_url,
                "-c:v", "libx264",
                "-preset", "ultrafast",
                "-g", "50",
                "-an",
                "-f", "hls",
                "-hls_time", "2",
                "-hls_list_size", "15",
                "-hls_flags", "delete_segments",
                os.path.join(output_dir, "index.m3u8")
            ])
            
            try:
                print(f"[LiveStream] Starting live HLS converter for monitor {monitor_id}: {' '.join(cmd)}")
                log_file_path = os.path.join(output_dir, "ffmpeg.log")
                with open(log_file_path, "w", encoding="utf-8") as log_file:
                    proc = subprocess.Popen(
                        cmd,
                        stdout=subprocess.DEVNULL,
                        stderr=log_file,
                        creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
                    )
                live_converters[monitor_id] = proc
                # Give FFmpeg a second to write the first segment
                time.sleep(1.5)
            except (FileNotFoundError, OSError) as e:
                # If WinError 2 (File not found) or OSError indicating command not found
                if getattr(e, 'winerror', None) == 2 or getattr(e, 'errno', None) == 2 or "系统找不到指定的文件" in str(e):
                    print("[LiveStream ERROR] 系统找不到 ffmpeg 可执行文件！请确认已将 FFmpeg 安装并加入系统 PATH 环境变量。")
                    abort(500, description="FFmpeg 未安装或未加入系统环境变量 PATH，请参考 README 配置！")
                else:
                    print(f"[LiveStream] Failed to start live converter for monitor {monitor_id}: {e}")
                    abort(500, description="Failed to launch live stream transcoder")
            except Exception as e:
                print(f"[LiveStream] Failed to start live converter for monitor {monitor_id}: {e}")
                abort(500, description="Failed to launch live stream transcoder")
                
    index_file = os.path.join(output_dir, "index.m3u8")
    # Wait up to 5 seconds for the index file to appear if it's new
    attempts = 0
    while not os.path.exists(index_file) and attempts < 10:
        time.sleep(0.5)
        attempts += 1
        
    if not os.path.exists(index_file):
        log_file_path = os.path.join(output_dir, "ffmpeg.log")
        ffmpeg_err = ""
        if os.path.exists(log_file_path):
            try:
                with open(log_file_path, "r", encoding="utf-8", errors="ignore") as f:
                    ffmpeg_err = f.read()
            except Exception as read_err:
                ffmpeg_err = f"Failed to read ffmpeg log: {read_err}"
        print(f"[LiveStream ERROR] ffmpeg failed to generate HLS files. ffmpeg output:\n{ffmpeg_err}")
        abort(404, description=f"M3U8 stream file not generated yet. FFmpeg stderr:\n{ffmpeg_err}")
        
    response = send_from_directory(output_dir, "index.m3u8", mimetype='application/x-mpegURL')
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response


@video_stream_bp.route('/live/<int:monitor_id>/<filename>')
def live_stream_segment(monitor_id, filename):
    output_dir = os.path.join(LIVE_STREAM_BASE, str(monitor_id))
    # Security check: filename must not contain directory traversal
    if ".." in filename or "/" in filename or "\\" in filename:
        abort(403, description="Access denied")
    response = send_from_directory(output_dir, filename)
    # Enable caching for .ts segments to improve performance
    if filename.endswith(".ts"):
        response.headers["Cache-Control"] = "public, max-age=86400"
    return response


@video_stream_bp.route('/thumbnail/<path:video_path>')
def serve_thumbnail(video_path):
    """
    Generate or serve a thumbnail image for a video file.
    GET /api/video/thumbnail/<path>
    """
    try:
        safe_video_path = _normalize_video_path(video_path)
        full_path = os.path.abspath(os.path.join(BACKEND_DIR, safe_video_path))

        if not full_path.startswith(BACKEND_DIR + os.sep) and full_path != BACKEND_DIR:
            abort(403, description="Access denied")

        if not os.path.exists(full_path):
            abort(404, description=f"Video not found: {safe_video_path}")

        # The thumbnail will be stored alongside the video, changing extension to _thumb.jpg
        thumb_path = os.path.splitext(full_path)[0] + "_thumb.jpg"

        if not os.path.exists(thumb_path):
            # Generate thumbnail on the fly using FFmpeg
            ffmpeg_bin = get_ffmpeg_path("ffmpeg")
            cmd = [
                ffmpeg_bin, "-y",
                "-ss", "0.000",
                "-i", full_path,
                "-vframes", "1",
                "-q:v", "2",
                "-f", "image2",
                thumb_path
            ]
            print(f"[Thumbnail Generation] command: {' '.join(cmd)}")
            subprocess.run(cmd, capture_output=True, timeout=5)

        if os.path.exists(thumb_path):
            return send_file(thumb_path, mimetype='image/jpeg')
        else:
            abort(500, description="Failed to generate thumbnail")
    except Exception as e:
        print(f"[Thumbnail Exception] {e}")
        abort(500, description=str(e))
