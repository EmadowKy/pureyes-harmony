import os
import sys


BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))

sys.path.insert(0, BACKEND_DIR)


from app import create_app
app = create_app()


if __name__ == "__main__":
    print("✅ 后端服务启动中（通用相对路径配置）...")
    # Nginx 对外提供 8000 端口，后端默认监听内部 5000 端口。
    # 可通过 PUREYES_PORT 覆盖，便于本地开发或其他部署环境复用。
    port = int(os.getenv("PUREYES_PORT", "5000"))
    debug = os.getenv("PUREYES_DEBUG", "0").lower() in {"1", "true", "yes"}
    app.run(debug=debug, host="0.0.0.0", port=port, use_reloader=False)
