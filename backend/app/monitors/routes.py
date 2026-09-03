import os
import re
import shutil
import subprocess
import threading
import time
from datetime import datetime, timedelta

from flask import Response, abort, request, send_file
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.config import get_ffmpeg_path
from app.core.db import db
from app.models.monitor import Monitor
from app.models.qa_record import QAVideoSelection
from app.models.group import GroupMember
from app.user_center.permissions import current_user, is_admin, require_group_creator
from app.core.response import success, fail
from app.core.media_auth import build_media_url, media_access_identity, monitor_scope, path_scope
from . import monitors_bp
from .slicer import slice_video
from app.core.recorder import start_recording, stop_recording


BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RECORDINGS_BASE = os.path.join(BACKEND_ROOT, "storage", "streams")
COVERS_BASE = os.path.join(BACKEND_ROOT, "storage", "monitor_covers")
SEGMENT_NAME_RE = re.compile(r"^(?P<stamp>\d{8}_\d{6})\.mp4$")
COVER_REFRESH_INTERVAL_SECONDS = int(os.environ.get("MONITOR_COVER_INTERVAL_SECONDS", "60"))
COVER_ACTIVE_FILE_GRACE_SECONDS = int(os.environ.get("MONITOR_COVER_ACTIVE_FILE_GRACE_SECONDS", "15"))
cover_refresh_started = False
cover_refresh_lock = threading.Lock()


def _parse_segment_time(filename: str):
    match = SEGMENT_NAME_RE.match(filename)
    if not match:
        return None
    try:
        return datetime.strptime(match.group("stamp"), "%Y%m%d_%H%M%S")
    except ValueError:
        return None


def _monitor_recordings_dir(monitor_id: int) -> str:
    return os.path.join(RECORDINGS_BASE, str(monitor_id))


def _monitor_cover_path(monitor_id: int) -> str:
    return os.path.join(COVERS_BASE, f"{monitor_id}.jpg")


def _remove_monitor_cover(monitor: Monitor) -> None:
    cover_path = _monitor_cover_path(monitor.id)
    try:
        if os.path.exists(cover_path):
            os.remove(cover_path)
    except OSError as exc:
        print(f"[MonitorCover] failed to remove cover for monitor {monitor.id}: {exc}")
    monitor.cover_path = None
    monitor.cover_updated_at = None


def _relative_backend_path(path: str) -> str:
    return os.path.relpath(path, BACKEND_ROOT).replace("\\", "/")


def _absolute_backend_path(path: str) -> str:
    full_path = os.path.abspath(os.path.join(BACKEND_ROOT, path.replace("/", os.sep)))
    if not full_path.startswith(BACKEND_ROOT + os.sep) and full_path != BACKEND_ROOT:
        raise ValueError("invalid backend path")
    return full_path


def _latest_recording_file(monitor_id: int):
    output_dir = _monitor_recordings_dir(monitor_id)
    if not os.path.exists(output_dir):
        return None

    candidates = []
    for filename in os.listdir(output_dir):
        if not filename.endswith(".mp4"):
            continue
        start_time = _parse_segment_time(filename)
        if not start_time:
            continue
        full_path = os.path.join(output_dir, filename)
        if not os.path.isfile(full_path) or os.path.getsize(full_path) == 0:
            continue
        file_is_recent = time.time() - os.path.getmtime(full_path) < COVER_ACTIVE_FILE_GRACE_SECONDS
        segment_may_be_active = datetime.now() < start_time + timedelta(seconds=60)
        if file_is_recent and segment_may_be_active:
            continue
        candidates.append((start_time, full_path))

    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def _refresh_monitor_cover(monitor: Monitor) -> bool:
    latest_path = _latest_recording_file(monitor.id)
    if not latest_path:
        return False

    cover_path = _monitor_cover_path(monitor.id)
    latest_mtime = os.path.getmtime(latest_path)
    if os.path.exists(cover_path) and os.path.getmtime(cover_path) >= latest_mtime:
        if not monitor.cover_path:
            monitor.cover_path = _relative_backend_path(cover_path)
            monitor.cover_updated_at = datetime.utcnow()
            return True
        return False

    os.makedirs(COVERS_BASE, exist_ok=True)
    cmd = [
        get_ffmpeg_path("ffmpeg"), "-y",
        "-sseof", "-1",
        "-i", latest_path,
        "-vframes", "1",
        "-q:v", "2",
        "-update", "1",
        "-f", "image2",
        cover_path,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode != 0 or not os.path.exists(cover_path) or os.path.getsize(cover_path) == 0:
            print(f"[MonitorCover] failed for monitor {monitor.id}: {result.stderr[-500:] if result.stderr else ''}")
            return False
    except Exception as exc:
        print(f"[MonitorCover] exception for monitor {monitor.id}: {exc}")
        return False

    monitor.cover_path = _relative_backend_path(cover_path)
    monitor.cover_updated_at = datetime.utcnow()
    return True


def refresh_all_monitor_covers() -> int:
    changed_count = 0
    monitors = Monitor.query.filter(Monitor.stream_url.isnot(None)).all()
    for monitor in monitors:
        if not (monitor.stream_url or "").strip():
            continue
        if _refresh_monitor_cover(monitor):
            changed_count += 1
    if changed_count:
        db.session.commit()
    return changed_count


def start_cover_refresh_loop(app) -> None:
    global cover_refresh_started
    with cover_refresh_lock:
        if cover_refresh_started:
            return
        cover_refresh_started = True

    def loop() -> None:
        while True:
            try:
                with app.app_context():
                    refresh_all_monitor_covers()
            except Exception as exc:
                print(f"[MonitorCover] refresh loop error: {exc}")
            time.sleep(max(30, COVER_REFRESH_INTERVAL_SECONDS))

    thread = threading.Thread(target=loop, daemon=True)
    thread.start()


def _parse_client_time(raw: str):
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo:
        parsed = parsed.astimezone().replace(tzinfo=None)
    return parsed


def _build_recording_items(monitor_id: int, selected_time: datetime, window_count: int, step_seconds: int):
    output_dir = _monitor_recordings_dir(monitor_id)
    if not os.path.exists(output_dir):
        return [], None

    segment_files = []
    for filename in os.listdir(output_dir):
        if not filename.endswith(".mp4"):
            continue
        start_time = _parse_segment_time(filename)
        if not start_time:
            continue
        segment_files.append((start_time, filename))

    segment_files.sort(key=lambda item: item[0])
    if not segment_files:
        return [], None

    window_seconds = max(step_seconds * window_count * 2, 60)
    window_start = selected_time - timedelta(seconds=window_seconds // 2)
    window_end = selected_time + timedelta(seconds=window_seconds // 2)

    items = []
    chosen_item = None
    for start_time, filename in segment_files:
        end_time = start_time + timedelta(seconds=60)
        if end_time < window_start or start_time > window_end:
            continue

        item = {
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "filename": filename,
            "url": build_media_url(
                f"/api/video/storage/streams/{monitor_id}/{filename}",
                path_scope(f"storage/streams/{monitor_id}/{filename}"),
            )
        }
        items.append(item)
        if start_time <= selected_time < end_time:
            chosen_item = item

    return items, chosen_item


def _require_monitor_creator(monitor_id: int, emp_id: str):
    monitor = db.session.get(Monitor, monitor_id)
    if not monitor:
        return None, fail(message="monitor not found", code=4003, http_status=404)
    user = current_user()
    if is_admin(user):
        return monitor, None
    _, error = require_group_creator(monitor.group_id, emp_id)
    if error:
        return None, error
    return monitor, None


@monitors_bp.post("/<int:group_id>")
@jwt_required()
def add_monitor(group_id):
    emp_id = get_jwt_identity()
    group, error = require_group_creator(group_id, emp_id)
    if error:
        return error

    data = request.get_json() or {}
    name = (data.get("name") or "").strip()
    stream_url = (data.get("stream_url") or "").strip()

    if not name:
        return fail(message="monitor name is required", code=4002, http_status=400)

    monitor = Monitor(group_id=group_id, name=name, stream_url=stream_url, status="online" if stream_url else "offline")
    db.session.add(monitor)
    db.session.commit()

    if monitor.stream_url:
        start_recording(monitor.id, monitor.stream_url)

    return success(message="monitor added", data=monitor.to_dict(), http_status=201)


@monitors_bp.get("/<int:group_id>")
@jwt_required()
def get_monitors(group_id):
    emp_id = get_jwt_identity()
    member = GroupMember.query.filter_by(group_id=group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=4001, http_status=403)

    monitors = Monitor.query.filter_by(group_id=group_id).all()
    changed = False
    for monitor in monitors:
        changed = _refresh_monitor_cover(monitor) or changed
    if changed:
        db.session.commit()
    return success(data=[m.to_dict() for m in monitors])


@monitors_bp.put("/<int:monitor_id>")
@jwt_required()
def update_monitor(monitor_id):
    emp_id = get_jwt_identity()
    monitor, error = _require_monitor_creator(monitor_id, emp_id)
    if error:
        return error

    data = request.get_json() or {}
    next_name = ((data.get("name") if "name" in data else monitor.name) or "").strip()
    next_url = ((data.get("stream_url") if "stream_url" in data else monitor.stream_url) or "").strip()
    if not next_name:
        return fail(message="monitor name is required", code=4002, http_status=400)

    url_changed = next_url != (monitor.stream_url or "")
    monitor.name = next_name
    monitor.stream_url = next_url
    if url_changed:
        stop_recording(monitor.id)
        _remove_monitor_cover(monitor)

    db.session.commit()

    if url_changed and monitor.stream_url:
        start_recording(monitor.id, monitor.stream_url)

    return success(message="monitor updated", data=monitor.to_dict())


@monitors_bp.delete("/<int:monitor_id>")
@jwt_required()
def delete_monitor(monitor_id):
    emp_id = get_jwt_identity()
    monitor, error = _require_monitor_creator(monitor_id, emp_id)
    if error:
        return error

    stop_recording(monitor.id)
    recordings_dir = _monitor_recordings_dir(monitor.id)
    cover_path = _monitor_cover_path(monitor.id)
    QAVideoSelection.query.filter_by(monitor_id=monitor.id).delete(synchronize_session=False)
    db.session.delete(monitor)
    db.session.commit()

    for path in [recordings_dir, cover_path]:
        try:
            if os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)
            elif os.path.exists(path):
                os.remove(path)
        except OSError as exc:
            print(f"[MonitorDelete] failed to remove {path}: {exc}")

    return success(message="monitor deleted")


@monitors_bp.get("/<int:monitor_id>/cover")
def get_monitor_cover(monitor_id):
    monitor = db.session.get(Monitor, monitor_id)
    if not monitor:
        return fail(message="monitor not found", code=4003, http_status=404)
    emp_id = media_access_identity(monitor_scope(monitor_id))
    member = GroupMember.query.filter_by(
        group_id=monitor.group_id,
        emp_id=emp_id,
        status="accepted",
    ).first() if emp_id else None
    if not member:
        abort(401)

    if _refresh_monitor_cover(monitor):
        db.session.commit()

    if not monitor.cover_path:
        return fail(message="monitor cover not ready", code=4045, http_status=404)

    try:
        cover_path = _absolute_backend_path(monitor.cover_path)
    except ValueError:
        return fail(message="invalid cover path", code=4046, http_status=404)

    if not os.path.exists(cover_path):
        monitor.cover_path = None
        monitor.cover_updated_at = None
        db.session.commit()
        return fail(message="monitor cover not ready", code=4045, http_status=404)

    try:
        with open(cover_path, "rb") as image_file:
            image_bytes = image_file.read()
    except OSError:
        monitor.cover_path = None
        monitor.cover_updated_at = None
        db.session.commit()
        return fail(message="monitor cover not ready", code=4045, http_status=404)

    return Response(image_bytes, mimetype="image/jpeg")


@monitors_bp.get("/<int:monitor_id>/history")
@jwt_required()
def get_monitor_history(monitor_id):
    emp_id = get_jwt_identity()
    monitor = db.session.get(Monitor, monitor_id)
    if not monitor:
        return fail(message="monitor not found", code=4003, http_status=404)

    member = GroupMember.query.filter_by(group_id=monitor.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=4001, http_status=403)

    anchor_raw = request.args.get("anchor") or request.args.get("time")
    step_seconds_map = {
        "day": 86400,
        "hour": 3600,
        "minute": 60,
        "second": 1,
    }
    granularity = (request.args.get("granularity") or "minute").lower()
    if granularity not in step_seconds_map:
        return fail(message="invalid granularity", code=4006, http_status=400)
    step_seconds = step_seconds_map[granularity]

    try:
        window_count = max(1, min(int(request.args.get("window") or 6), 60))
    except ValueError:
        return fail(message="invalid window", code=4007, http_status=400)

    if anchor_raw:
        selected_time = _parse_client_time(anchor_raw)
        if not selected_time:
            return fail(message="invalid anchor time", code=4005, http_status=400)
    else:
        selected_time = datetime.now()

    items, chosen_item = _build_recording_items(monitor_id, selected_time, window_count, step_seconds)
    window_seconds = max(step_seconds * window_count, 60)
    return success(data={
        "monitor": monitor.to_dict(),
        "selected_time": selected_time.isoformat(),
        "window_start": (selected_time - timedelta(seconds=window_seconds)).isoformat(),
        "window_end": (selected_time + timedelta(seconds=window_seconds)).isoformat(),
        "granularity": granularity,
        "window": window_count,
        "step_seconds": step_seconds,
        "records": items,
        "selected_record": chosen_item,
    })


@monitors_bp.get("/<int:monitor_id>/playback")
@jwt_required()
def get_monitor_playback(monitor_id):
    emp_id = get_jwt_identity()
    monitor = db.session.get(Monitor, monitor_id)
    if not monitor:
        return fail(message="monitor not found", code=4003, http_status=404)

    member = GroupMember.query.filter_by(group_id=monitor.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=4001, http_status=403)

    target_raw = request.args.get("time") or request.args.get("anchor")
    if not target_raw:
        return fail(message="time is required", code=4004, http_status=400)

    target_time = _parse_client_time(target_raw)
    if not target_time:
        return fail(message="invalid time", code=4005, http_status=400)

    items, chosen_item = _build_recording_items(monitor_id, target_time, window_count=3, step_seconds=60)
    if not chosen_item:
        return fail(message="recording not found for selected time", code=4044, http_status=404)

    return success(data={
        "monitor": monitor.to_dict(),
        "target_time": target_time.isoformat(),
        "record": chosen_item,
        "records": items,
    })


@monitors_bp.get("/<int:monitor_id>/slice")
@jwt_required()
def get_monitor_slice(monitor_id):
    emp_id = get_jwt_identity()
    monitor = db.session.get(Monitor, monitor_id)
    if not monitor:
        return fail(message="monitor not found", code=4003, http_status=404)

    member = GroupMember.query.filter_by(group_id=monitor.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=4001, http_status=403)

    start_time = request.args.get("start")
    end_time = request.args.get("end")
    if not start_time or not end_time:
        return fail(message="start and end time are required", code=4004, http_status=400)

    output_path = slice_video(monitor_id, start_time, end_time)
    return success(data={"url": f"/api/static/slices/{output_path}"})
