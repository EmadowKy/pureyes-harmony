import os
import subprocess
import threading
import time
from datetime import datetime, timedelta
from flask import current_app
from app.core.db import db
from app.models.monitor import Monitor
from app.core.config import get_ffmpeg_path

# Global dictionary to keep track of running recording processes { monitor_id: subprocess.Popen }
recording_processes = {}
recorder_lock = threading.Lock()

# Base storage path for recordings
VIDEO_STORAGE_BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "storage", "streams"))

def start_recording(monitor_id: int, stream_url: str) -> bool:
    """
    Starts an FFmpeg process to record the camera live stream in 60-second segments.
    """
    global recording_processes
    
    if not stream_url:
        print(f"[Recorder] Monitor {monitor_id} has no stream URL. Skipping.")
        return False
        
    with recorder_lock:
        if monitor_id in recording_processes:
            # Check if process is still running
            proc = recording_processes[monitor_id]
            if proc.poll() is None:
                print(f"[Recorder] Monitor {monitor_id} is already being recorded.")
                return True
            else:
                del recording_processes[monitor_id]

        output_dir = os.path.join(VIDEO_STORAGE_BASE, str(monitor_id))
        os.makedirs(output_dir, exist_ok=True)
        
        # Build FFmpeg command
        cmd = [get_ffmpeg_path("ffmpeg"), "-y"]
        
        # Check RTSP TCP option
        if stream_url.strip().lower().startswith("rtsp://"):
            cmd.extend(["-rtsp_transport", "tcp"])
            
        cmd.extend([
            "-i", stream_url,
            "-an",
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-tune", "zerolatency",
            "-pix_fmt", "yuv420p",
            "-force_key_frames", "expr:gte(t,n_forced*2)",
            "-f", "segment",
            "-segment_time", "60",
            "-reset_timestamps", "1",
            "-segment_format", "mp4",
            "-strftime", "1",
            os.path.join(output_dir, "%Y%m%d_%H%M%S.mp4")
        ])
        
        try:
            print(f"[Recorder] Starting recording command for monitor {monitor_id}: {' '.join(cmd)}")
            # Start process in background
            # We redirect stdout/stderr to devnull to avoid blocking Popen or spamming logs
            log_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "logs"))
            os.makedirs(log_dir, exist_ok=True)
            log_path = os.path.join(log_dir, f"recorder_{monitor_id}.log")
            log_file = open(log_path, "ab")
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=log_file,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
            )
            recording_processes[monitor_id] = proc
            return True
        except (FileNotFoundError, OSError) as e:
            if getattr(e, 'winerror', None) == 2 or getattr(e, 'errno', None) == 2 or "系统找不到指定的文件" in str(e):
                print(f"[Recorder ERROR] 系统找不到 ffmpeg 可执行文件！请确认已将 FFmpeg 安装并加入系统 PATH 环境变量。")
            else:
                print(f"[Recorder] Failed to start FFmpeg recording for monitor {monitor_id}: {e}")
            return False
        except Exception as e:
            print(f"[Recorder] Failed to start FFmpeg recording for monitor {monitor_id}: {e}")
            return False

def stop_recording(monitor_id: int):
    """
    Stops the FFmpeg recording process for the monitor.
    """
    global recording_processes
    with recorder_lock:
        if monitor_id in recording_processes:
            proc = recording_processes[monitor_id]
            if proc.poll() is None:
                print(f"[Recorder] Stopping recording for monitor {monitor_id}...")
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
            del recording_processes[monitor_id]

def start_all_recordings(app):
    """
    Loads all monitors and launches recording threads/processes.
    """
    print("[Recorder] Launching background recording manager...")
    with app.app_context():
        try:
            monitors = Monitor.query.all()
            for m in monitors:
                if m.stream_url and m.status == "online":
                    start_recording(m.id, m.stream_url)
        except Exception as e:
            print(f"[Recorder] Error during starting initial recordings: {e}")
            
    # Start cleanup thread
    t = threading.Thread(target=cleanup_old_recordings_loop, daemon=True)
    t.start()

def stop_all_recordings():
    """
    Terminates all running recording processes.
    """
    global recording_processes
    print("[Recorder] Stopping all background recordings...")
    monitor_ids = list(recording_processes.keys())
    for mid in monitor_ids:
        stop_recording(mid)

def cleanup_old_recordings_loop():
    """
    Loop that runs in a background thread to remove recordings older than 24 hours.
    """
    while True:
        try:
            if os.path.exists(VIDEO_STORAGE_BASE):
                now = datetime.now()
                cutoff = now - timedelta(hours=24)
                
                # Scan monitor folders
                for monitor_dir in os.listdir(VIDEO_STORAGE_BASE):
                    monitor_path = os.path.join(VIDEO_STORAGE_BASE, monitor_dir)
                    if os.path.isdir(monitor_path):
                        for file in os.listdir(monitor_path):
                            if file.endswith(".mp4"):
                                file_path = os.path.join(monitor_path, file)
                                try:
                                    # Parse date from segment name: %Y%m%d_%H%M%S.mp4
                                    basename = os.path.splitext(file)[0]
                                    file_time = datetime.strptime(basename, "%Y%m%d_%H%M%S")
                                    if file_time < cutoff:
                                        print(f"[Recorder] Cleaning up expired segment file: {file_path}")
                                        os.remove(file_path)
                                except Exception as parse_err:
                                    # Fall back to file modification time if parse fails
                                    try:
                                        mtime = datetime.fromtimestamp(os.path.getmtime(file_path))
                                        if mtime < cutoff:
                                            os.remove(file_path)
                                    except:
                                        pass
        except Exception as e:
            print(f"[Recorder] Error cleaning up expired recordings: {e}")
            
        time.sleep(300)  # Check every 5 minutes
