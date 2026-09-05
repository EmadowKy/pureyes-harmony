# 01-服务器硬件配置与环境依赖

> [!NOTE]
> **提示**：普通客户端用户默认连接官方服务器，无需搭建后端环境。本文档专为运维人员或有私有化独立部署需求的机构团队提供参考。

---

## 1. 服务器推荐硬件配置

Pureyes 系统的大模型推理全面采用 API 接入方式（支持在【我的】页面或配置文件中灵活指定 API 密钥、Base URL 与模型名称）。服务器端主要负责轻量化目标检测、目标追踪、特征提取与 Web API 服务：

| 硬件资源 | 最低配置 | 推荐配置 (生产环境) |
| :--- | :--- | :--- |
| **操作系统** | Ubuntu 20.04 LTS | Ubuntu 22.04 LTS |
| **CPU** | 4 核 Intel/AMD x86_64 | 8 核或以上 高频 CPU |
| **系统内存 (RAM)** | 8 GB | 16 GB 及以上 |
| **独立显卡 (GPU)** | NVIDIA GPU, 8 GB 显存 (如 RTX 3060 / 4060) | NVIDIA GPU, 16 GB 显存 (如 RTX 4060 Ti 16G / T4) |
| **CUDA 环境** | CUDA 11.8 或 CUDA 12.6 | PyTorch 内建 CUDA 12.6 Wheel |
| **磁盘空间** | 预留 20 GB 剩余空间 (NVMe SSD) | 预留 100 GB SSD (用于视频与切片存储) |
| **系统工具依赖** | `ffmpeg`, `ffprobe`, `git` | `ffmpeg`, `ffprobe`, `git` |

---

## 2. 完整 Python 依赖包清单 (`backend/requirements.txt`)

后端基于 **Python 3.10** 环境建立，全量依赖清单存放在 `backend/requirements.txt` 文件中：

```text
# Web 框架与数据库
Flask==2.3.3
Flask-CORS==4.0.0
Flask-SQLAlchemy==3.1.1
Flask-JWT-Extended==4.6.0
gunicorn==23.0.0

# 身份认证与安全
PyJWT==2.8.0
Werkzeug>=3.0.0
cryptography>=42.0.0

# 视频与图像处理
opencv-python==4.8.1.78
numpy<2.0.0
Pillow>=10.0.0

# 系统配置与工具
PyYAML>=6.0.1
requests>=2.31.0
python-dotenv==1.0.1
filelock>=3.13.0

# AI 视觉分析引擎核心依赖
ultralytics>=8.2.0        # YOLOv8 目标检测网络
supervision>=0.21.0       # ByteTrack 目标追踪工具
onnxruntime>=1.17.0       # ONNX 引擎 (用于加载 OSNet 行人重识别特征提取)
lancedb>=0.6.0            # 嵌入式时空特征向量数据库
pydantic>=2.0.0           # 数据校验与结构化解析
transformers>=4.40.0      # 多模态视觉模型 Tokenizer / 特征提取
```

---

## 3. 轻量化 AI 模型权重与配置文件清单

后端运行仅需以下轻量化算法模型权重及配置文件（大模型统一通过 API 接入，无需下载昂贵的本地大模型文件）：

| 模型名称 | 文件名 | 存储目录路径 | 说明与作用 |
| :--- | :--- | :--- | :--- |
| **YOLOv8 目标检测权重** | `yolov8n.pt` | `backend/yolov8n.pt` 及根目录 | 用于检测画面中的人员、车辆等实体，文件大小约 6.5 MB。 |
| **OSNet 重识别权重** | `osnet_x1_0.pth` / `osnet_x1_0.onnx` | `models/` 或 `backend/models/` | 用于跨镜头行人重识别 (Person ReID) 特征向量提取，可通过 `convert_osnet.py` 转换。 |
| **ByteTrack 追踪配置** | `bytetrack_fixed.yaml` | `backend/app/mva_v2/bytetrack_fixed.yaml` | 多目标跨帧连续追踪的算法配置文件。 |

---

## 4. 系统底层依赖工具安装 (Ubuntu 示例)

```bash
# 更新 apt 软件源并安装基础依赖与 FFmpeg
sudo apt-get update && sudo apt-get install -y \
    ffmpeg \
    git \
    curl \
    wget \
    build-essential

# 验证 FFmpeg 安装
ffmpeg -version
ffprobe -version
nvidia-smi
```
