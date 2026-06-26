from flask import Blueprint, send_file, abort, request
import os
from .views import upload_video, delete_video, rename_video, tick_video, get_video_list, get_single_video

video_bp = Blueprint('video_manage', __name__, url_prefix='/api/video-manage')

current_file = os.path.abspath(__file__)
backend_root = os.path.dirname(os.path.dirname(os.path.dirname(current_file)))


@video_bp.route('/upload', methods=['POST'])
def api_upload_video():
    return upload_video()


@video_bp.route('/delete', methods=['POST'])
def api_delete_video():
    return delete_video()


@video_bp.route('/rename', methods=['POST'])
def api_rename_video():
    return rename_video()


@video_bp.route('/tick', methods=['POST'])
def api_tick_video():
    return tick_video()


@video_bp.route('/list', methods=['GET'])
def api_get_video_list():
    return get_video_list()


@video_bp.route('/info', methods=['GET'])
def api_get_single_video():
    return get_single_video()