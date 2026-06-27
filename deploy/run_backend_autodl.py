"""Start the Pureyes backend with deployment-friendly relative paths.

The existing backend/configs/model.yaml uses paths like ../../output/output.
Those paths resolve to repo/output/... when the process working directory is
backend/configs, so this launcher sets that cwd before importing the app.
"""

from pathlib import Path
import os
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
CONFIG_WORKDIR = BACKEND_DIR / "configs"

os.chdir(CONFIG_WORKDIR)
sys.path.insert(0, str(BACKEND_DIR))

from run import app  # noqa: E402


def _env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    debug = _env_bool("FLASK_DEBUG", False)

    print(f"Pureyes backend cwd: {Path.cwd()}")
    print(f"Pureyes backend repo: {REPO_ROOT}")
    print(f"Pureyes backend listen: http://{host}:{port}")
    app.run(debug=debug, host=host, port=port)
