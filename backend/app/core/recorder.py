import os
import shutil
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
SEGMENT_SECONDS = int(os.environ.get("MONITOR_RECORDING_SEGMENT_SECONDS", "60"))
RETENTION_HOURS = max(1, int(os.environ.get("MONITOR_RECORDING_RETENTION_HOURS", "24")))
MIN_FREE_GB = max(0.0, float(os.environ.get("MONITOR_MIN_FREE_DISK_GB", "2")))
SUPERVISOR_INTERVAL_SECONDS = max(15, int(os.environ.get("MONITOR_RECORDER_SUPERVISOR_SECONDS", "30")))


def _acquire_recording_lock(output_dir):
    """On Linux the child owns this lock until it exits, including orphan exits."""
    if os.name != 'posix':
        return None
    import fcntl
    fd = os.open(os.path.join(output_dir, '.recorder.lock'), os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return -1
    return fd


def _open_recording_paths():
    """Protect files held by any recorder, not just this Python process."""
    paths = set()
    proc_root = os.path.join(os.sep, 'proc')
    if os.name != 'posix' or not os.path.isdir(proc_root):
        return paths
    base = os.path.realpath(VIDEO_STORAGE_BASE) + os.sep
    for pid in os.listdir(proc_root):
        if not pid.isdigit():
            continue
        try:
            with open(os.path.join(proc_root, pid, 'comm')) as handle:
                if handle.read().strip() != 'ffmpeg':
                    continue
            fd_dir = os.path.join(proc_root, pid, 'fd')
            for fd in os.listdir(fd_dir):
                try:
                    target = os.path.realpath(os.path.join(fd_dir, fd))
                    if target.startswith(base) and target.endswith('.mp4'):
                        paths.add(target)
                except OSError:
                    pass
        except OSError:
            continue
    return paths


def recording_state(monitor_id: int) -> str:
    """Return the actual process state instead of trusting a stored label."""
    with recorder_lock:
        proc = recording_processes.get(monitor_id)
        if not proc:
            return "stopped"
        return "recording" if proc.poll() is None else "failed"

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
        lock_fd = _acquire_recording_lock(output_dir)
        if lock_fd == -1:
            return False
        
        # Build FFmpeg command
        cmd = [get_ffmpeg_path("ffmpeg"), "-y"]
        
        # Check RTSP TCP option
        if stream_url.strip().lower().startswith("rtsp://"):
            cmd.extend(["-rtsp_transport", "tcp"])
            
        cmd.extend([
            "-i", stream_url,
            "-an",
            "-c:v", "copy",
            "-f", "segment",
            "-segment_time", str(SEGMENT_SECONDS),
            "-reset_timestamps", "1",
            "-segment_format", "mp4",
            "-segment_format_options", "movflags=+frag_keyframe+empty_moov+default_base_moof",
            "-strftime", "1",
            os.path.join(output_dir, "%Y%m%d_%H%M%S.mp4")
        ])
        
        try:
            print(f"[Recorder] Starting recording for monitor {monitor_id}")
            # Start process in background. FFmpeg diagnostics are discarded so
            # recording a long-running stream cannot create unbounded log files.
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0,
                **({'pass_fds': (lock_fd,)} if lock_fd is not None else {})
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
        finally:
            if lock_fd is not None:
                os.close(lock_fd)

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
                if m.stream_url and m.stream_url.strip():
                    if m.status != "online":
                        m.status = "online"
                    start_recording(m.id, m.stream_url)
            db.session.commit()
        except Exception as e:
            print(f"[Recorder] Error during starting initial recordings: {e}")
            
    # Start cleanup thread
    t = threading.Thread(target=cleanup_old_recordings_loop, daemon=True)
    t.start()
    supervisor = threading.Thread(target=recording_supervisor_loop, args=(app,), daemon=True)
    supervisor.start()

def stop_all_recordings():
    """
    Terminates all running recording processes.
    """
    global recording_processes
    print("[Recorder] Stopping all background recordings...")
    monitor_ids = list(recording_processes.keys())
    for mid in monitor_ids:
        stop_recording(mid)

def _delete_expired_recordings() -> None:
    """Apply retention and a disk-watermark guard to finalized recordings."""
    if not os.path.exists(VIDEO_STORAGE_BASE):
        return
    now = datetime.now()
    cutoff = now - timedelta(hours=RETENTION_HOURS)
    candidates = []
    active_paths = _open_recording_paths()
    # Conservative fallback for Windows or inaccessible process descriptors.
    # Recently written files must not be unlinked even if disk space is low.
    write_grace = max(SEGMENT_SECONDS * 3, 180)
    for monitor_dir in os.listdir(VIDEO_STORAGE_BASE):
        monitor_path = os.path.join(VIDEO_STORAGE_BASE, monitor_dir)
        if not os.path.isdir(monitor_path) or os.path.islink(monitor_path):
            continue
        for file in os.listdir(monitor_path):
            if not file.endswith(".mp4"):
                continue
            file_path = os.path.join(monitor_path, file)
            if os.path.islink(file_path):
                continue
            try:
                if os.path.realpath(file_path) in active_paths:
                    continue
                if time.time() - os.path.getmtime(file_path) < write_grace:
                    continue
                file_time = datetime.strptime(os.path.splitext(file)[0], "%Y%m%d_%H%M%S")
            except OSError:
                continue
            except ValueError:
                file_time = datetime.fromtimestamp(os.path.getmtime(file_path))
            if file_time < cutoff:
                try:
                    if time.time() - os.path.getmtime(file_path) >= write_grace:
                        os.remove(file_path)
                except OSError:
                    pass
            else:
                candidates.append((file_time, file_path))

    # Never allow a monitor recorder to fill the system volume. Delete oldest
    # retained files only while below the configured free-space watermark.
    target_free_bytes = int(MIN_FREE_GB * 1024 * 1024 * 1024)
    for _, file_path in sorted(candidates):
        if shutil.disk_usage(VIDEO_STORAGE_BASE).free >= target_free_bytes:
            break
        try:
            # Recheck immediately before deletion in case a writer resumed.
            if time.time() - os.path.getmtime(file_path) >= write_grace:
                os.remove(file_path)
        except OSError:
            pass


def cleanup_old_recordings_loop():
    """
    Loop that runs in a background thread to remove recordings older than 24 hours.
    """
    while True:
        try:
            _delete_expired_recordings()
        except Exception as e:
            print(f"[Recorder] Error cleaning up expired recordings: {e}")
            
        time.sleep(300)  # Check every 5 minutes


def recording_supervisor_loop(app):
    """Restart a failed recorder rather than leaving a monitor falsely online."""
    while True:
        try:
            with app.app_context():
                for monitor in Monitor.query.filter(Monitor.stream_url.isnot(None)).all():
                    stream_url = (monitor.stream_url or "").strip()
                    if stream_url and recording_state(monitor.id) != "recording":
                        start_recording(monitor.id, stream_url)
        except Exception as exc:
            print(f"[Recorder] supervisor error: {exc}")
        time.sleep(SUPERVISOR_INTERVAL_SECONDS)
