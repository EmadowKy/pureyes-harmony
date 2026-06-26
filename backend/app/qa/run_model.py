import os
import sys
import torch
import gc

current_file = os.path.abspath(__file__)
qa_dir = os.path.dirname(current_file)
project_root = os.path.dirname(qa_dir)
sys.path.append(project_root)

os.environ['PYTORCH_CUDA_ALLOC_CONF'] = 'expandable_segments:True,max_split_size_mb:512'

if torch.cuda.is_available():
    torch.cuda.empty_cache()

from typing import List, Dict, Any
from mva.agent_runner import AgentRunner

def ask_model(question: str, video_paths: List[str], config_path: str, 
                                  enable_memory_optimization: bool = True, 
                                  progress_callback=None) -> Dict[str, Any]:
    """
    使用多视频理解模型分析多个视频。
    将所有视频一次性传递给模型进行真正的多视频联合分析和对比。
    
    Args:
        question (str): 要分析的问题。
        video_paths (List[str]): 视频文件的相对路径列表（例如 'example/1.mp4'）。
        config_path (str): 模型配置文件的路径。
        enable_memory_optimization (bool): 启用 GPU 内存优化（默认为 True）。

    Returns:
        Dict[str, Any]: 模型的原始 JSON 响应。
    """
    if not video_paths:
        return {"error": "No video paths provided", "success": False}

    current_file = os.path.abspath(__file__)
    backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(current_file)))

    sample = {
        "question": question,
        "video_paths": video_paths
    }

    try:
        agent_runner = AgentRunner(config_path=config_path, device_id=0)
        result = agent_runner.run_on_sample(sample, video_base_dir=backend_dir, progress_callback=progress_callback)

        if result.get("success", True) is False:
            print(f"[ERROR] 多视频分析失败: {result.get('error', '未知错误')}")

        if enable_memory_optimization:
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            gc.collect()

        return result
    except Exception as e:
        print(f"[ERROR] 处理视频时出错: {e}")
        import traceback
        traceback.print_exc()
        return {"error": str(e), "success": False}
    

if __name__ == "__main__":
    current_file_path = os.path.abspath(__file__)
    current_dir = os.path.dirname(current_file_path)
    question = "这两个视频有什么区别？"
    video_paths = [
        os.path.join(current_dir, "../../example/1.mp4"),
        os.path.join(current_dir, "../../example/2.mp4")
    ]
    
    config_path = os.path.join(current_dir, "../../configs/model.yaml")

    analysis_result = ask_model(
        question, 
        video_paths, 
        config_path,
        enable_memory_optimization=True
    )
    print(analysis_result)