from flask import Blueprint

monitors_bp = Blueprint("monitors", __name__)

from . import routes
