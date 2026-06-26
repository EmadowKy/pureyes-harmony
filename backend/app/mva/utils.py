
# from zai import ZhipuAiClient
import base64
import cv2
import os
os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"
# os.environ["HF_HUB_OFFLINE"] = "1"
# os.environ["TRANSFORMERS_OFFLINE"] = "1"

from functools import lru_cache

from transformers import Qwen3VLForConditionalGeneration, Qwen2_5_VLForConditionalGeneration, AutoProcessor, set_seed
from qwen_vl_utils import process_vision_info

# 全局模型缓存，按GPU ID存储
_model_cache = {}
_processor_cache = {}

def init(model_path: str="Qwen3-VL-2B-Instruct", device_id: int=None):
    """
    初始化模型和处理器
    
    Args:
        model_path: 模型路径
        device_id: GPU设备ID (0-7)，如果为None则使用device_map="auto"
    """
    # Set seed for reproducibility
    set_seed(42)

    # 如果指定了device_id，使用缓存
    if device_id is not None:
        cache_key = f"{model_path}_{device_id}"
        if cache_key in _model_cache:
            return _model_cache[cache_key], _processor_cache[cache_key]
    
    # 设置设备映射
    if device_id is not None:
        device_map = f"cuda:{device_id}"
    else:
        device_map = "auto"
    
    # Check if model exists in cache to avoid reloading even without device_id if previously loaded with same params
    # But simplifying: always trust cache if device_id provided.
    
    try:
        if "Qwen3" in model_path:
            model = Qwen3VLForConditionalGeneration.from_pretrained(
                model_path, 
                dtype="auto",
                device_map=device_map
            )
        elif "Qwen2.5" in model_path:
            model = Qwen2_5_VLForConditionalGeneration.from_pretrained(
                model_path, 
                dtype="auto",
                device_map=device_map
            )

        processor = AutoProcessor.from_pretrained(model_path)
    except Exception as e:
        # Fallback or error handling
        print(f"Error loading model {model_path}: {e}")
        raise e
    
    # 缓存模型和处理器
    if device_id is not None:
        cache_key = f"{model_path}_{device_id}"
        _model_cache[cache_key] = model
        _processor_cache[cache_key] = processor
    
    return model, processor


def Qwen_VL(messages, device_id=None, model_path="Qwen3-VL-2B-Instruct", max_tokens=2048):
    model, processor = init(model_path=model_path, device_id=device_id)
    text = processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    
    # Qwen2.5 uses patch size 14, Qwen3 uses 16 
    if "Qwen2.5" in model_path:
        images, videos, video_kwargs = process_vision_info(messages, return_video_kwargs=True, return_video_metadata=True)
    else:
        images, videos, video_kwargs = process_vision_info(messages, image_patch_size=16, return_video_kwargs=True, return_video_metadata=True)

    if videos is not None:
        videos, video_metadatas = zip(*videos)
        videos, video_metadatas = list(videos), list(video_metadatas)
    else:
        video_metadatas = None

    # Optional debug printing of model I/O controlled by environment variable PRINT_MODEL_IO

    inputs = processor(text=text, images=images, videos=videos, video_metadata=video_metadatas, return_tensors="pt", do_resize=False, **video_kwargs)
    inputs = inputs.to(model.device)

    # Use do_sample=False to minimize randomness (greedy decoding)
    generated_ids = model.generate(**inputs, max_new_tokens=max_tokens, do_sample=False)
    generated_ids_trimmed = [
        out_ids[len(in_ids) :] for in_ids, out_ids in zip(inputs.input_ids, generated_ids)
    ]
    output_text = processor.batch_decode(
        generated_ids_trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False
    )
    final_output = output_text[0] if output_text else ""

    return final_output


def answer(video_frames, question, options, prompt_template=None, device_id=None, model_path="Qwen3-VL-2B-Instruct", print_data=False, skip_iteration=False):
    """
    Generate an answer based on video frames and a question.
    
    Args:
        video_frames: List of image paths or PIL images.
        question: The question string.
        options: The options string (e.g., "A. ...\nB. ...").
        prompt_template: Optional prompt template. Can contain {QUESTION} and {OPTIONS} placeholders.
                        If provided, it replaces the default prompt construction.
        device_id: GPU ID.
        model_path: Model path.
        print_data: Whether to print the input data for debugging.
        skip_iteration: Whether to skip the iteration step.
    """
    # User provided template. Try to format it if it has placeholders.
    # Use safe formatting to avoid errors if keys are missing in template but present in args, or vice-versa
    try:
        # Check if template expects formatting
        if "{QUESTION}" in prompt_template or "{OPTIONS}" in prompt_template:
            prompt_text = prompt_template.replace("{QUESTION}", question).replace("{OPTIONS}", options)
            # Remove {FRAMES} placeholder if present, as frames are passed as images
            prompt_text = prompt_text.replace("{FRAMES}", "")
            # Remove {BBOX} placeholder if present (currently not supported by this function, might need to add if needed)
            prompt_text = prompt_text.replace("{BBOX}", "") 
        else:
            # If no standard placeholders, treat as prefix and append question/options
            prompt_text = f"{prompt_template}\n\nQuestion: {question}\nOptions:\n{options}"
    except Exception as e:
        print(f"Warning: Failed to format prompt template: {e}")
        prompt_text = f"{prompt_template}\n\nQuestion: {question}\nOptions:\n{options}"

    if print_data:
        print("=== Initial frames in frame bank ===")
        
    if not skip_iteration:
        filtered_frames = {}
        for k, v in video_frames.items():
            filtered_frames[k] = []
            for item in v:
                if isinstance(item, (tuple, list)) and len(item) >= 2:
                    path = item[0]
                    score = item[1]
                else:
                    path = item
                    score = 1.0 # Default keep for non-scored items (compatibility)
                    
                if print_data:
                    print(f"Path: {path}, Score: {score}")
                    
                if score >= 0.5:
                    filtered_frames[k].append((path, score))
        
        video_frames = filtered_frames

    if print_data:
        print("=== Answering ===")
        print("Question:", question)
        print("Options:", options)
        print(f"Number of filtered video frames: {len(video_frames)}")
        for k, v in video_frames.items():
            print(f"{k}: ")
            for frame in v:
                print(f"  Path: {frame[0]}, Score: {frame[1]}")
        print("==================")

    content = []
    
    for k, v in video_frames.items():
        # print(k)
        content.append({
            "type": "text",
            "text": f"The following is the {k}"
        })
        for frame in v:
            content.append({
                "type": "image",
                "image": frame[0] if isinstance(frame, tuple) else frame
            })
    content.append({
        "type": "text",
        "text": prompt_text
    })
        
    messages = [
        {
            "role": "user",
            "content": content
        }
    ]

    # print(f"messages: {messages}")
    
    try:
        output_text = Qwen_VL(messages, device_id=device_id, model_path=model_path, max_tokens=512)
    except Exception as e:
        print(f"Error in answer generation: {e}")
        output_text = "Error generating answer."

    if print_data:
        print("======Model output========\n", output_text)

    return output_text

def question_analyse(question, options, prompt_template=None, device_id=None, model_path="Qwen3-VL-2B-Instruct", print_data=False):
    """
    Analyze the question and options to determine the strategy.
    
    Args:
        question: The question string.
        options: The options string.
        prompt_template: Template for the analysis prompt.
        device_id: GPU ID.
        model_path: Model path.
        print_data: Whether to print debug info.
    """
    try:
        if prompt_template and ("{QUESTION}" in prompt_template or "{OPTIONS}" in prompt_template):
            prompt_text = prompt_template.replace("{QUESTION}", question).replace("{OPTIONS}", options)
        else:
            prompt_text = f"{prompt_template}\n\nQuestion: {question}\nOptions:\n{options}" if prompt_template else f"Question: {question}\nOptions:\n{options}"
    except Exception as e:
        print(f"Warning: Failed to format analysis prompt: {e}")
        prompt_text = f"Question: {question}\nOptions:\n{options}"

    if print_data:
        print("=== Question Analysis ===")
        print("Prompt:", prompt_text)
        print("=======================")

    messages = [
        {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": prompt_text
                }
            ]
        }
    ]
    
    try:
        output_text = Qwen_VL(messages, device_id=device_id, model_path=model_path, max_tokens=512)
    except Exception as e:
        print(f"Error in question analysis: {e}")
        output_text = "Analysis failed."

    if print_data:
        print("======Analysis Output========\n", output_text)

    return output_text
