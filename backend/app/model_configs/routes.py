from flask import request
from flask_jwt_extended import get_jwt_identity

from app.core.db import db
from app.core.network_security import validate_llm_base_url
from app.core.response import fail, success
from app.models.group import Group, GroupMember
from app.models.llm_config import LLMConfig
from app.user_center.permissions import active_user_required
from . import model_configs_bp


def available_config(config, emp_id, group_id):
    if config.scope == "personal":
        return config.owner_id == emp_id
    return (config.scope == "group" and config.group_id == group_id
            and GroupMember.query.filter_by(group_id=group_id, emp_id=emp_id,
                                            status="accepted").first() is not None)


def _editable(config, emp_id):
    if config.scope == "personal":
        return config.owner_id == emp_id
    group = db.session.get(Group, config.group_id)
    return bool(group and group.creator_id == emp_id)


def _fields(data, config=None):
    name = data.get("name", config.name if config else "")
    model = data.get("model", config.model if config else "")
    url = data.get("base_url", config.base_url if config else "")
    key = data.get("api_key") or (config.api_key if config else "")
    if not all(isinstance(value, str) for value in (name, model, key, url)):
        raise ValueError("配置名称、模型、地址和 API Key 必须是文本")
    name, model, key = name.strip(), model.strip(), key.strip()
    if not name or len(name) > 80 or not model or len(model) > 128 or not key or len(key) > 2048:
        raise ValueError("请填写有效的名称、模型和 API Key")
    url = validate_llm_base_url(url)
    if not url or len(url) > 255:
        raise ValueError("请填写有效的 BASE URL")
    return name, model, url, key


@model_configs_bp.get("")
@active_user_required()
def list_configs():
    emp_id = get_jwt_identity()
    if "group_id" in request.args and request.args.get("group_id", type=int) is None:
        return fail(message="invalid group_id", code=6103, http_status=400)
    group_id = request.args.get("group_id", type=int)
    groups = (Group.query.join(GroupMember, GroupMember.group_id == Group.id)
              .filter(GroupMember.emp_id == emp_id, GroupMember.status == "accepted"))
    if group_id is not None:
        group = groups.filter(Group.id == group_id).first()
        if not group:
            return fail(message="not a group member", code=3003, http_status=403)
        visible_groups = {group.id: group}
    else:
        visible_groups = {group.id: group for group in groups.all()}
    personal = LLMConfig.query.filter_by(scope="personal", owner_id=emp_id).all()
    shared = (LLMConfig.query.filter_by(scope="group")
              .filter(LLMConfig.group_id.in_(visible_groups)).all() if visible_groups else [])
    return success(data=[config.public(emp_id, visible_groups.get(config.group_id).creator_id
                      if config.scope == "group" else None)
                         for config in personal + shared])


@model_configs_bp.post("")
@active_user_required()
def create_config():
    emp_id = get_jwt_identity()
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        return fail(message="invalid config data", code=6103, http_status=400)
    scope = data.get("scope")
    if scope not in ("personal", "group"):
        return fail(message="invalid scope", code=6101, http_status=400)
    group = None
    if scope == "group":
        group_id = data.get("group_id")
        group = db.session.get(Group, group_id) if type(group_id) is int else None
        if not group or group.creator_id != emp_id:
            return fail(message="only the group leader can manage shared configs", code=6102, http_status=403)
    try:
        name, model, url, key = _fields(data)
    except ValueError as exc:
        return fail(message=str(exc), code=6103, http_status=400)
    config = LLMConfig(name=name, scope=scope, owner_id=emp_id if scope == "personal" else None,
                       group_id=group.id if group else None, api_key=key, base_url=url, model=model)
    db.session.add(config)
    db.session.commit()
    return success(data=config.public(emp_id, emp_id), http_status=201)


@model_configs_bp.put("/<int:config_id>")
@active_user_required()
def update_config(config_id):
    config = db.session.get(LLMConfig, config_id)
    if not config:
        return fail(message="config not found", code=6104, http_status=404)
    emp_id = get_jwt_identity()
    if not _editable(config, emp_id):
        return fail(message="permission denied", code=6102, http_status=403)
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        return fail(message="invalid config data", code=6103, http_status=400)
    if "scope" in data or "group_id" in data:
        return fail(message="scope cannot be changed", code=6103, http_status=400)
    try:
        config.name, config.model, config.base_url, config.api_key = _fields(data, config)
    except ValueError as exc:
        return fail(message=str(exc), code=6103, http_status=400)
    db.session.commit()
    return success(data=config.public(emp_id, emp_id))


@model_configs_bp.delete("/<int:config_id>")
@active_user_required()
def delete_config(config_id):
    config = db.session.get(LLMConfig, config_id)
    if not config:
        return fail(message="config not found", code=6104, http_status=404)
    if not _editable(config, get_jwt_identity()):
        return fail(message="permission denied", code=6102, http_status=403)
    db.session.delete(config)
    db.session.commit()
    return success(message="config deleted")
