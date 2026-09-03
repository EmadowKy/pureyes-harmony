from flask import request
from flask_jwt_extended import get_jwt_identity
from app.core.db import db
from app.models.group import Group, GroupMember
from app.models.qa_record import QARecord
from app.models.user import User
from app.models.workspace import Workspace
from app.core.response import success, fail
from app.core.network_security import validate_llm_base_url
from app.user_center.permissions import active_user_required, can_view_user, current_user, role_required
from app.user_center.serializers import user_to_dict
from . import users_bp

USER_MUTABLE_FIELDS = {"name", "phone", "avatar", "llm_base_url", "llm_model"}


def _clean(value):
    return value.strip() if isinstance(value, str) else value


def _apply_user_updates(user, data):
    if "llm_base_url" in data:
        try:
            data = dict(data)
            data["llm_base_url"] = validate_llm_base_url(data.get("llm_base_url"))
        except ValueError as exc:
            return fail(message=str(exc), code=2011, http_status=400)

    for field in USER_MUTABLE_FIELDS:
        if field in data:
            setattr(user, field, _clean(data.get(field)))

    if data.get("clear_llm_api_key") is True:
        user.llm_api_key = None
    elif "llm_api_key" in data:
        next_api_key = _clean(data.get("llm_api_key"))
        if next_api_key:
            user.llm_api_key = next_api_key

    if "password" in data and data["password"]:
        password = str(data["password"])
        if len(password) < 6:
            return fail(message="password must be at least 6 chars", code=2004, http_status=400)
        user.set_password(password)
        user.auth_version = (user.auth_version or 0) + 1
    return None


def _ensure_can_operate_target(actor, user):
    if not actor:
        return fail(message="permission denied", code=2001, http_status=403)
    if user.role == "super_admin":
        return fail(message="cannot operate super_admin", code=2008, http_status=403)
    if actor.emp_id == user.emp_id:
        return fail(message="cannot operate yourself here", code=2010, http_status=403)
    return None


def _transfer_user_owned_data(emp_id, actor_emp_id):
    owned_groups = Group.query.filter_by(creator_id=emp_id).all()
    for group in owned_groups:
        group.creator_id = actor_emp_id
        actor_member = GroupMember.query.filter_by(
            group_id=group.id,
            emp_id=actor_emp_id,
        ).first()
        if actor_member:
            actor_member.status = "accepted"
        else:
            db.session.add(GroupMember(
                group_id=group.id,
                emp_id=actor_emp_id,
                status="accepted",
            ))

    transferred_workspaces = Workspace.query.filter_by(creator_id=emp_id).update(
        {"creator_id": actor_emp_id},
        synchronize_session=False,
    )
    transferred_records = QARecord.query.filter_by(creator_id=emp_id).update(
        {"creator_id": actor_emp_id},
        synchronize_session=False,
    )

    return {
        "groups": len(owned_groups),
        "workspaces": transferred_workspaces,
        "qa_records": transferred_records,
    }


def _user_search_to_dict(user):
    return {
        "emp_id": user.emp_id,
        "name": user.name,
        "phone": user.phone,
        "avatar": user.avatar,
        "role": user.role,
        "is_active": user.is_active,
    }

@users_bp.get("/me")
@active_user_required()
def me():
    emp_id = get_jwt_identity()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    return success(data=user_to_dict(user, include_settings=True))

@users_bp.put("/me")
@active_user_required()
def update_me():
    emp_id = get_jwt_identity()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)

    error = _apply_user_updates(user, request.get_json() or {})
    if error:
        return error

    db.session.commit()
    return success(message="user updated", data=user_to_dict(user, include_settings=True))


@users_bp.get("/search")
@active_user_required()
def search_users():
    keyword = _clean(request.args.get("keyword") or request.args.get("q") or "")
    if not keyword:
        return success(data=[])

    like_pattern = f"%{keyword}%"
    users = User.query.filter(
        User.is_active.is_(True),
        (User.emp_id.ilike(like_pattern))
        | (User.name.ilike(like_pattern))
        | (User.phone.ilike(like_pattern)),
    ).order_by(User.created_at.desc()).limit(50).all()

    return success(data=[_user_search_to_dict(u) for u in users])


@users_bp.get("/<emp_id>")
@active_user_required()
def get_user(emp_id):
    viewer = current_user()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    if not can_view_user(viewer, emp_id):
        return fail(message="permission denied", code=2001, http_status=403)
    return success(data=user_to_dict(user))

@users_bp.get("/")
@role_required("admin", "super_admin")
def get_all_users():
    keyword = _clean(request.args.get("keyword") or request.args.get("q") or "")
    role = _clean(request.args.get("role") or "")
    is_active = _clean(request.args.get("is_active") or "")

    query = User.query
    if keyword:
        like_pattern = f"%{keyword}%"
        query = query.filter((User.emp_id.ilike(like_pattern)) | (User.name.ilike(like_pattern)))
    if role:
        query = query.filter(User.role == role)
    if is_active:
        if is_active.lower() in {"1", "true", "yes"}:
            query = query.filter(User.is_active.is_(True))
        elif is_active.lower() in {"0", "false", "no"}:
            query = query.filter(User.is_active.is_(False))

    users = query.order_by(User.created_at.desc()).all()
    return success(data=[user_to_dict(u) for u in users])

@users_bp.post("/")
@role_required("admin", "super_admin")
def create_user():
    data = request.get_json() or {}
    emp_id = _clean(data.get("emp_id"))
    name = _clean(data.get("name")) or "New User"
    password = data.get("password")
    phone = _clean(data.get("phone"))
    avatar = _clean(data.get("avatar"))

    if not emp_id or not password:
        return fail(message="emp_id and password are required", code=2005, http_status=400)
    if len(str(password)) < 6:
        return fail(message="password must be at least 6 chars", code=2004, http_status=400)

    if User.query.filter_by(emp_id=emp_id).first():
        return fail(message="emp_id already exists", code=2006, http_status=409)

    user = User(
        emp_id=emp_id,
        name=name,
        phone=phone,
        avatar=avatar,
        role="user"
    )
    user.set_password(password)
    db.session.add(user)
    db.session.commit()

    return success(message="user created", data=user_to_dict(user), http_status=201)

@users_bp.put("/<emp_id>/role")
@role_required("super_admin")
def promote_user(emp_id):
    data = request.get_json() or {}
    new_role = data.get("role")
    
    if new_role not in ["admin", "user"]:
        return fail(message="invalid role", code=2007, http_status=400)

    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
        
    if user.role == "super_admin":
        return fail(message="cannot change super_admin role", code=2008, http_status=403)

    user.role = new_role
    user.auth_version = (user.auth_version or 0) + 1
    db.session.commit()
    return success(message="role updated", data=user_to_dict(user))


@users_bp.put("/<emp_id>/status")
@role_required("admin", "super_admin")
def update_user_status(emp_id):
    actor = current_user()
    data = request.get_json() or {}
    is_active = data.get("is_active")
    if not isinstance(is_active, bool):
        return fail(message="is_active must be boolean", code=2009, http_status=400)

    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    if user.role == "super_admin":
        return fail(message="cannot disable super_admin", code=2008, http_status=403)
    if actor and actor.emp_id == emp_id and not is_active:
        return fail(message="cannot disable yourself", code=2010, http_status=403)

    user.is_active = is_active
    user.auth_version = (user.auth_version or 0) + 1
    db.session.commit()
    return success(message="user status updated", data=user_to_dict(user))


@users_bp.put("/<emp_id>/password")
@role_required("admin", "super_admin")
def reset_user_password(emp_id):
    actor = current_user()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)

    error = _ensure_can_operate_target(actor, user)
    if error:
        return error

    data = request.get_json() or {}
    password = str(data.get("password") or "")
    if len(password) < 6:
        return fail(message="password must be at least 6 chars", code=2004, http_status=400)

    user.set_password(password)
    user.auth_version = (user.auth_version or 0) + 1
    db.session.commit()
    return success(message="password reset", data=user_to_dict(user))


@users_bp.delete("/<emp_id>")
@role_required("admin", "super_admin")
def delete_user(emp_id):
    actor = current_user()
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)

    error = _ensure_can_operate_target(actor, user)
    if error:
        return error

    transfer_counts = _transfer_user_owned_data(emp_id, actor.emp_id)
    GroupMember.query.filter_by(emp_id=emp_id).delete(synchronize_session=False)
    db.session.delete(user)
    db.session.commit()

    return success(message="user deleted", data={
        "deleted_emp_id": emp_id,
        "transferred": transfer_counts,
    })


@users_bp.put("/<emp_id>")
@role_required("admin", "super_admin")
def update_user(emp_id):
    user = User.query.filter_by(emp_id=emp_id).first()
    if not user:
        return fail(message="user not found", code=2002, http_status=404)
    if user.role == "super_admin":
        return fail(message="cannot edit super_admin here", code=2008, http_status=403)

    error = _apply_user_updates(user, request.get_json() or {})
    if error:
        return error

    db.session.commit()
    return success(message="user updated", data=user_to_dict(user))
