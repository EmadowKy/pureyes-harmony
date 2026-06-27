# pureyes-harmony 部署运行指南

本项目分为两部分：

- `backend/`: Python Flask 后端，负责账号、小组、监控、视频切片和 Qwen3-VL 多视频问答推理。
- `frontend/`: HarmonyOS / ArkTS 前端工程，负责手机端界面和调用后端接口。

结论先说：

- 可以在 AutoDL、恒源云、阿里云 GPU、学校 GPU 服务器等远程 Linux 服务器上调试并跑通后端。
- 后端不需要安装 DevEco Studio、HarmonyOS SDK、华为编译器、CANN、Ascend、MindSpore 或 `torch_npu`。当前代码使用 Hugging Face Transformers + PyTorch CUDA，推荐 NVIDIA GPU。
- 前端是 HarmonyOS 工程，需要在本机安装 DevEco Studio 和对应 HarmonyOS SDK 后编译、签名、安装到 HarmonyOS 设备或模拟器。
- 服务器上需要 FFmpeg，因为监控流转码、视频切片和播放兼容性检查会调用 `ffmpeg` / `ffprobe`。

## 1. 推荐硬件和系统

后端推荐环境：

- 系统：Ubuntu 20.04 / 22.04。
- Python：3.10 或 3.11，推荐 3.10。
- GPU：NVIDIA GPU，建议显存 16 GB 起步，24 GB 以上更稳。
- CUDA wheel：推荐 PyTorch CUDA 12.6 wheel。如果服务器驱动较老，可改用 CUDA 11.8 wheel。
- 磁盘：至少预留 20 GB，模型和视频文件会占空间。

AutoDL 选机建议：

- 镜像优先选 `Miniconda + CUDA 12.x` 或 `PyTorch + CUDA 12.x`。
- 如果可选，优先 4090 / A5000 / A10 / L20 等 24 GB 左右显存机器。
- 建议把模型目录直接放在仓库的 `models/` 下，便于迁移和对接。

## 2. 克隆代码

如果要部署本文档对应的对接版本，直接克隆 `deploy-relative-paths` 分支：

```bash
git clone -b deploy-relative-paths --single-branch https://github.com/EmadowKy/pureyes-harmony.git
cd pureyes-harmony
```

如果该分支后续已经合并到 `main`，再使用普通克隆即可：

```bash
git clone https://github.com/EmadowKy/pureyes-harmony.git
cd pureyes-harmony
```

如果网络较慢，可以先在服务器上手动下载模型文件；项目默认不会再强制设置 Hugging Face 镜像地址。

## 3. 创建 Conda 环境

```bash
conda create -n pureyes python=3.10 -y
conda activate pureyes

python -m pip install -U pip setuptools wheel
```

安装 FFmpeg：

```bash
conda install -c conda-forge ffmpeg git git-lfs -y
git lfs install
```

验证 FFmpeg：

```bash
ffmpeg -version
ffprobe -version
```

## 4. 安装 GPU PyTorch

推荐 CUDA 12.6 wheel：

```bash
pip install torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu126
```

如果服务器 NVIDIA 驱动较老，CUDA 12.6 wheel 不可用，可以改用 CUDA 11.8 wheel：

```bash
pip install torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu118
```

检查 GPU：

```bash
python - <<'PY'
import torch
print("torch:", torch.__version__)
print("torch cuda:", torch.version.cuda)
print("cuda available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu:", torch.cuda.get_device_name(0))
PY
```

如果 `cuda available` 是 `False`，先不要继续跑模型，优先检查 AutoDL 镜像、NVIDIA 驱动和 PyTorch wheel 是否匹配。

## 5. 安装后端依赖

Torch 单独安装，其他依赖用推荐文件：

```bash
pip install -r backend/requirements-gpu.txt
```

重要版本说明：

- 当前代码导入 `Qwen3VLForConditionalGeneration`，旧版 `transformers>=4.35.0` 不够。
- 推荐先使用 `transformers==4.57.6`。
- 如果仍然报 `cannot import name 'Qwen3VLForConditionalGeneration'`，按 Qwen3-VL 官方模型卡建议改为源码安装：

```bash
pip uninstall -y transformers
pip install git+https://github.com/huggingface/transformers
```

验证关键依赖：

```bash
python - <<'PY'
import torch
import transformers
from transformers import Qwen3VLForConditionalGeneration, AutoProcessor
from qwen_vl_utils import process_vision_info
print("torch:", torch.__version__)
print("transformers:", transformers.__version__)
print("Qwen3-VL import ok")
PY
```

## 6. 配置本地模型

默认模型在 `backend/configs/model.yaml`：

```yaml
models:
  main_model_path: "models/Qwen3-VL-2B-Instruct"
```

相对路径会按仓库根目录解析。推荐目录结构：

```text
pureyes-harmony/
  backend/
  frontend/
  models/
    Qwen3-VL-2B-Instruct/
      config.json
      model.safetensors.index.json
      tokenizer.json
      ...
```

你可以直接从 Hugging Face 下载到服务器的 `models/` 目录：

```bash
mkdir -p models
cd models
git clone https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct
cd ..
```

如果模型放在其他位置，只需要把 `backend/configs/model.yaml` 改成对应相对路径或绝对路径：

```yaml
models:
  main_model_path: "/data/models/Qwen3-VL-2B-Instruct"
```

代码会在本地模型目录不存在时直接报错，避免误触发在线下载。

## 7. 启动后端

开发调试：

```bash
cd backend
python run.py
```

后端默认监听：

```text
0.0.0.0:8000
```

另开一个终端验证：

```bash
curl http://127.0.0.1:8000/api/health
```

预期返回类似：

```json
{"code":0,"data":{"service":"backend"},"message":"ok"}
```

首次启动会自动创建超级管理员：

```text
emp_id: admin
password: admin
```

登录验证：

```bash
curl -X POST http://127.0.0.1:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"emp_id":"admin","password":"admin"}'
```

生产或长时间调试建议用单 worker，避免多个进程重复加载模型：

```bash
pip install gunicorn==23.0.0
cd backend
gunicorn -w 1 -b 0.0.0.0:8000 run:app --timeout 600
```

## 8. AutoDL 端口访问

后端已经绑定 `0.0.0.0:8000`。在 AutoDL 上需要把 8000 端口暴露出去，常见方式：

- 在 AutoDL 控制台添加自定义服务端口，把容器内 `8000` 映射为公网访问地址。
- 或使用 SSH 隧道只在本机调试：

```bash
ssh -L 8000:127.0.0.1:8000 root@你的服务器地址
```

手机端 HarmonyOS 应用必须能访问后端地址。如果只开本机 SSH 隧道，手机通常访问不到；真机调试更推荐使用 AutoDL 公网端口、内网穿透或同一局域网可访问的地址。

## 9. 模型推理最小测试

仓库没有自带 `backend/example/1.mp4` 和 `backend/example/2.mp4`。可以先用 FFmpeg 生成两个测试视频：

```bash
cd backend
mkdir -p example
ffmpeg -y -f lavfi -i testsrc=duration=5:size=640x360:rate=15 -pix_fmt yuv420p example/1.mp4
ffmpeg -y -f lavfi -i smptebars=duration=5:size=640x360:rate=15 -pix_fmt yuv420p example/2.mp4
```

然后运行模型测试：

```bash
python -m app.qa.run_model
```

这一步会从 `models/Qwen3-VL-2B-Instruct` 加载 Qwen3-VL，耗时较长，显存不够时会报 CUDA OOM。

如果只是验证后端服务，`/api/health` 和登录接口通过即可；只有提交问答任务时才会真正加载模型。

## 10. 前端 HarmonyOS 配置

前端工程目录：

```text
frontend/
```

需要安装：

- DevEco Studio。
- HarmonyOS SDK，版本需要能识别项目里的 `modelVersion` / `targetSdkVersion` `26.0.0`。
- 真机调试需要开启开发者模式并配置签名；模拟器按 DevEco Studio 提示配置即可。

修改后端地址：

文件：

```text
frontend/entry/src/main/ets/utils/http.ets
```

把默认地址：

```ts
export const BASE_HOST = 'http://10.32.212.191:8000';
const BASE_URL = 'http://10.32.212.191:8000/api';
```

改成你的后端地址，例如：

```ts
export const BASE_HOST = 'http://你的AutoDL公网地址:公网端口';
const BASE_URL = 'http://你的AutoDL公网地址:公网端口/api';
```

然后在 DevEco Studio 中：

1. `Open` 打开 `frontend/` 目录。
2. 等待 Hvigor / ohpm 同步依赖。
3. 连接 HarmonyOS 真机或启动模拟器。
4. 选择 `entry` 模块运行。
5. 使用 `admin / admin` 登录。

项目已声明网络权限：

```json5
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET"
  }
]
```

## 11. 应用内跑通流程

后端启动后，前端操作大致如下：

1. 登录：`admin / admin`。
2. 创建小组。
3. 在小组内创建工作区。
4. 添加监控源。如果是 RTSP/RTMP，后端会用 FFmpeg 转 HLS；如果是普通 HTTP 视频地址，前端直接播放。
5. 在工作区新建 AI 问答。
6. 后端切片、加载 Qwen3-VL、抽帧并生成答案。

注意：当前前端提交问答时默认使用 `monitor_id = 1` 和当前时间段。为了稳定测试，建议先添加一个可用监控源，或先用第 9 节的 `backend/example/1.mp4`、`backend/example/2.mp4` 做后端模型链路测试。

## 12. 常见问题

### 12.1 `cannot import name 'Qwen3VLForConditionalGeneration'`

原因：Transformers 版本太旧。

处理：

```bash
pip install -U transformers==4.57.6
```

如果仍失败：

```bash
pip uninstall -y transformers
pip install git+https://github.com/huggingface/transformers
```

### 12.2 `ffmpeg not found` 或 `ffprobe failed`

安装 FFmpeg：

```bash
conda install -c conda-forge ffmpeg -y
```

验证：

```bash
which ffmpeg
which ffprobe
```

### 12.3 CUDA OOM

优先改小帧数。文件：

```text
backend/configs/model.yaml
```

可先改为：

```yaml
parameters:
  size: 360
  num_frames_iter: 4
  num_frames_noiter: 8
  skip_iteration: true
```

`skip_iteration: true` 会减少多轮探索，适合先跑通。

### 12.4 本地模型路径不存在

如果报 `Local model path does not exist`，说明 `backend/configs/model.yaml` 指向的模型目录不存在。

默认路径是：

```text
models/Qwen3-VL-2B-Instruct
```

请先把 Hugging Face 模型完整下载到该目录，或把 `main_model_path` 改成实际模型目录。

### 12.5 前端 Network Error

逐项检查：

- `backend` 是否正在运行。
- AutoDL 是否映射了 8000 端口。
- `frontend/entry/src/main/ets/utils/http.ets` 是否改成公网可访问地址。
- 手机或模拟器是否能打开 `http://你的地址/api/health`。
- 后端如果只通过 SSH 本机隧道暴露，真机通常访问不到。

### 12.6 `/api/qa/*` 接口访问不到

当前 `create_app()` 没有注册 `app.qa.routes` 的 `qa_bp`。前端实际使用的是：

```text
/api/workspaces/<workspace_id>/qa
/api/workspaces/qa/<task_id>/status
```

按前端路径测试即可。如果后续要直接使用 `/api/qa/*`，需要在 `backend/app/__init__.py` 里注册对应蓝图。

## 13. 参考资料

- 项目仓库：https://github.com/EmadowKy/pureyes-harmony
- Qwen3-VL-2B-Instruct 模型卡：https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct
- qwen-vl-utils：https://pypi.org/project/qwen-vl-utils/
- PyTorch 安装页：https://pytorch.org/get-started/locally/
- DevEco Studio：https://developer.huawei.com/consumer/en/deveco-studio/
