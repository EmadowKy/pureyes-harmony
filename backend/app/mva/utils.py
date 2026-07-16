
import base64
import cv2
import os
import threading
import requests

# Thread-local storage for cloud API configuration
api_config = threading.local()

def init(model_path: str="Qwen3-VL-2B-Instruct", device_id: int=None):
    """
    Dummy init function returning None, None since PyTorch is completely discarded.
    """
    return None, None


def Qwen_VL(messages, device_id=None, model_path="Qwen3-VL-2B-Instruct", max_tokens=2048):
    api_key = getattr(api_config, 'api_key', None)
    base_url = getattr(api_config, 'base_url', None)
    model_name = getattr(api_config, 'model', None)
    
    if not api_key or not base_url:
        raise RuntimeError("未配置大模型 API 密钥或基础 URL，请先到‘我的’页面进行配置。")
        
    # Build messages for OpenAI API
    openai_messages = []
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", [])
        
        openai_content = []
        if isinstance(content, str):
            openai_content.append({"type": "text", "text": content})
        elif isinstance(content, list):
            for item in content:
                itype = item.get("type")
                if itype == "text":
                    openai_content.append({"type": "text", "text": item.get("text", "")})
                elif itype == "image":
                    img_path = item.get("image")
                    if img_path and os.path.exists(img_path):
                        try:
                            frame = cv2.imread(img_path)
                            if frame is not None:
                                h, w = frame.shape[:2]
                                max_size = 512
                                if max(h, w) > max_size:
                                    scale = max_size / max(h, w)
                                    frame = cv2.resize(frame, (int(w * scale), int(h * scale)))
                                success, buffer = cv2.imencode('.jpg', frame)
                                if success:
                                    b64_str = base64.b64encode(buffer).decode('utf-8')
                                    openai_content.append({
                                        "type": "image_url",
                                        "image_url": {
                                            "url": f"data:image/jpeg;base64,{b64_str}"
                                        }
                                    })
                                else:
                                    with open(img_path, "rb") as f:
                                        b64_str = base64.b64encode(f.read()).decode('utf-8')
                                    openai_content.append({
                                        "type": "image_url",
                                        "image_url": {
                                            "url": f"data:image/jpeg;base64,{b64_str}"
                                        }
                                    })
                            else:
                                with open(img_path, "rb") as f:
                                    b64_str = base64.b64encode(f.read()).decode('utf-8')
                                openai_content.append({
                                    "type": "image_url",
                                    "image_url": {
                                        "url": f"data:image/jpeg;base64,{b64_str}"
                                    }
                                })
                        except Exception as e:
                            print(f"[WARN] Failed to encode image to base64: {e}")
                            if os.path.exists(img_path):
                                with open(img_path, "rb") as f:
                                    b64_str = base64.b64encode(f.read()).decode('utf-8')
                                openai_content.append({
                                    "type": "image_url",
                                    "image_url": {
                                        "url": f"data:image/jpeg;base64,{b64_str}"
                                    }
                                })
        
        openai_messages.append({
            "role": role,
            "content": openai_content
        })
        
    url = f"{base_url.rstrip('/')}/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    req_model = model_name if model_name else "qwen3.7-plus"
    
    payload = {
        "model": req_model,
        "messages": openai_messages,
        "max_tokens": max_tokens,
        "stream": True
    }
    
    print(f"[MVA Cloud API] Sending request to {url} with model {req_model}")
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=60, stream=True)
        if response.status_code == 200:
            import json
            collected_chunks = []
            
            # Retrieve task_id from thread local to update running_tasks registry
            task_id = getattr(api_config, 'task_id', None)
            
            for line in response.iter_lines():
                if line:
                    decoded_line = line.decode('utf-8')
                    if decoded_line.startswith("data:"):
                        data_str = decoded_line[5:].strip()
                        if data_str == "[DONE]":
                            break
                        try:
                            chunk_json = json.loads(data_str)
                            delta = chunk_json['choices'][0]['delta']
                            chunk_text = delta.get('content')
                            if chunk_text is None:
                                chunk_text = ''
                            collected_chunks.append(chunk_text)
                            partial_text = "".join(collected_chunks)
                            
                            # Update running tasks dict dynamically for streaming/typewriter feedback
                            if task_id and getattr(api_config, 'is_final_answer', False):
                                from app.workspaces.routes import running_tasks
                                if task_id in running_tasks:
                                    import re
                                    match = re.search(r'"final_answer"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)', partial_text)
                                    if match:
                                        clean_answer = match.group(1)
                                        clean_answer = clean_answer.replace('\\"', '"').replace('\\n', '\n')
                                        running_tasks[task_id]['answer'] = clean_answer
                                    else:
                                        running_tasks[task_id]['answer'] = ""
                        except Exception as parse_err:
                            print(f"[MVA Stream Parse Error] {parse_err}")
                            
            content = "".join(collected_chunks)
            print(f"[MVA Cloud API] Answer (stream complete): {content}")
            return content
        else:
            print(f"[MVA Cloud API ERROR] Status {response.status_code}: {response.text}")
            raise RuntimeError(f"大模型 API 调用失败: 状态码 {response.status_code}, 错误信息: {response.text}")
    except Exception as e:
        print(f"[MVA Cloud API EXCEPTION] {e}")
        raise e


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
        setattr(api_config, 'is_final_answer', True)
        output_text = Qwen_VL(messages, device_id=device_id, model_path=model_path, max_tokens=512)
    except Exception as e:
        print(f"Error in answer generation: {e}")
        output_text = "Error generating answer."
    finally:
        setattr(api_config, 'is_final_answer', False)

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
