import os
os.environ["OPENCV_LOG_LEVEL"] = "OFF"
import warnings
warnings.filterwarnings("ignore")

import sys
import time
import asyncio
import cv2
import logging

# Set backend path
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.mva_v2.database import SpatiotemporalDB
from app.mva_v2.pipeline import JITVideoPipeline

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

async def run_benchmark():
    video_path = os.path.abspath(os.path.join(backend_dir, "..", "example", "192.168.2.101_01_20160622163110996_91.mp4"))
    if not os.path.exists(video_path):
        print(f"Error: Video file not found at {video_path}")
        return

    print("=" * 85)
    print("         PUREYES 视频特征预处理性能与精度基准测试 Benchmark         ")
    print("=" * 85)

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    duration = total_frames / fps if fps > 0 else 0
    cap.release()

    orig_res_str = f"{width}x{height}"

    print(f"📹 测试视频元数据 (Video Metadata):")
    print(f"   - 文件名称: {os.path.basename(video_path)}")
    print(f"   - 原画分辨率: {orig_res_str} (高清)")
    print(f"   - 视频原生帧率 (FPS): {fps:.2f} 帧/秒")
    print(f"   - 视频总帧数: {total_frames} 帧 | 总物理时长: {duration:.2f} 秒 ({duration/60:.2f} 分钟)")
    print("-" * 85)

    # 全局初始化一次数据库与管道，避免重复初始化 CUDA Context 冲突
    db_client = SpatiotemporalDB()
    pipeline = JITVideoPipeline(db_client)
    video_id = os.path.basename(video_path)

    test_duration = 30.0  # 取前 30 秒片段做对比基准测试

    configs = [
        {"name": "最高精度模式 (Highest Precision)", "fps": 2.0, "res": "4K"},
        {"name": "标准推荐模式 (Recommended Mode)", "fps": 1.0, "res": "1080P"},
        {"name": "极速检索模式 (Fastest Mode)", "fps": 0.5, "res": "720P"}
    ]

    results = []

    for cfg in configs:
        print(f"\n🚀 正在测试: {cfg['name']} (采样率: {cfg['fps']} 帧/秒, 画质: {cfg['res']})...")
        # 清空当前 video_id 的历史记录以准确统计本次提取数量
        db_client.delete_video(video_id)

        t_start = time.perf_counter()
        await pipeline.process_clip(
            video_path=video_path,
            video_id=video_id,
            start_sec=0.0,
            end_sec=test_duration,
            progress_callback=None,
            sample_fps=cfg['fps'],
            resolution=cfg['res']
        )
        t_end = time.perf_counter()

        elapsed = t_end - t_start
        speedup = test_duration / elapsed if elapsed > 0 else 0
        records = [r for r in db_client.records if r.get('video_id') == video_id]
        
        results.append({
            "name": cfg['name'],
            "fps": cfg['fps'],
            "res": cfg['res'],
            "elapsed": elapsed,
            "speedup": speedup,
            "records": len(records),
            "est_1min": 60.0 / speedup if speedup > 0 else 0,
            "est_5min": 300.0 / speedup if speedup > 0 else 0
        })

    print("\n" + "=" * 85)
    print("                    预处理性能与指标对比报告 (BENCHMARK REPORT)                    ")
    print("=" * 85)
    print(f"{'测试模式':<24} | {'采样率/画质':<12} | {'耗时(30s片段)':<12} | {'实时倍速比':<8} | {'提取特征数':<10} | {'1分钟预估耗时'}")
    print("-" * 85)
    for r in results:
        param_str = f"{r['fps']}帧/s, {r['res']}"
        print(f"{r['name']:<22} | {param_str:<12} | {r['elapsed']:>9.2f}s    | {r['speedup']:>6.2f}x  | {r['records']:>8}条   | {r['est_1min']:>8.2f}s")
    print("=" * 85)

if __name__ == "__main__":
    asyncio.run(run_benchmark())
