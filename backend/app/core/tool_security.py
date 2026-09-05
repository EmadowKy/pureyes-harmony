import os


def resolve_selected_video(video_items, tool_params):
    """Resolve an agent tool request strictly to one of the user-selected videos."""
    requested_id = str(tool_params.get("video_id") or "").strip()
    requested_path = str(tool_params.get("video_path") or "").strip()
    id_match = None
    path_match = None

    if requested_id:
        id_match = next(
            (item for item in video_items if str(item.get("video_id")) == requested_id),
            None,
        )
    if requested_path:
        requested_abs = os.path.normcase(os.path.abspath(requested_path))
        path_match = next(
            (
                item for item in video_items
                if os.path.normcase(os.path.abspath(item.get("video_path") or "")) == requested_abs
            ),
            None,
        )

    if requested_id and not id_match:
        return None
    if requested_path and not path_match:
        return None
    if id_match and path_match and id_match is not path_match:
        return None
    return id_match or path_match
