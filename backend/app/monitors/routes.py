from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.db import db
from app.models.monitor import Monitor
from app.models.group import GroupMember
from app.core.response import success, fail
from . import monitors_bp
from .slicer import slice_video

@monitors_bp.post("/<int:group_id>")
@jwt_required()
def add_monitor(group_id):
    emp_id = get_jwt_identity()
    member = GroupMember.query.filter_by(group_id=group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=4001, http_status=403)
        
    data = request.get_json() or {}
    name = data.get("name")
    stream_url = data.get("stream_url", "")
    
    if not name:
        return fail(message="monitor name is required", code=4002, http_status=400)
        
    monitor = Monitor(group_id=group_id, name=name, stream_url=stream_url)
    db.session.add(monitor)
    db.session.commit()
    
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
