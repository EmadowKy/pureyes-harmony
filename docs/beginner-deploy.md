# 零基础前后端部署指南

这份文档按“我完全不懂前后端”的角度写。你只需要记住一句话：

- AutoDL 上只跑后端。
- 你的电脑上用 DevEco Studio 打开并运行前端。
- 前端里要改的 IP/地址，是 AutoDL 给你的公网访问地址，不是 AutoDL 容器内部 IP。

## 1. 先搞清楚三台机器

本项目有三部分环境：

| 位置 | 做什么 | 需要装什么 |
| --- | --- | --- |
| AutoDL 服务器 | 跑 Python 后端和大模型 | conda、Python、PyTorch、FFmpeg、模型文件 |
| 你的电脑 | 打开 HarmonyOS 前端工程、编译安装 App | DevEco Studio |
| 手机或模拟器 | 运行 App | 能访问 AutoDL 后端公网地址 |

负责人说的“先运行后端，再前端，记得在前端把 IP 改成自己的 IP”，意思是：

1. 先在 AutoDL 启动 `backend/run.py`。
2. 在 AutoDL 控制台拿到能从外部访问后端的地址。
3. 在前端文件 `frontend/entry/src/main/ets/utils/http.ets` 里，把旧地址改成 AutoDL 的外部访问地址。
4. 再用 DevEco Studio 运行前端。

## 2. AutoDL 上先跑后端

进入 AutoDL 容器终端，建议放在 `~/autodl-tmp`：

```bash
cd ~/autodl-tmp
```

如果 `git clone` 报 SSL 自签名证书错误，先执行：

```bash
apt-get update
apt-get install -y ca-certificates openssl git
update-ca-certificates

git config --global http.sslVerify true
git config --global http.sslCAInfo /etc/ssl/certs/ca-certificates.crt
```

克隆当前对接分支：

```bash
git clone -b deploy-relative-paths --single-branch https://github.com/EmadowKy/pureyes-harmony.git
cd pureyes-harmony
```

创建并进入 conda 环境：

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

安装 GPU 版 PyTorch：

```bash
pip install torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu126
```

安装项目后端依赖：

```bash
pip install -r backend/requirements-gpu.txt
```

## 3. 模型放哪里

本分支默认从项目根目录下读取模型：

```text
pureyes-harmony/models/Qwen3-VL-2B-Instruct
```

推荐你直接把 Hugging Face 模型下载到这个位置：

```bash
cd ~/autodl-tmp/pureyes-harmony
mkdir -p models
cd models
git clone https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct
cd ..
```

如果你已经把模型放在别的目录，例如 `/root/autodl-tmp/models/Qwen3-VL-2B-Instruct`，就改：

```text
backend/configs/model.yaml
```

把：

```yaml
main_model_path: "models/Qwen3-VL-2B-Instruct"
```

改成你的实际路径，例如：

```yaml
main_model_path: "/root/autodl-tmp/models/Qwen3-VL-2B-Instruct"
```

## 4. AutoDL 的 IP 到底填哪个

不要填这些：

- 不要填 `127.0.0.1`
- 不要填 `localhost`
- 不要填 `0.0.0.0`
- 不要填 AutoDL 容器里看到的内网 IP
- 不要继续用项目里原来的 `http://10.32.212.191:8000`

你要填的是 AutoDL 控制台给你的“外部访问地址”。

### 4.1 推荐用 AutoDL 映射端口

AutoDL 常见公网映射端口是 `6006` 或 `6008`。这个分支已经支持用环境变量改后端端口，所以建议先用 `6006` 启动后端：

```bash
cd ~/autodl-tmp/pureyes-harmony/backend
PORT=6006 python run.py
```

看到类似下面的输出就表示后端启动了：

```text
Backend service starting: http://0.0.0.0:6006
```

在 AutoDL 容器里先测一下：

```bash
curl http://127.0.0.1:6006/api/health
```

正常应该返回：

```json
{"code":0,"data":{"service":"backend"},"message":"ok"}
```

然后到 AutoDL 控制台找“自定义服务 / 端口映射 / 访问链接”一类入口，把容器内的 `6006` 对应的公网地址复制出来。它可能长得像：

```text
http://某个域名:某个端口
```

或者：

```text
https://某个域名:某个端口
```

这个完整地址才是前端要填的 `BASE_HOST`。

如果你的 AutoDL 控制台允许映射 `8000`，也可以用：

```bash
cd ~/autodl-tmp/pureyes-harmony/backend
PORT=8000 python run.py
```

但是前端依然要填 AutoDL 控制台复制出来的外部地址，不是 `0.0.0.0:8000`。

### 4.2 后端保持运行

终端一关，`python run.py` 可能会停。可以用 `nohup` 放后台：

```bash
cd ~/autodl-tmp/pureyes-harmony/backend
nohup env PORT=6006 python run.py > backend.log 2>&1 &
tail -f backend.log
```

如果要停止：

```bash
ps -ef | grep "python run.py"
kill 进程号
```

## 5. 在 DevEco Studio 里改前端 IP

DevEco Studio 是华为的开发工具，可以理解成“华为版 Android Studio / VS Code”，用来打开和运行 HarmonyOS 前端工程。

你不需要在 AutoDL 上安装 DevEco Studio。DevEco Studio 安装在你的电脑上。

### 5.1 安装 DevEco Studio

1. 打开华为 DevEco Studio 官方下载页。
2. 下载适合你电脑系统的安装包。
3. 一路安装。
4. 首次打开时，按提示安装或配置 HarmonyOS SDK。

如果你不确定 SDK 版本，先按 DevEco Studio 默认推荐安装。这个项目的前端配置在：

```text
frontend/build-profile.json5
```

里面写了：

```json5
"compatibleSdkVersion": "4.0.0(10)",
"targetSdkVersion": "6.1.1(24)",
"compileSdkVersion": "6.1.1(24)"
```

### 5.2 打开前端工程

在 DevEco Studio 里：

1. 点击 `Open`。
2. 选择仓库里的 `frontend` 文件夹，不是整个 `pureyes-harmony` 根目录。
3. 等它自动同步依赖，通常会看到 Hvigor / ohpm 相关同步过程。
4. 如果提示 Trust Project / 信任项目，选择信任。

### 5.3 改后端地址

打开这个文件：

```text
frontend/entry/src/main/ets/utils/http.ets
```

你会看到：

```ts
export const BASE_HOST = 'http://10.32.212.191:8000';
const BASE_URL = 'http://10.32.212.191:8000/api';
```

把它改成 AutoDL 控制台复制出来的外部访问地址。

假设 AutoDL 给你的地址是：

```text
https://abc123.autodl.com:6006
```

那就改成：

```ts
export const BASE_HOST = 'https://abc123.autodl.com:6006';
const BASE_URL = 'https://abc123.autodl.com:6006/api';
```

注意：

- `BASE_HOST` 后面不要加 `/api`
- `BASE_URL` 后面要加 `/api`
- 地址末尾不要多写 `/`
- `http` 还是 `https` 要和 AutoDL 给你的地址保持一致
- DevEco 模拟器里不要写 `localhost`。`localhost` 在模拟器里通常指模拟器自己，不是你的 Windows，也不是 AutoDL。

如果你用的是 AutoDL 弹窗给的 SSH 隧道命令，例如这种形式：

```bash
ssh -CNg -L 6006:127.0.0.1:6006 root@你的AutoDL连接地址 -p 端口号
```

那它的意思是“让 Windows 浏览器可以用 `http://localhost:6006` 访问 AutoDL 后端”。这不代表 DevEco 模拟器里的 App 也可以写 `localhost:6006`。

先在 Windows 浏览器里测试：

```text
http://localhost:6006/api/health
```

如果 Windows 本机都打不开，说明后端或 SSH 隧道还没通，先不要调前端。

如果 Windows 本机能打开，再给 DevEco 模拟器试这个地址：

```ts
export const BASE_HOST = 'http://10.0.2.2:6006';
const BASE_URL = 'http://10.0.2.2:6006/api';
```

如果 `10.0.2.2` 也不通，就回到 AutoDL 控制台复制真正的公网访问地址，按上面的方式填入 `http.ets`。

改完保存。

## 6. 在 DevEco Studio 里运行前端

### 6.1 用模拟器

如果你没有 HarmonyOS 真机，可以先用 DevEco Studio 的模拟器。

大致流程：

1. 打开 Device Manager / 设备管理器。
2. 创建或启动一个 HarmonyOS 模拟器。
3. 顶部运行配置选择 `entry`。
4. 点击绿色运行按钮。

### 6.2 用真机

如果你有华为 / HarmonyOS 真机：

1. 手机打开开发者模式。
2. 打开 USB 调试。
3. 用数据线连接电脑。
4. DevEco Studio 识别到设备后，选择该设备运行。

首次运行可能需要签名配置。DevEco Studio 通常会提示自动生成调试签名；先按提示走 Debug 签名即可。

## 7. 怎么确认前后端连通

### 7.1 先用浏览器测后端

在你的电脑浏览器或手机浏览器里打开：

```text
AutoDL外部访问地址/api/health
```

例如：

```text
https://abc123.autodl.com:6006/api/health
```

能看到：

```json
{"code":0,"data":{"service":"backend"},"message":"ok"}
```

说明后端地址填对了。

### 7.2 再运行 App 登录

App 打开后，用默认账号：

```text
工号: admin
密码: admin
```

如果登录提示 Network Error，优先检查：

- 后端是不是还在 AutoDL 上运行。
- AutoDL 的外部访问地址是不是复制错了。
- `http.ets` 里的 `BASE_HOST` 和 `BASE_URL` 有没有一起改。
- 手机或模拟器能不能打开 `AutoDL外部访问地址/api/health`。
- 你是不是误填了 `127.0.0.1`、`localhost`、`0.0.0.0` 或容器内网 IP。

## 8. 一句话排错表

| 现象 | 最可能原因 | 处理 |
| --- | --- | --- |
| AutoDL 里 `curl 127.0.0.1:6006/api/health` 不通 | 后端没启动或端口不对 | 重新 `PORT=6006 python run.py` |
| 浏览器打不开 `AutoDL地址/api/health` | AutoDL 端口映射没开或地址不对 | 去 AutoDL 控制台复制外部访问地址 |
| App 启动后红字提示“服务器未连接” | 模拟器访问不到后端，常见是误写了 `localhost` | Windows 先测 `后端地址/api/health`；模拟器不要用 `localhost`，优先用 AutoDL 公网地址，SSH 隧道调试可试 `10.0.2.2:6006` |
| App 登录 Network Error | 前端地址填错 | 改 `frontend/entry/src/main/ets/utils/http.ets` |
| 后端报模型路径不存在 | 模型没放到 `models/Qwen3-VL-2B-Instruct` | 下载模型或改 `model.yaml` |
| DevEco Studio 打不开工程 | 打开目录错了 | 选择 `frontend/` 文件夹 |
| DevEco Studio 提示 hvigor 配置版本 `26.0.0` 不支持 | 前端工程的 Hvigor 配置版本高于 DevEco 6.1.1 支持范围 | 拉取最新 `deploy-relative-paths` 分支，或把 `frontend/oh-package.json5` 和 `frontend/hvigor/hvigor-config.json5` 的 `modelVersion` 改成 `6.1.1` |
| DevEco Studio 提示 `compileSdkVersion / compatibleSdkVersion / targetSdkVersion` 不正确 | `frontend/build-profile.json5` 里的 SDK 版本仍是 `26.0.0` | 拉取最新 `deploy-relative-paths` 分支，或改成 `compatibleSdkVersion: "4.0.0(10)"`、`targetSdkVersion: "6.1.1(24)"`、`compileSdkVersion: "6.1.1(24)"` |
| DevEco Studio 提示 `If Compatible SDK Version is 4.1.0(11) or earlier, set useNormalizedOHMUrl to false` | 兼容 SDK 较低但 strictMode 仍启用规范化 OHM URL | 拉取最新 `deploy-relative-paths` 分支，或把 `frontend/build-profile.json5` 中的 `useNormalizedOHMUrl` 改成 `false` |

## 9. 官方资料

- AutoDL SSH 与端口访问说明：https://www.autodl.com/docs/ssh_proxy/
- DevEco Studio 官方下载页：https://developer.huawei.com/consumer/en/deveco-studio/
- Qwen3-VL-2B-Instruct 模型页：https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct
