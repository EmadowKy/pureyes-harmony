import os
import sys


BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))

sys.path.insert(0, BACKEND_DIR)


from app import create_app
app = create_app()


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", os.environ.get("BACKEND_PORT", "8000")))
    print(f"Backend service starting: http://{host}:{port}")
    app.run(debug=True, host=host, port=port)
