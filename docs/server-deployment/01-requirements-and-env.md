# 01-服务器硬件配置、CUDA 与环境依赖

> [!NOTE]
> **提示**：普通客户端用户默认连接官方服务器，无需搭建后端环境。本文档专为运维人员或有私有化独立部署需求的机构团队提供参考。

---

## 1. 服务器推荐硬件配置

为了确保视觉大模型与 YOLOv8/OSNet 推理的流畅运行，自建 GPU 服务器建议满足以下硬件规范：

| 硬件资源 | 最低配置 | 推荐配置 (生产环境) |
| :--- | :--- | :--- |
| **操作系统** | Ubuntu 20.04 LTS | Ubuntu 22.04 LTS |
| **CPU** | 8 核 Intel/AMD x86_64 | 16 核或以上 高频 CPU |
| **系统内存 (RAM)** | 16 GB | 32 GB 及以上 |
| **独立显卡 (GPU)** | NVIDIA GPU, 16 GB 显存 (如 RTX 4060 Ti 16G / T4) | NVIDIA GPU, 24 GB 显存 (如 RTX 3090 / 4090 / A10) |
| **CUDA 环境** | CUDA 11.8 或 CUDA 12.6 | PyTorch 内建 CUDA 12.6 Wheel |
| **磁盘空间** | 预留 50 GB 剩余空间 (NVMe SSD) | 预留 200 GB SSD (用于模型与视频存储) |
| **系统工具依赖** | `ffmpeg`, `ffprobe`, `git-lfs` | `ffmpeg`, `ffprobe`, `git-lfs`, `git` |

---

## 2. 软件环境与核心依赖库

后端环境基于 Python 3.10 运行环境建立：

- **核心 Web 框架**：Flask, Flask-CORS, Flask-SQLAlchemy, Werkzeug.
- **AI / 深度学习框架**：
  - `torch==2.7.1` (带 CUDA 支持)
  - `torchvision==0.22.1`
  - `transformers`
  - `ultralytics` (YOLOv8 依赖)
- **多媒体处理工具**：FFmpeg (必须确保可执行命令 `ffmpeg` 与 `ffprobe` 已加入全局 PATH)。

---

## 3. 系统底层依赖工具安装 (Ubuntu 示例)

```bash
# 更新 apt 软件源并安装基础依赖与 FFmpeg
sudo apt-get update && sudo apt-get install -y \
    ffmpeg \
    git \
    git-lfs \
    curl \
    wget \
    build-essential

# 验证 FFmpeg 安装
ffmpeg -version
ffprobe -version
nvidia-smi
```
