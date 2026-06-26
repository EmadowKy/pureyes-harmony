import os
import sys


BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))

sys.path.insert(0, BACKEND_DIR)


from app import create_app
app = create_app()


if __name__ == "__main__":
    print("✅ 后端服务启动中（通用相对路径配置）...")
    # 启动服务，绑定8000端口
    app.run(debug=True, host="0.0.0.0", port=8000)