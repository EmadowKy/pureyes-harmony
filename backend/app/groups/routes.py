from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.core.db import db
from app.models.group import Group, GroupMember
from app.models.user import User
from app.core.response import success, fail
from app.user_center.permissions import require_group_creator, require_group_member
from app.user_center.serializers import group_to_dict, membership_to_dict
from . import groups_bp


def _clean(value):
    return value.strip() if isinstance(value, str) else value

@groups_bp.post("/")
@jwt_required()
def create_group():
    emp_id = get_jwt_identity()
    data = request.get_json() or {}
    name = _clean(data.get("name"))
    if not name:
        return fail(message="group name is required", code=3001, http_status=400)
    
    group = Group(name=name, creator_id=emp_id)
    db.session.add(group)
    db.session.flush() # get group id
    
    # Creator automatically joins as accepted member
    member = GroupMember(group_id=group.id, emp_id=emp_id, status="accepted")
    db.session.add(member)
    db.session.commit()
    
    return success(
        message="group created",
        data=group_to_dict(group, current_emp_id=emp_id, include_counts=True),
        http_status=201,
    )

@groups_bp.get("/")
@jwt_required()
def get_my_groups():
    emp_id = get_jwt_identity()
    memberships = GroupMember.query.filter_by(emp_id=emp_id, status="accepted").all()
    group_ids = [m.group_id for m in memberships]
    if not group_ids:
        return success(data=[])
    groups = Group.query.filter(Group.id.in_(group_ids)).order_by(Group.created_at.desc()).all()
    return success(data=[group_to_dict(g, current_emp_id=emp_id, include_counts=True) for g in groups])


@groups_bp.get("/<int:group_id>")
@jwt_required()
def get_group(group_id):
    emp_id = get_jwt_identity()
    group, member, error = require_group_member(group_id, emp_id)
    if error:
        return error
    data = group_to_dict(group, current_emp_id=emp_id, include_counts=True)
    data["membership"] = member.to_dict()
    return success(data=data)


@groups_bp.put("/<int:group_id>")
@jwt_required()
def update_group(group_id):
    emp_id = get_jwt_identity()
    group, error = require_group_creator(group_id, emp_id)
    if error:
        return error

    name = _clean((request.get_json() or {}).get("name"))
    if not name:
        return fail(message="group name is required", code=3001, http_status=400)

    group.name = name
    db.session.commit()
    return success(message="group updated", data=group_to_dict(group, current_emp_id=emp_id, include_counts=True))

@groups_bp.get("/invites")
@jwt_required()
def get_my_invites():
    emp_id = get_jwt_identity()
    memberships = GroupMember.query.filter_by(emp_id=emp_id, status="pending").all()
    results = []
    for m in memberships:
        group = db.session.get(Group, m.group_id)
        if group:
            results.append(membership_to_dict(m, group=group))
    return success(data=results)

@groups_bp.post("/<int:group_id>/invite")
@jwt_required()
def invite_member(group_id):
    emp_id = get_jwt_identity()
    group, error = require_group_creator(group_id, emp_id)
    if error:
        return error
        
    data = request.get_json() or {}
    invitee_emp_id = _clean(data.get("emp_id"))
    if not invitee_emp_id:
        return fail(message="emp_id is required", code=3004, http_status=400)
    if invitee_emp_id == emp_id:
        return fail(message="cannot invite yourself", code=3010, http_status=400)
        
    user = User.query.filter_by(emp_id=invitee_emp_id).first()
    if not user:
        return fail(message="user not found", code=3005, http_status=404)
    if not user.is_active:
        return fail(message="user is inactive", code=3011, http_status=403)
        
    existing_member = GroupMember.query.filter_by(group_id=group_id, emp_id=invitee_emp_id).first()
    if existing_member:
        return fail(message="user is already a member or invited", code=3006, http_status=409)
        
    new_member = GroupMember(group_id=group_id, emp_id=invitee_emp_id, status="pending")
    db.session.add(new_member)
    db.session.commit()
    
    return success(message="invitation sent", data=membership_to_dict(new_member, user=user, group=group), http_status=201)

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


@groups_bp.get("/<int:group_id>/invites")
@jwt_required()
def get_group_invites(group_id):
    emp_id = get_jwt_identity()
    group, error = require_group_creator(group_id, emp_id)
    if error:
        return error

    memberships = GroupMember.query.filter_by(group_id=group_id, status="pending").all()
    return success(data=[membership_to_dict(m, group=group) for m in memberships])

@groups_bp.get("/<int:group_id>/members")
@jwt_required()
def get_group_members(group_id):
    emp_id = get_jwt_identity()
    group, member, error = require_group_member(group_id, emp_id)
    if error:
        return error

    include_pending = request.args.get("include_pending") in {"1", "true", "yes"}
    query = GroupMember.query.filter_by(group_id=group_id)
    if include_pending and group.creator_id == emp_id:
        memberships = query.filter(GroupMember.status.in_(["accepted", "pending"])).all()
    else:
        memberships = query.filter_by(status="accepted").all()

    emp_ids = [m.emp_id for m in memberships]
    users = User.query.filter(User.emp_id.in_(emp_ids)).all()
    users_by_id = {u.emp_id: u for u in users}

    data = []
    for membership in memberships:
        item = membership_to_dict(membership, user=users_by_id.get(membership.emp_id), group=group)
        item["is_creator"] = membership.emp_id == group.creator_id
        data.append(item)

    data.sort(key=lambda item: (item["status"] != "accepted", not item["is_creator"], item.get("name") or ""))
    return success(data=data)


@groups_bp.delete("/<int:group_id>/members/<emp_id>")
@jwt_required()
def remove_group_member(group_id, emp_id):
    actor_emp_id = get_jwt_identity()
    group, error = require_group_creator(group_id, actor_emp_id)
    if error:
        return error
    if emp_id == group.creator_id:
        return fail(message="cannot remove group creator", code=3012, http_status=403)

    member = GroupMember.query.filter_by(group_id=group_id, emp_id=emp_id).first()
    if not member:
        return fail(message="member not found", code=3013, http_status=404)

    db.session.delete(member)
    db.session.commit()
    return success(message="member removed")


@groups_bp.post("/<int:group_id>/leave")
@jwt_required()
def leave_group(group_id):
    emp_id = get_jwt_identity()
    group, member, error = require_group_member(group_id, emp_id)
    if error:
        return error
    if group.creator_id == emp_id:
        return fail(message="group creator cannot leave the group", code=3014, http_status=403)

    db.session.delete(member)
    db.session.commit()
    return success(message="left group")
