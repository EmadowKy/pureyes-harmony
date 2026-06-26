from flask import Blueprint

workspaces_bp = Blueprint("workspaces", __name__)

from . import routes
