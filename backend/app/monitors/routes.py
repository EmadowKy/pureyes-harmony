import os
import re
from datetime import datetime, timedelta

from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.db import db
from app.models.monitor import Monitor
from app.models.group import GroupMember
from app.user_center.permissions import require_group_creator
from app.core.response import success, fail
from . import monitors_bp
from .slicer import slice_video
from app.core.recorder import start_recording


RECORDINGS_BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "storage", "streams"))
SEGMENT_NAME_RE = re.compile(r"^(?P<stamp>\d{8}_\d{6})\.mp4$")


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
            "url": f"/api/video/storage/streams/{monitor_id}/{filename}"
        }
        items.append(item)
        if start_time <= selected_time < end_time:
            chosen_item = item

    return items, chosen_item

@monitors_bp.post("/<int:group_id>")
@jwt_required()
def add_monitor(group_id):
    emp_id = get_jwt_identity()
    group, error = require_group_creator(group_id, emp_id)
    if error:
        return error
        
    data = request.get_json() or {}
    name = data.get("name")
    stream_url = data.get("stream_url", "")
    
    if not name:
        return fail(message="monitor name is required", code=4002, http_status=400)
        
    monitor = Monitor(group_id=group_id, name=name, stream_url=stream_url)
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
    return success(data=[m.to_dict() for m in monitors])


@monitors_bp.get("/<int:monitor_id>/history")
@jwt_required()
def get_monitor_history(monitor_id):
    emp_id = get_jwt_identity()
    monitor = Monitor.query.get(monitor_id)
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
    monitor = Monitor.query.get(monitor_id)
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
    # This endpoint returns a URL to the sliced video
    emp_id = get_jwt_identity()
    monitor = Monitor.query.get(monitor_id)
    if not monitor:
        return fail(message="monitor not found", code=4003, http_status=404)
        
    member = GroupMember.query.filter_by(group_id=monitor.group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=4001, http_status=403)
        
    start_time = request.args.get("start")
    end_time = request.args.get("end")
    if not start_time or not end_time:
        return fail(message="start and end time are required", code=4004, http_status=400)
        
    # Execute slicing logic
    output_path = slice_video(monitor_id, start_time, end_time)
    
    # In a real app, this should return a URL to access the output_path via a static file server or another endpoint
    # Here we just return the path relative to a static route
    return success(data={"url": f"/api/static/slices/{output_path}"})
