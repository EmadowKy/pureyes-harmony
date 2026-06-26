from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.db import db
from app.models.group import Group, GroupMember
from app.models.user import User
from app.core.response import success, fail
from . import groups_bp

@groups_bp.post("/")
@jwt_required()
def create_group():
    emp_id = get_jwt_identity()
    data = request.get_json() or {}
    name = data.get("name")
    if not name:
        return fail(message="group name is required", code=3001, http_status=400)
    
    group = Group(name=name, creator_id=emp_id)
    db.session.add(group)
    db.session.flush() # get group id
    
    # Creator automatically joins as accepted member
    member = GroupMember(group_id=group.id, emp_id=emp_id, status="accepted")
    db.session.add(member)
    db.session.commit()
    
    return success(message="group created", data=group.to_dict(), http_status=201)

@groups_bp.get("/")
@jwt_required()
def get_my_groups():
    emp_id = get_jwt_identity()
    # Get groups where user is accepted
    memberships = GroupMember.query.filter_by(emp_id=emp_id, status="accepted").all()
    group_ids = [m.group_id for m in memberships]
    groups = Group.query.filter(Group.id.in_(group_ids)).all()
    return success(data=[g.to_dict() for g in groups])

@groups_bp.get("/invites")
@jwt_required()
def get_my_invites():
    emp_id = get_jwt_identity()
    memberships = GroupMember.query.filter_by(emp_id=emp_id, status="pending").all()
    results = []
    for m in memberships:
        group = Group.query.get(m.group_id)
        if group:
            results.append({
                "group_id": group.id,
                "group_name": group.name,
                "creator_id": group.creator_id,
                "joined_at": m.joined_at.isoformat() + "Z"
            })
    return success(data=results)

@groups_bp.post("/<int:group_id>/invite")
@jwt_required()
def invite_member(group_id):
    emp_id = get_jwt_identity()
    group = Group.query.get(group_id)
    if not group:
        return fail(message="group not found", code=3002, http_status=404)
        
    if group.creator_id != emp_id:
        return fail(message="only creator can invite members", code=3003, http_status=403)
        
    data = request.get_json() or {}
    invitee_emp_id = data.get("emp_id")
    if not invitee_emp_id:
        return fail(message="emp_id is required", code=3004, http_status=400)
        
    user = User.query.filter_by(emp_id=invitee_emp_id).first()
    if not user:
        return fail(message="user not found", code=3005, http_status=404)
        
    existing_member = GroupMember.query.filter_by(group_id=group_id, emp_id=invitee_emp_id).first()
    if existing_member:
        return fail(message="user is already a member or invited", code=3006, http_status=409)
        
    new_member = GroupMember(group_id=group_id, emp_id=invitee_emp_id, status="pending")
    db.session.add(new_member)
    db.session.commit()
    
    return success(message="invitation sent")

@groups_bp.post("/<int:group_id>/respond")
@jwt_required()
def respond_invite(group_id):
    emp_id = get_jwt_identity()
    data = request.get_json() or {}
    action = data.get("action") # accept / reject
    
    if action not in ["accept", "reject"]:
        return fail(message="invalid action", code=3007, http_status=400)
        
    member = GroupMember.query.filter_by(group_id=group_id, emp_id=emp_id, status="pending").first()
    if not member:
        return fail(message="invitation not found", code=3008, http_status=404)
        
    if action == "accept":
        member.status = "accepted"
        db.session.commit()
        return success(message="invitation accepted")
    else:
        db.session.delete(member)
        db.session.commit()
        return success(message="invitation rejected")

@groups_bp.get("/<int:group_id>/members")
@jwt_required()
def get_group_members(group_id):
    emp_id = get_jwt_identity()
    member = GroupMember.query.filter_by(group_id=group_id, emp_id=emp_id, status="accepted").first()
    if not member:
        return fail(message="not a group member", code=3009, http_status=403)
        
    memberships = GroupMember.query.filter_by(group_id=group_id, status="accepted").all()
    emp_ids = [m.emp_id for m in memberships]
    users = User.query.filter(User.emp_id.in_(emp_ids)).all()
    
    return success(data=[u.to_dict() for u in users])
