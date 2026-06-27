# pureyes-harmony 部署跑通说明

## 模块文档

- 用户与小组模块：[docs/user-group-module.md](docs/user-group-module.md)

## 更新记录

- 2026-06-27 18:16:14 +08:00：补齐用户与小组模块后端接口、前端“我的/小组”页面、模块说明文档，并记录远程后端大模型检查结果。
- 2026-06-27 18:22:19 +08:00：远程后端编译和用户/小组接口测试通过；本机 DevEco/Hvigor `assembleApp` 构建通过。

本文面向当前仓库 `EmadowKy/pureyes-harmony` 的 `main` 分支，检查时间为 2026-06-27。本仓库当前没有原始 README；本说明只新增部署文件，不修改已有源码。

## 结论

- 可以在 AutoDL、学校 GPU 服务器、阿里云 GPU 等远程 Linux/NVIDIA CUDA 环境调试并跑通后端。
- 后端不需要安装华为 DevEco Studio、HarmonyOS SDK、华为编译器、CANN、MindSpore、`torch_npu`。当前后端是 Flask + PyTorch CUDA + Hugging Face Transformers。
- 前端是 HarmonyOS / ArkTS 工程，需要在本机 DevEco Studio 中编译、签名、安装到 HarmonyOS 真机或模拟器。仓库前端 `modelVersion`、`targetSdkVersion`、`compatibleSdkVersion` 都是 `26.0.0`，你下载的华为开发者官网 26 beta 工具链方向是匹配的。
- 如果只想先把后端 API 和模型推理跑通，AutoDL 上只配 Python/CUDA/FFmpeg/模型即可，不需要华为相关软件。

## 新增文件

- `README.md`：当前部署说明。
- `backend/requirements-autodl.txt`：后端锁版本依赖，不包含 `torch` / `torchvision`，避免覆盖 GPU wheel。
- `deploy/check_env.py`：非下载式环境检查脚本。
- `deploy/run_backend_autodl.py`：不改原 `backend/run.py` 的启动脚本，支持 `HOST`/`PORT` 环境变量，并让 `model.yaml` 里的 `../../output/...` 解析到仓库内 `output/...`。

## 推荐服务器环境

- 系统：Ubuntu 22.04 或 20.04。
- Python：3.10。
- GPU：NVIDIA GPU，16 GB 显存起步，24 GB 及以上更稳。
- CUDA：优先用 PyTorch pip CUDA wheel，不要求服务器安装完整 CUDA Toolkit 或 `nvcc`。
- 磁盘：至少预留 20 GB；模型、上传视频、抽帧和转码文件会占空间。
- 系统工具：必须有 `ffmpeg` 和 `ffprobe`，代码中监控录制、视频切片、视频兼容性检查都会调用。

## 1. 克隆仓库

```bash
cd /root/autodl-tmp
git clone https://github.com/EmadowKy/pureyes-harmony.git
cd pureyes-harmony
```

如果是你本地 Windows 工作区，本文对应的 clone 目录是：

```text
D:\VSCode_MyCode\C4_AI\pureyes-harmony
```

## 2. 创建 Conda 环境

```bash
conda create -n pureyes python=3.10 -y
conda activate pureyes

python -m pip install -U pip setuptools wheel
conda install -c conda-forge ffmpeg git git-lfs -y
git lfs install
```

检查系统工具：

```bash
ffmpeg -version
ffprobe -version
nvidia-smi
```

## 3. 安装 GPU PyTorch

推荐先用 CUDA 12.6 wheel：

```bash
pip install torch==2.7.1 torchvision==0.22.1 --index-url https://download.pytorch.org/whl/cu126
```

如果服务器 NVIDIA 驱动较旧，CUDA 12.6 wheel 无法使用，再换 CUDA 11.8 wheel：

```bash
pip install torch==2.7.1 torchvision==0.22.1 --index-url https://download.pytorch.org/whl/cu118
```

验证：

```bash
python -c "import torch; print(torch.__version__); print(torch.version.cuda); print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'no cuda')"
```

`torch.cuda.is_available()` 必须是 `True`，否则先不要继续跑模型。

## 4. 安装后端依赖

不要优先使用原 `backend/requirements.txt`，它的 AI 依赖范围太宽，会安装当前 pip 源上的最新版本，复现性较差。建议用新增的锁版本文件：

```bash
pip install -r backend/requirements-autodl.txt
```

检查关键导入：

```bash
python deploy/check_env.py
```

如果这里报 `cannot import name 'Qwen3VLForConditionalGeneration'`，说明当前 `transformers` wheel 不含项目需要的 Qwen3-VL 类。先尝试：

```bash
pip uninstall -y transformers
pip install git+https://github.com/huggingface/transformers
python deploy/check_env.py
```

## 5. 准备本地模型，避免缓存下载

当前 `backend/configs/model.yaml` 默认是：

```yaml
models:
  main_model_path: "Qwen/Qwen3-VL-2B-Instruct"
```

这会让 Transformers 按 Hugging Face 仓库 ID 加载模型，可能触发联网下载和缓存。为了符合“不希望下载缓存，模型手动放服务器”的要求，建议把模型直接放到仓库内：

```text
pureyes-harmony/
  models/
    Qwen3-VL-2B-Instruct/
      config.json
      model.safetensors.index.json
      tokenizer.json
      ...
```

然后把 `backend/configs/model.yaml` 的模型路径改成本地相对路径：

```yaml
models:
  main_model_path: "../../models/Qwen3-VL-2B-Instruct"
```

这个相对路径配合 `deploy/run_backend_autodl.py` 使用：启动脚本会把进程工作目录切到 `backend/configs`，所以 `../../models/...` 会解析到仓库根目录下的 `models/...`。

为了防止误触发在线下载，模型目录准备好以后可以开启离线环境变量：

```bash
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
python deploy/check_env.py --require-local-model
```

注意：代码里 `backend/app/mva/utils.py` 当前写了 `HF_ENDPOINT=https://hf-mirror.com`。只要 `main_model_path` 是本地目录，就不会依赖这个镜像；如果仍然写 `Qwen/Qwen3-VL-2B-Instruct`，就可能走在线下载。

## 6. 启动后端

推荐用新增启动脚本：

```bash
export PORT=6006
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
python deploy/run_backend_autodl.py
```

默认监听：

```text
0.0.0.0:6006
```

如果不设置 `PORT`，默认是 `8000`。原始启动方式仍然可用：

```bash
cd backend
python run.py
```

但原 `backend/run.py` 端口写死为 `8000`，且 `model.yaml` 里的输出目录会按当前工作目录解析；远程部署更建议使用 `deploy/run_backend_autodl.py`。

后台运行示例：

```bash
mkdir -p logs
nohup python deploy/run_backend_autodl.py > logs/backend.log 2>&1 &
tail -f logs/backend.log
```

## 7. 后端健康检查

另开一个终端：

```bash
curl http://127.0.0.1:6006/api/health
```

预期类似：

```json
{"code":0,"data":{"service":"backend"},"message":"ok"}
```

首次启动会自动创建管理员：

```text
emp_id: admin
password: admin
```

登录检查：

```bash
curl -X POST http://127.0.0.1:6006/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"emp_id":"admin","password":"admin"}'
```

健康检查和登录不会加载大模型。第一次调用 QA 推理接口时才会加载 Qwen3-VL。

## 8. AutoDL 端口访问

AutoDL 上启动后端后，需要在控制台暴露容器端口，例如 `6006`。手机或 DevEco 模拟器必须访问 AutoDL 控制台给出的公网地址，而不是服务器内部的 `127.0.0.1`。

如果只做本机浏览器调试，也可以用 SSH 隧道：

```bash
ssh -CNg -L 6006:127.0.0.1:6006 root@你的服务器地址 -p 端口号
```

然后本机浏览器访问：

```text
http://localhost:6006/api/health
```

前端真机/模拟器通常不要填 `localhost`，因为那通常指设备或模拟器自己，不是 AutoDL 服务器。

## 9. 前端 DevEco 配置

前端目录：

```text
frontend/
```

建议流程：

1. 在 Windows 本机安装 DevEco Studio / HarmonyOS SDK 26 beta。
2. 用 DevEco Studio 打开 `frontend` 目录。
3. 等待 DevEco 同步 ohpm/hvigor 工程。
4. 在 `frontend/entry/src/main/ets/utils/http.ets` 中，把后端地址改为 AutoDL 暴露出来的公网地址。

当前代码位置：

```ts
export const BASE_HOST = 'http://10.32.212.191:8000';
const BASE_URL = 'http://10.32.212.191:8000/api';
```

示例：

```ts
export const BASE_HOST = 'http://你的AutoDL公网地址:6006';
const BASE_URL = 'http://你的AutoDL公网地址:6006/api';
```

然后在 DevEco 中选择手机或模拟器运行。前端已有网络权限：

```json5
"name": "ohos.permission.INTERNET"
```

## 10. 常见问题

`torch.cuda.is_available()` 是 `False`：
先检查 `nvidia-smi` 是否正常，再确认安装的是 PyTorch CUDA wheel，不是默认 CPU wheel。

`Qwen3VLForConditionalGeneration` 导入失败：
优先使用 `transformers==4.57.6`；如果仍失败，安装 Hugging Face Transformers 最新源码版。

服务启动后显存没有变化：
正常。健康检查和登录不加载模型，第一次 QA 推理才加载。

模型仍然联网下载：
确认 `backend/configs/model.yaml` 的 `main_model_path` 不是 `Qwen/Qwen3-VL-2B-Instruct`，而是本地模型目录；再设置 `HF_HUB_OFFLINE=1` 和 `TRANSFORMERS_OFFLINE=1`。

前端访问失败：
优先确认 Windows 浏览器能打开后端 `/api/health`。如果浏览器能打开但前端不能，检查 `http.ets` 中是否仍使用旧 IP、`localhost` 或未暴露的内网地址。

## 参考来源

- PyTorch 官方安装页：https://pytorch.org/get-started/locally/
- PyTorch 官方历史版本页：https://pytorch.org/get-started/previous-versions/
- Qwen3-VL-2B-Instruct 模型页：https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct
- 华为开发者下载页：https://developer.huawei.com/consumer/cn/download/
