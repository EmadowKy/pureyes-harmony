from functools import wraps

from flask_jwt_extended import get_jwt_identity, jwt_required

from app.core.response import fail
from app.core.db import db
from app.models.group import Group, GroupMember
from app.models.user import User


ADMIN_ROLES = {"admin", "super_admin"}


def current_user():
    emp_id = get_jwt_identity()
    if not emp_id:
        return None
    return User.query.filter_by(emp_id=emp_id).first()


def is_admin(user):
    return bool(user and user.role in ADMIN_ROLES and user.is_active)


def is_super_admin(user):
    return bool(user and user.role == "super_admin" and user.is_active)


def role_required(*roles):
    def decorator(fn):
        @wraps(fn)
        @jwt_required()
        def wrapper(*args, **kwargs):
            user = current_user()
            if not user or not user.is_active:
                return fail(message="user is inactive or not found", code=2003, http_status=403)
            if user.role not in roles:
                return fail(message="permission denied", code=2001, http_status=403)
            return fn(*args, **kwargs)

        return wrapper

    return decorator


def accepted_member(group_id, emp_id):
    return GroupMember.query.filter_by(
        group_id=group_id,
        emp_id=emp_id,
        status="accepted",
    ).first()


def is_group_creator(group, emp_id):
    return bool(group and group.creator_id == emp_id)


def can_view_user(viewer, target_emp_id):
    if not viewer or not viewer.is_active:
        return False
    if viewer.emp_id == target_emp_id:
        return True
    if viewer.role in ADMIN_ROLES:
        return True

    viewer_groups = GroupMember.query.filter_by(
        emp_id=viewer.emp_id,
        status="accepted",
    ).with_entities(GroupMember.group_id)

    return GroupMember.query.filter(
        GroupMember.emp_id == target_emp_id,
        GroupMember.status == "accepted",
        GroupMember.group_id.in_(viewer_groups),
    ).first() is not None


def require_group_member(group_id, emp_id):
    group = db.session.get(Group, group_id)
    if not group:
        return None, None, fail(message="group not found", code=3002, http_status=404)
    member = accepted_member(group_id, emp_id)
    if not member:
        return group, None, fail(message="not a group member", code=3009, http_status=403)
    return group, member, None


def require_group_creator(group_id, emp_id):
    group = db.session.get(Group, group_id)
    if not group:
        return None, fail(message="group not found", code=3002, http_status=404)
    if not is_group_creator(group, emp_id):
        return group, fail(message="only group creator can perform this action", code=3003, http_status=403)
    return group, None
