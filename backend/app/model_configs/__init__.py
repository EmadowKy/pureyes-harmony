from flask import Blueprint

model_configs_bp = Blueprint("model_configs", __name__)

from . import routes  # noqa: E402,F401
