import os
import sys


BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))

sys.path.insert(0, BACKEND_DIR)


from app import create_app
app = create_app()


if __name__ == "__main__":
    print("✅ 后端服务启动中（通用相对路径配置）...")
    # 生产环境仅监听本机，通过 HTTPS 反向代理对外提供服务。
    # 隔离的容器网络可按需设置 PUREYES_HOST=0.0.0.0。
    port = int(os.getenv("PUREYES_PORT", "5000"))
    host = os.getenv("PUREYES_HOST", "127.0.0.1")
    debug = os.getenv("PUREYES_DEBUG", "0").lower() in {"1", "true", "yes"}
    app.run(debug=debug, host=host, port=port, use_reloader=False)
