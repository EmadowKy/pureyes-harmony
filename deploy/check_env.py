"""Non-downloading environment checks for Pureyes backend deployment."""

from pathlib import Path
import argparse
import importlib
import os
import shutil
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
CONFIG_DIR = BACKEND_DIR / "configs"
MODEL_CONFIG = CONFIG_DIR / "model.yaml"


def print_status(ok: bool, label: str, detail: str = "") -> None:
    mark = "OK" if ok else "FAIL"
    suffix = f" - {detail}" if detail else ""
    print(f"[{mark}] {label}{suffix}")


def check_import(module_name: str, display_name: str | None = None) -> bool:
    display = display_name or module_name
    try:
        module = importlib.import_module(module_name)
        version = getattr(module, "__version__", "installed")
        print_status(True, display, str(version))
        return True
    except Exception as exc:
        print_status(False, display, str(exc))
        return False


def check_ffmpeg() -> bool:
    ok = True
    for exe in ("ffmpeg", "ffprobe"):
        path = shutil.which(exe)
        if not path:
            print_status(False, exe, "not found in PATH")
            ok = False
            continue
        try:
            result = subprocess.run(
                [exe, "-version"],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            first_line = (result.stdout or result.stderr).splitlines()[0]
            print_status(result.returncode == 0, exe, first_line)
            ok = ok and result.returncode == 0
        except Exception as exc:
            print_status(False, exe, str(exc))
            ok = False
    return ok


def check_cuda() -> bool:
    try:
        import torch

        print_status(True, "torch", torch.__version__)
        print_status(True, "torch.version.cuda", str(torch.version.cuda))
        cuda_ok = torch.cuda.is_available()
        detail = torch.cuda.get_device_name(0) if cuda_ok else "CUDA unavailable"
        print_status(cuda_ok, "torch.cuda.is_available()", detail)
        return cuda_ok
    except Exception as exc:
        print_status(False, "torch", str(exc))
        return False


def check_qwen_imports() -> bool:
    try:
        from transformers import AutoProcessor, Qwen3VLForConditionalGeneration
        from qwen_vl_utils import process_vision_info

        _ = AutoProcessor, Qwen3VLForConditionalGeneration, process_vision_info
        print_status(True, "Qwen3-VL imports", "transformers and qwen-vl-utils are usable")
        return True
    except Exception as exc:
        print_status(False, "Qwen3-VL imports", str(exc))
        return False


def resolve_model_path(raw_path: str) -> Path | None:
    if not raw_path or "://" in raw_path:
        return None
    if "/" in raw_path and not raw_path.startswith((".", "/")):
        # Looks like a Hugging Face repo id such as Qwen/Qwen3-VL-2B-Instruct.
        return None
    path = Path(raw_path)
    if not path.is_absolute():
        path = CONFIG_DIR / path
    return path.resolve()


def check_model_config(require_local_model: bool) -> bool:
    if not MODEL_CONFIG.exists():
        print_status(False, "model.yaml", f"missing: {MODEL_CONFIG}")
        return False

    try:
        import yaml

        with MODEL_CONFIG.open("r", encoding="utf-8") as handle:
            config = yaml.safe_load(handle) or {}
    except Exception as exc:
        print_status(False, "model.yaml", str(exc))
        return False

    raw_model_path = str((config.get("models") or {}).get("main_model_path", "")).strip()
    print_status(bool(raw_model_path), "models.main_model_path", raw_model_path or "empty")

    resolved = resolve_model_path(raw_model_path)
    if resolved is None:
        message = "remote repo id or URL; this may trigger Hugging Face download/cache"
        print_status(not require_local_model, "local model path", message)
        return not require_local_model

    exists = resolved.exists()
    print_status(exists, "local model directory", str(resolved))
    if exists:
        config_json = resolved / "config.json"
        print_status(config_json.exists(), "model config.json", str(config_json))
        return config_json.exists()
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--require-local-model",
        action="store_true",
        help="fail if backend/configs/model.yaml points to a Hugging Face repo id or a missing local directory",
    )
    args = parser.parse_args()

    print(f"Repo root: {REPO_ROOT}")
    print(f"Python: {sys.version.split()[0]}")
    print(f"HF_HUB_OFFLINE={os.getenv('HF_HUB_OFFLINE', '')}")
    print(f"TRANSFORMERS_OFFLINE={os.getenv('TRANSFORMERS_OFFLINE', '')}")

    checks = [
        check_import("flask", "Flask"),
        check_import("numpy", "NumPy"),
        check_import("cv2", "OpenCV"),
        check_import("PIL", "Pillow"),
        check_import("yaml", "PyYAML"),
        check_import("transformers", "Transformers"),
        check_import("accelerate", "Accelerate"),
        check_import("qwen_vl_utils", "qwen-vl-utils"),
        check_cuda(),
        check_qwen_imports(),
        check_ffmpeg(),
        check_model_config(args.require_local_model),
    ]

    if all(checks):
        print("Environment check passed.")
        return 0
    print("Environment check failed. Fix the FAIL items above before running model inference.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
