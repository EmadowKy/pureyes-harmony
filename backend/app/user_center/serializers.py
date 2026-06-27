from app.models.group import GroupMember
from app.models.user import User


def iso_z(value):
    return value.isoformat() + "Z" if value else None


def user_to_dict(user, include_private=True):
    data = {
        "emp_id": user.emp_id,
        "name": user.name,
        "phone": user.phone if include_private else None,
        "avatar": user.avatar,
        "role": user.role,
        "is_active": user.is_active,
        "created_at": iso_z(user.created_at),
        "updated_at": iso_z(user.updated_at),
    }
    return data


def group_to_dict(group, current_emp_id=None, include_counts=False):
    data = group.to_dict()
    data["is_creator"] = current_emp_id == group.creator_id if current_emp_id else False

    if include_counts:
        data["member_count"] = GroupMember.query.filter_by(
            group_id=group.id,
            status="accepted",
        ).count()
        data["pending_count"] = GroupMember.query.filter_by(
            group_id=group.id,
            status="pending",
        ).count()

    return data


def membership_to_dict(member, user=None, group=None):
    payload = member.to_dict()
    if user is None:
        user = User.query.filter_by(emp_id=member.emp_id).first()
    if user:
        payload["user"] = user_to_dict(user)
        payload.update({
            "name": user.name,
            "phone": user.phone,
            "avatar": user.avatar,
            "role": user.role,
            "is_active": user.is_active,
        })
    if group:
        payload["group"] = group_to_dict(group)
        payload["group_name"] = group.name
        payload["creator_id"] = group.creator_id
    return payload
