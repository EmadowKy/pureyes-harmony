import os
import sys
import yaml
import json
import time
from typing import Dict, Any, List
import math

# Adjust path to import from root directory
sys.path.append(os.path.dirname(os.path.abspath(__file__)))


from utils import init, answer, question_analyse
from agent import ToolAgent, DescAgent
import cv2
from PIL import Image
import numpy as np


# --- User Customization Section ---
def calculate_priority_score(current_score, acceleration, config):
    """
    Calculate a priority score for a video to determine if it should be selected for optimization.
    Higher priority score means higher chance of being selected.
    
    Args:
        current_score (float): The current score of the video.
        acceleration (float): The improvement rate of the last agent internal step.
                              (Typically from the previous run).
        config (dict): Configuration dictionary.
        
    Returns:
        float: The priority score.
    """
    # ---------------------------------------------------------
    # TODO: User can modify this formula manually.
    # Goal: Balanace between "needs improvement" (low score) and "has potential" (high acceleration).
    
    k = config['parameters'].get('priority_score_k', 1.0) # Weight for acceleration
    t = config['parameters'].get('priority_score_t', 1.0) # Weight for current score

    priority = (math.e**(k*acceleration))*((1-current_score)**t) # Base priority on how much improvement potential there is (low score) and how promising the acceleration is.
        
    return priority
    # ---------------------------------------------------------

def load_config(config_path):
    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)

class AgentRunner:
    def __init__(self, config_path, device_id=0, node_rank=0, run_id=None):
        self.config = load_config(config_path)
        self.device_id = device_id
        self.node_rank = node_rank
        self.run_id = run_id
        self.uniform_sample_count = {}  # 记录每个视频的均匀采样次数
        self._sampling_error_happened = False
        
        # If run_id is provided, override output paths to save everything in log/run_id folder
        if self.run_id:
            # We assume the script is running from root, so 'log' will be in root
            base_log_dir = os.path.join("log", self.run_id)
            
            # Update paths to be inside the log folder
            self.config['paths']['output_dir'] = base_log_dir
            self.config['paths']['video_frames_dir'] = os.path.join(base_log_dir, "video_frames")
            self.config['paths']['key_frames_dir'] = os.path.join(base_log_dir, "key_frames")
        
        # Prepare directories
        os.makedirs(self.config['paths']['output_dir'], exist_ok=True)
        # Also create subdirectories if they are used directly (some scripts might rely on them existing)
        os.makedirs(self.config['paths']['video_frames_dir'], exist_ok=True)
        os.makedirs(self.config['paths']['key_frames_dir'], exist_ok=True)
        
        # Initialize model
        self.model, self.processor = init(
            model_path=self.config['models']['main_model_path'], 
            device_id=device_id
        )

    def _mark_sampling_error(self, message: str):
        self._sampling_error_happened = True
        print(message)

    def run_on_sample(self, sample: Dict[str, Any], video_base_dir: str, prompt_override: str = None, progress_callback=None):
        """
        Run the agent on a single sample and return full details.
        
        sample: {
            "key": str/int (optional, task key)
            "question": str,
            "options": List[str],
            "video_paths": List[str] (filenames or relative paths),
            "answer": str (optional, ground truth),
            "task": str (optional)
        }
        
        Returns:
            dict: The complete result data structure.
        """
        if self.config['parameters'].get('print_output', False):
            print("\n\n\n")
        self._sampling_error_happened = False
        paths = self.config['paths']
        params = self.config['parameters']  
        prompts = self.config['prompts']
        skip_iteration = params.get('skip_iteration', False)
        question_analysis = params.get('question_analysis', False)
        
        # Extract basic info
        key = sample.get('key', 'unknown')
        question = sample.get('question', '')
        # Prioritize 'ground_truth', fallback to 'answer', default to empty string
        ground_truth = sample.get('ground_truth', sample.get('answer', ''))
            
        task_name = sample.get('task', '')
        
        # Adapt to different dataset keys for video list
        if 'video_paths' in sample:
            video_filenames = sample.get('video_paths', [])
        elif 'videos' in sample:
            video_filenames = sample.get('videos', [])
        else:
            video_filenames = []

        options_raw = sample.get('options', [])
        if isinstance(options_raw, list):
            options_text = "\n".join(options_raw)
        else:
            options_text = str(options_raw)
        
        full_video_paths = [os.path.join(video_base_dir, v) for v in video_filenames]
        
        # Initialize timing and tracking
        timings = {}
        total_start = time.time()

        process_logs = {
            'initialization': [],
            'iterations': [],
            'progress': []
        }

        def _emit_progress(stage, status, message=None, data=None):
            item = {
                'timestamp': time.time(),
                'stage': stage,
                'status': status,
                'message': message,
                'data': data or {}
            }
            process_logs.setdefault('progress', []).append(item)
            if progress_callback:
                try:
                    progress_callback(item)
                except Exception as e:
                    print(f"Warning: progress_callback failed: {e}")

        # Emit model initialization start
        _emit_progress('model_initialization', 'started', '模型初始化开始')
        
        # --- Validate Videos ---
        valid_videos = []
        
        for i, v_path in enumerate(full_video_paths, 1):
            if not os.path.exists(v_path):
                print(f"Warning: Video not found {v_path}")
                continue
            valid_videos.append((i, v_path))

        if not valid_videos:
            return {'error': "Error: No valid videos", 'success': False, 'key': key}

        # --- Initialize TextBank and Agents ---
        TextBank = {
            'question': question,
            'videos': {}
        }
        
        tool_agent = ToolAgent(self.model, self.processor, self.config, self.device_id)
        desc_agent = DescAgent(self.model, self.processor, self.config, self.device_id)
        
        if not skip_iteration and question_analysis:
            # --- Question Analysis Agent (Pre-Initialization) ---
            if self.config['parameters'].get('print_output', False):
                print("--- Question Analysis Agent Start ---")
                
            analysis_template = prompts.get('question_analysis', "")
            
            # Use question_analyse()
            analysis_result = question_analyse(
                question=question,
                options=options_text,
                prompt_template=analysis_template,
                device_id=self.device_id,
                model_path=self.config['models']['main_model_path'],
                print_data=self.config['parameters'].get('print_output', False)
            ).strip()
            
            TextBank['question_analysis'] = analysis_result
            process_logs['question_analysis'] = analysis_result
            
            if self.config['parameters'].get('print_output', False):
                print(f"Analysis Strategy: {analysis_result}\n---------------------------------------")
        
        if not question_analysis:
            self.config['prompts']['tool_combined_action'] = self.config['prompts']['tool_combined_action'].replace("{TOOL_ANALYSIS}", "")
            self.config['prompts']['desc_combined_action'] = self.config['prompts']['desc_combined_action'].replace("{DESC_ANALYSIS}", "")

        else:
            self.config['prompts']['tool_combined_action'] = self.config['prompts']['tool_combined_action'].replace("{TOOL_ANALYSIS}", self.config['prompts'].get('tool_analysis', ""))
            self.config['prompts']['desc_combined_action'] = self.config['prompts']['desc_combined_action'].replace("{DESC_ANALYSIS}", self.config['prompts'].get('desc_analysis', ""))

        _emit_progress('model_initialization', 'completed', '模型初始化完成')

        # print(self.config['prompts']['tool_combined_action'])
        # print(self.config['prompts']['desc_combined_action'])

        # Ensure q_id is unique across distributed nodes if key is unknown or shared
        if key != 'unknown':
            q_id = str(key)
        else:
            # Fallback: timestamp + rank + gpu to ensure uniqueness
            q_id = f"{int(time.time()*1000)}_n{self.node_rank}_g{self.device_id}"
        
        benchmark_name = paths.get('Benchmark_name', 'Benchmark')
        
        
        
        global_terminated = False

        num_frames = params.get('num_frames_iter', 8) if not skip_iteration else params.get('num_frames_noiter', 16)

        # Phase 1: Initialization
        for idx, v_path in valid_videos:
            if self.config['parameters'].get('number_type') == "123":
                v_name = f"Video {idx}"
            else:
                v_name = f"Video {chr(ord('A') + idx - 1)}"
                
            # Pre-calculate duration
            v_duration = self._get_video_duration(v_path)

            TextBank['videos'][v_name] = {
                'path': v_path,
                'idx': idx,
                'duration': v_duration,
                'iteration_count': 0,
                'description': "",
                'priority': 1.0, # Will be calculated
                'status': 'active',
                'last_acceleration': self.config['parameters']['agent']['initial_acceleration'],
                'last_score': 0.5, # Will be initialized by DescAgent
                'current_frames': [],
                'frame_bank': []
            }
            
            # Initialize uniformly sampled frames first
            safe_v_name = v_name.replace(" ", "_")
            self.uniform_sample_count[v_path] = 0
            frames_info = self._init_extract_uniform_frames(v_path, num_frames, q_id, safe_v_name, offset=0.0)

            if not frames_info:
                self._mark_sampling_error(
                    f"Error: Initial frame sampling failed for {v_name} ({v_path}). "
                    f"Expected {num_frames} frames, got 0."
                )
                TextBank['videos'][v_name]['status'] = 'tool_terminated'
                _emit_progress('sampling', 'failed', f"{v_name} 初始采样失败", {'video': v_name, 'expected_frames': num_frames, 'actual': len(frames_info)})
                process_logs['initialization'].append({
                    'video': v_name,
                    'status': 'sampling_failed',
                    'initial_description': 'Initial frame sampling failed.',
                    'acceleration': self.config['parameters']['agent']['initial_acceleration'],
                    'score': TextBank['videos'][v_name]['last_score'],
                    'priority': TextBank['videos'][v_name].get('priority', 1.0)
                })
                continue
            
            # Immediately add initial frames to frame_bank with score 0.5
            for f_info in frames_info:
                TextBank['videos'][v_name]['frame_bank'].append((f_info['path'], 0.5, f_info['time']))
            
            TextBank['videos'][v_name]['frame_bank'].sort(key=lambda x: x[1], reverse=True)
            bank_limit = self.config['parameters']['agent'].get('frame_bank_size', 16)
            
            # If skipping iteration, we should respect num_frames_noiter if it's larger than bank_limit
            # to avoid truncating uniformly sampled frames (which all have same 0.5 score initially)
            if skip_iteration:
                bank_limit = max(bank_limit, num_frames)

            if len(TextBank['videos'][v_name]['frame_bank']) > bank_limit:
                TextBank['videos'][v_name]['frame_bank'] = TextBank['videos'][v_name]['frame_bank'][:bank_limit]
            
            _emit_progress('sampling', 'completed', f"{v_name} 初始采样完成", {
                'video': v_name,
                'sampled_frames': len(frames_info),
                'frame_bank_size': len(TextBank['videos'][v_name]['frame_bank'])
            })
            
            if skip_iteration:
                continue

            # Use DescAgent to generate initial description and score
            v_label_str = v_name
            # For initialization, later videos can see descriptions of already initialized videos
            other_descs = {k: v.get('description', 'No description.') for k, v in TextBank['videos'].items() if k != v_name and v.get('description') != ""}
            
            # Create timestamped frames for DescAgent specifically
            init_vis_frames = self._add_timestamp_to_frames(frames_info, v_label_str)
            frame_paths = [f['path'] for f in init_vis_frames]
            
            # Use describe_and_evaluate
            # Note: describe_and_evaluate expects desc_old. For init, use empty string.
            if self.config['parameters'].get('print_output', False):    
                print(f"Initializing description and score for {v_name}")
            st = time.time()

            desc_new_part, score_new, v_term, g_term = desc_agent.describe_and_evaluate(
                question, 
                frames=frame_paths, 
                desc_old="", 
                other_descs=other_descs, 
                video_label=v_label_str,
                video_duration=v_duration,
                options_text=options_text,
                question_analysis=TextBank.get('question_analysis', "")
            )
            if self.config['parameters'].get('print_output', False): 
                ed = time.time()
                print(f"Initialization of {v_name} took {(ed - st):.2f} s")
            
            # Format initial description with time range (0 - duration)
            initial_desc = f"0.00-{v_duration:.2f}: {desc_new_part} (Score: {score_new:.2f})"
            
            TextBank['videos'][v_name]['current_frames'] = frames_info
            TextBank['videos'][v_name]['description'] = initial_desc
            TextBank['videos'][v_name]['last_score'] = score_new # Set initial score from model
            # Compute initial priority immediately after initialization
            initial_priority = calculate_priority_score(
                TextBank['videos'][v_name]['last_score'],
                TextBank['videos'][v_name]['last_acceleration'],
                self.config
            )
            TextBank['videos'][v_name]['priority'] = initial_priority
            
            # Check termination immediately
            if v_term:
                TextBank['videos'][v_name]['status'] = 'desc_terminated'

                for f_info in frames_info:
                    path = f_info['path']
                    for idx_bank, item in enumerate(TextBank['videos'][v_name]['frame_bank']):
                        if item[0] == path:
                            TextBank['videos'][v_name]['frame_bank'][idx_bank] = (path, score_new, f_info['time'])
                            break
                
                TextBank['videos'][v_name]['frame_bank'].sort(key=lambda x: x[1], reverse=True)
                if len(TextBank['videos'][v_name]['frame_bank']) > bank_limit:
                    TextBank['videos'][v_name]['frame_bank'] = TextBank['videos'][v_name]['frame_bank'][:bank_limit]
            
            _emit_progress('description_scoring', 'completed', f"{v_name} 初始描述和评分完成", {
                'video': v_name,
                'description': initial_desc,
                'score': score_new,
                'priority': TextBank['videos'][v_name].get('priority', 0.0)
            })
            
            process_logs['initialization'].append({
                'video': v_name,
                'status': 'initialized',
                'initial_description': initial_desc,
                'acceleration': self.config['parameters']['agent']['initial_acceleration'],
                'score': score_new,
                'priority': TextBank['videos'][v_name].get('priority', 1.0)
            })
            
            # Note: During initialization phase, we intentionally ignore g_term signals
            # to ensure all videos are initialized before considering global termination.
            # Global termination will be re-evaluated during the main iteration loop.
            if False:  # Disabled during initialization phase
                global_terminated = True
                break

        # Phase 2: Main Iteration Loop
        max_iterations = self.config['parameters'].get('agent', {}).get('global_max_iterations', 10)

        iteration_count = 0
        
        while not skip_iteration and not global_terminated and iteration_count < max_iterations:
            agent_cfg = self.config['parameters'].get('agent', {})
            min_accel = agent_cfg.get('min_acceleration_threshold', 0.2)
            max_score = agent_cfg.get('max_score_threshold', 0.8)

            active_videos = {k: v for k, v in TextBank['videos'].items() if v['status'] == 'active'}
            if not active_videos:
                break

            # Calculate priority for all active videos to select one
            for v_k, v_v in active_videos.items():
                v_v['priority'] = calculate_priority_score(v_v['last_score'], v_v['last_acceleration'], self.config)

            for v_k, v_v in active_videos.items():
                if v_v['last_acceleration'] < min_accel:
                    v_v['status'] = 'accel_terminated'
                if v_v['last_score'] >= max_score:
                    v_v['status'] = 'score_terminated'

            # # --- 终止逻辑：所有视频平均分超过阈值则整体终止 ---
            # all_scores = [v['last_score'] for v in TextBank['videos'].values()]
            # if all_scores and sum(all_scores)/len(all_scores) >= max_score:
            #     global_terminated = True
            #     break

            # 重新筛选活跃视频
            active_videos = {k: v for k, v in TextBank['videos'].items() if v['status'] == 'active'}
            if not active_videos:
                break

            v_curr_name = max(active_videos.keys(), key=lambda k: active_videos[k]['priority'])
            v_curr = TextBank['videos'][v_curr_name]

            # 初始化迭代对象（用于逐步填充卡片）
            iter_log = {
                'iteration': iteration_count + 1,
                'selected_video': v_curr_name,
                'priority_before': v_curr['priority'],
                'action': None,
                'new_description_part': None,
                'full_description': v_curr.get('description', ''),
                'old_score': v_curr.get('last_score', 0.5),
                'new_score': None,
                'acceleration': None,
                'video_terminated': False,
                'global_terminated': False
            }

            # 迭代开始时就发送初始的迭代框架
            _emit_progress('iteration', 'started', f"第 {iteration_count+1} 次主循环开始", {
                'iteration': iteration_count+1,
                'selected_video': v_curr_name,
                'priority': v_curr.get('priority'),
                'priority_before': v_curr['priority'],
                'current_score': v_curr.get('last_score', 0.5),
                'iteration_data': iter_log  # 发送初始框架
            })

            v_idx = v_curr['idx']
            if self.config['parameters'].get('number_type') == "123":
                v_label = f"Video {v_idx}"
            else:
                v_label = f"Video {chr(ord('A') + v_idx - 1)}"

            duration = v_curr.get('duration', self._get_video_duration(v_curr['path']))

            # --- Tool Agent Work ---
            current_candidate_frames = v_curr['current_frames']
            current_vis_frames = self._add_timestamp_to_frames(current_candidate_frames, v_label)
            existing_bank_frames = v_curr['frame_bank']
            current_video_desc = v_curr.get('description', "No description yet.")
            other_videos_desc = {k: v.get('description', 'No description.') for k, v in TextBank['videos'].items() if k != v_curr_name}

            if self.config['parameters'].get('print_output', False): 
                print(f"Tool Agent start for {v_curr_name}")
                st = time.time()
            
            candidate_scores, option, target_start, target_end = tool_agent.decide_action(
                question,
                existing_bank_frames,
                current_vis_frames,
                duration,
                video_label=v_label,
                current_video_desc=current_video_desc,
                other_videos_desc=other_videos_desc,
                options_text=options_text,
                question_analysis=TextBank.get('question_analysis', "")
            )
            ed = time.time()
            
            # 更新迭代对象的 action 信息
            iter_log['action'] = {
                'option': option,
                'target_start': target_start,
                'target_end': target_end
            }
            
            _emit_progress('iteration', 'tool_decided', f"第 {iteration_count+1} 次主循环工具决策完成", {
                'iteration': iteration_count+1,
                'selected_video': v_curr_name,
                'option': option,
                'target_start': target_start,
                'target_end': target_end,
                'candidate_scores': candidate_scores,
                'iteration_data': iter_log  # 发送带有 action 的更新版本
            })
            
            if self.config['parameters'].get('print_output', False): 
                print(f"Tool Agent finished for {v_curr_name}, took {(ed - st):.2f} s")

            # Update frame bank with SCORED candidates
            # Important: We store the ORIGINAL (clean) frames in the bank, not the timestamped ones
            # Timestamps are only for Agent's "eyes" during reasoning.
            # Deduplicate: Only add if not present, or if new score is higher
            existing_indices = {item[0]: i for i, item in enumerate(v_curr['frame_bank'])}

            for i, f_info in enumerate(current_candidate_frames):
                path = f_info['path']
                score = candidate_scores[i] if i < len(candidate_scores) else 0.5
                time_val = f_info['time']

                if path in existing_indices:
                    # If exists, check if new score is higher
                    idx = existing_indices[path]
                    old_path, old_score, old_time = v_curr['frame_bank'][idx]
                    if score > old_score:
                        v_curr['frame_bank'][idx] = (path, score, time_val)
                else:
                    # New frame
                    v_curr['frame_bank'].append((path, score, time_val))
                    # Update index map for subsequent checks in this loop (unlikely to have dups in one batch but safe)
                    existing_indices[path] = len(v_curr['frame_bank']) - 1

            # Enforce Frame Bank Capacity (keep top K scores)
            bank_limit = self.config['parameters']['agent'].get('frame_bank_size', 16)
            v_curr['frame_bank'].sort(key=lambda x: x[1], reverse=True)
            if len(v_curr['frame_bank']) > bank_limit:
                v_curr['frame_bank'] = v_curr['frame_bank'][:bank_limit]
            
            iter_log = {
                'iteration': iteration_count + 1,
                'selected_video': v_curr_name,
                'priority_before': v_curr['priority'],
                'action': {
                    'option': option,
                    'target_start': target_start,
                    'target_end': target_end
                }
            }

            if option == 6:
                v_curr['status'] = 'tool_terminated'
                iter_log['status'] = 'tool_terminated'
                process_logs['iterations'].append(iter_log)
                continue
            
            # Execute Action
            safe_v_curr_name = v_curr_name.replace(" ", "_")
            new_frames_info = self._sample_frames(v_curr['path'], option, target_start, target_end, num_frames, duration, q_id, safe_v_curr_name, iteration_count)
            new_frame_paths = [f['path'] for f in new_frames_info]
            
            if not new_frame_paths:
                _emit_progress('sampling', 'failed', f"第 {iteration_count+1} 次主循环采样失败", {
                    'video': v_curr_name,
                    'iteration': iteration_count+1,
                    'option': option,
                    'target_start': target_start,
                    'target_end': target_end,
                    'sampled': 0
                })
                self._mark_sampling_error(
                    f"Error: Iteration frame sampling failed for {v_curr_name} ({v_curr['path']}). "
                    f"option={option}, range=({target_start:.2f}, {target_end:.2f}), expected={num_frames}, got=0."
                )
                v_curr['status'] = 'tool_terminated'
                iter_log['status'] = 'tool_terminated_no_frames'
                process_logs['iterations'].append(iter_log)
                continue

            # Update Current Frames for NEXT iteration
            if option in [1, 3, 5]:
                v_curr['current_frames'] = new_frames_info
                
            _emit_progress('sampling', 'completed', f"第 {iteration_count+1} 次主循环采样完成", {
                'video': v_curr_name,
                'iteration': iteration_count+1,
                'sampled_frames': len(new_frames_info),
                'target_start': target_start,
                'target_end': target_end
            })
            
            # Note: We do NOT add new frames to bank yet. They will be scored in the NEXT iteration.
            
            # Create timestamped frames for DescAgent specifically
            new_vis_frames = self._add_timestamp_to_frames(new_frames_info, v_label)
            new_vis_frame_paths = [f['path'] for f in new_vis_frames]
            
            # --- Desc Agent Work ---
            # Describe NEW frames AND Evaluate status in ONE call
            other_descs = {k: v['description'] for k, v in TextBank['videos'].items() if k != v_curr_name}

            if self.config['parameters'].get('print_output', False): 
                print(f"Desc Agent start for {v_curr_name}")
                st = time.time()
            
            desc_new_part, score_new, v_term, g_term = desc_agent.describe_and_evaluate(
                question, 
                frames=new_vis_frame_paths, 
                desc_old=v_curr['description'], 
                other_descs=other_descs, 
                video_label=v_label,
                video_duration=duration,
                options_text=options_text,
                question_analysis=TextBank.get('question_analysis', "")
            )

            if self.config['parameters'].get('print_output', False): 
                ed = time.time()
                print(f"Desc Agent finished for {v_curr_name}, took {(ed - st):.2f} s")
            
            # Update Description
            # Get accurate times from actual sampled frames
            start_desc = 0.0
            end_desc = duration
            if new_frames_info:
                start_desc = new_frames_info[0]['time']
                end_desc = new_frames_info[-1]['time']
            else:
                start_desc = target_start
                end_desc = target_end
                
            formatted_desc_part = f"{int(round(start_desc))}-{int(round(end_desc))}: {desc_new_part} (Score: {score_new:.2f})"

            if v_curr['description'] == "Initial observation." or v_curr['description'] == "":
                 v_curr['description'] = formatted_desc_part
            else:
                 # Append new observation to existing history
                 v_curr['description'] += f"\n{formatted_desc_part}"

            old_score = v_curr['last_score']
            # Calculate standard improvement rate: (new - old) / old
            # Use a small epsilon for denominator to avoid division by zero
            acceleration = (score_new - old_score) / max(old_score, 0.01)
            # Update state
            v_curr['last_score'] = score_new
            v_curr['last_acceleration'] = acceleration
            v_curr['iteration_count'] += 1
            
            # Calculate priority_after
            priority_after = calculate_priority_score(score_new, acceleration, self.config)
            
            if v_term:
                v_curr['status'] = 'desc_terminated'
                # If desc_agent terminates, force add current frames with 1.0 score
                for f_info in v_curr['current_frames']:
                     v_curr['frame_bank'].append((f_info['path'], score_new, f_info['time']))
                # Re-sort and truncate
                v_curr['frame_bank'].sort(key=lambda x: x[1], reverse=True)
                if len(v_curr['frame_bank']) > self.config['parameters']['agent'].get('frame_bank_size', 16):
                    v_curr['frame_bank'] = v_curr['frame_bank'][:self.config['parameters']['agent'].get('frame_bank_size', 16)]
            if g_term:
                global_terminated = True
                # Global termination -> force add ALL active current frames (for the current video)
                if not v_term: # If not already handled above
                     for f_info in v_curr['current_frames']:
                        v_curr['frame_bank'].append((f_info['path'], score_new, f_info['time']))
                     v_curr['frame_bank'].sort(key=lambda x: x[1], reverse=True)
                     if len(v_curr['frame_bank']) > self.config['parameters']['agent'].get('frame_bank_size', 16):
                        v_curr['frame_bank'] = v_curr['frame_bank'][:self.config['parameters']['agent'].get('frame_bank_size', 16)]

            iter_log.update({
                'new_description_part': desc_new_part,
                'full_description': v_curr['description'],
                'old_score': old_score,
                'new_score': score_new,
                'acceleration': acceleration,
                'video_terminated': v_term,
                'global_terminated': g_term,
                'priority_after': priority_after
            })
            _emit_progress('description_scoring', 'completed', f"第 {iteration_count+1} 次主循环描述与评分完成", {
                'video': v_curr_name,
                'iteration': iteration_count+1,
                'new_score': score_new,
                'acceleration': acceleration,
                'v_term': v_term,
                'g_term': g_term,
                'description_snippet': desc_new_part,
                'iteration_data': iter_log  # 发送包含分数、描述等完整信息的更新版本
            })
            
            # 发送最终完整的迭代对象
            _emit_progress('iteration', 'completed', f"第 {iteration_count+1} 次主循环完成", {
                'iteration_data': iter_log,  # 发送完整的迭代对象
                'video': v_curr_name,
                'iteration': iteration_count+1,
                'status': v_curr['status'],
                'score': score_new,
                'acceleration': acceleration
            })
            
            process_logs['iterations'].append(iter_log)
            
            iteration_count += 1
            
        # Phase 3: Result Generation
        final_frame_paths = {}
        # final_frame_paths = {}
        final_descriptions_list = []
        for v_name, v_data in TextBank['videos'].items():
            safe_v_name = v_name.replace(" ", "_")
            # Apply watermark
            # Use cached duration if available
            v_duration = v_data.get('duration', 0.0)
            if v_duration <= 0 and os.path.exists(v_data['path']):
                v_duration = self._get_video_duration(v_data['path'])

            watermarked_frames = self._apply_watermark_to_bank(
                v_data['frame_bank'], 
                v_data['idx'], 
                q_id, 
                safe_v_name, 
                video_duration=v_duration
            )
            final_frame_paths[v_name] = watermarked_frames
            
            # v_label is already the key (v_name), or can be re-derived if needed for consistency check
            v_label = v_name
            
            desc_text = v_data.get('description', 'No description available.')
            final_descriptions_list.append(f"{v_label}: {desc_text}")
        
        final_descriptions_str = "\n".join(final_descriptions_list)
            
        _emit_progress('finalization', 'completed', '已生成视频描述和最终候选帧', {
            'final_descriptions': final_descriptions_str,
            'num_videos': len(TextBank['videos']),
            'frame_handler': 'final_frame_paths'
        })
            
        if not final_frame_paths:
             # Default check, will be refined below based on mode
             pass 

        # --- Dynamic Prompt Selection based on input types ---
        use_visual = params.get('use_visual_answer', True)
        use_text = params.get('use_text_answer', True)

        if not use_visual:
            final_frame_paths = {}
        if not use_text:
            final_descriptions_str = ""

        # Validate inputs based on mode
        if not use_visual and not use_text:
             return {'error': "Config Error: Both use_visual_answer and use_text_answer are False.", 'success': False, 'key': key}
        
        if use_visual and not final_frame_paths:
             return {'error': "No frames selected (Visual Answer required)", 'success': False, 'key': key}
             
        if use_text and not final_descriptions_str and not use_visual:
             # If text-only mode and no text, we can't proceed.
             return {'error': "No descriptions available (Text-only Answer required)", 'success': False, 'key': key}

        try:
            if prompt_override:
                current_prompt_template = prompt_override
            else:
                # Select template from config
                if use_visual and use_text:
                    current_prompt_template = prompts.get('answer_combined')
                    # Fallback to legacy 'answer' key if 'answer_combined' missing
                    if not current_prompt_template:
                        current_prompt_template = prompts.get('answer')
                elif use_visual and not use_text:
                    current_prompt_template = prompts.get('answer_visual_only')
                elif not use_visual and use_text:
                    current_prompt_template = prompts.get('answer_text_only')
            
            # Create a default template if missing (safety net)
            if not current_prompt_template:
                if use_visual and not use_text:
                     current_prompt_template = "Question: {QUESTION}\nOptions: {OPTIONS}\nAnswer based on the images."
                elif not use_visual and use_text:
                     current_prompt_template = "Video Descriptions:\n{DESCRIPTIONS}\n\nQuestion: {QUESTION}\nOptions: {OPTIONS}\nAnswer based on descriptions."
                else:
                     current_prompt_template = "Video Descriptions:\n{DESCRIPTIONS}\n\nQuestion: {QUESTION}\nOptions: {OPTIONS}\nAnswer based on images and descriptions."

            # Inject Descriptions if needed
            if "{DESCRIPTIONS}" in current_prompt_template:
                current_prompt_template = current_prompt_template.replace("{DESCRIPTIONS}", final_descriptions_str)
            else:
                # Fallback: if template doesn't have placeholder but we have text to show (and we are in a text mode), append it.
                if use_text and final_descriptions_str:
                    # Prepend description is standard practice
                    current_prompt_template = current_prompt_template.replace("Question:", f"Video Descriptions:\n{final_descriptions_str}\n\nQuestion:")

            _emit_progress('answering', 'started', '开始生成最终回答', {
                'use_visual': use_visual,
                'use_text': use_text,
                'template': current_prompt_template[:200]
            })
            
            if self.config['parameters'].get('print_output', False):
                print("=======Start Answering=====")
                st = time.time()

            output_text = answer(
                video_frames=final_frame_paths,
                question=question,
                options=options_text,
                prompt_template=current_prompt_template,
                device_id=self.device_id,
                model_path=self.config['models']['main_model_path'],
                print_data=self.config['parameters'].get('print_output', False),
                skip_iteration=skip_iteration
            )

            if self.config['parameters'].get('print_output', False):
                ed = time.time()
                print(f"Answer generation took {(ed - st):.2f} s")
            
            _emit_progress('answering', 'completed', '最终回答生成完成', {
                'answer_preview': output_text.strip()[:200]
            })
            
            ans_output_clean = output_text.strip()
            predicted_ans = ans_output_clean if ans_output_clean else ""
                    
        except Exception as e:
            predicted_ans = ""
            output_text = str(e)
            
        is_correct = False
        if ground_truth and predicted_ans:
            if predicted_ans.upper() == ground_truth.upper():
                is_correct = True
                 
        total_end = time.time()
        timings['total_pipeline_duration'] = round(total_end - total_start, 3)

        model_outputs = {
            'final_description': {k: v['description'] for k, v in TextBank['videos'].items()},
            'answer_generation': {
                'raw_output': output_text
            }
        }
        
        try:
            # 清理 key_frames 目录 (如果配置为不保存)
            if not self.config['parameters'].get('save_key_frames', False):
                try:
                    question_dir = os.path.join(self.config['paths']['key_frames_dir'], q_id)
                    if os.path.exists(question_dir):
                        import shutil
                        shutil.rmtree(question_dir)
                except Exception as e:
                    print(f"Warning: Failed to clean up key frames directory: {e}")
                    
            # 清理 video_frames 目录 (如果配置为不保存)
            if not self.config['parameters'].get('save_video_frames', False):
                try:
                    question_dir = os.path.join(self.config['paths']['video_frames_dir'], q_id)
                    if os.path.exists(question_dir):
                        import shutil
                        shutil.rmtree(question_dir)
                except Exception as e:
                    print(f"Warning: Failed to clean up video frames directory: {e}")
        except Exception as e:
             print(f"Warning: Global cleanup failed in run_on_sample: {e}")

        return {
            'key': key,
            'question': question,
            'options': options_raw,
            'task': task_name,
            'predicted_answer': predicted_ans,
            'ground_truth': ground_truth,
            'is_correct': is_correct,
            'process_logs': process_logs,
            'timings': timings,
            'iterations': iteration_count,
            'model_outputs': model_outputs,
            'success': not self._sampling_error_happened
        }

    def _get_video_duration(self, video_path: str) -> float:
        try:
            cap = cv2.VideoCapture(video_path)
            if not cap.isOpened():
                return 0.0
            fps = cap.get(cv2.CAP_PROP_FPS)
            frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
            duration = frame_count / fps if fps > 0 else 0
            cap.release()
            return duration
        except Exception as e:
            print(f"Error getting video duration: {e}")
            return 0.0

    def _extract_frame_at_time(self, video_path: str, time_sec: float, output_dir: str, frame_name: str) -> str:
        try:
            cap = cv2.VideoCapture(video_path)
            if not cap.isOpened():
                self._mark_sampling_error(f"Error: Failed to open video for frame extraction: {video_path}")
                return None
            
            fps = cap.get(cv2.CAP_PROP_FPS)
            if fps <= 0:
                self._mark_sampling_error(f"Error: Invalid FPS ({fps}) while extracting frame from {video_path}")
                cap.release()
                return None

            total_frames = cap.get(cv2.CAP_PROP_FRAME_COUNT)
            frame_idx = int(time_sec * fps)
            
            # Safety check: ensure frame_idx is within valid range
            if total_frames > 0 and frame_idx >= total_frames:
                frame_idx = int(total_frames) - 1
            if frame_idx < 0:
                frame_idx = 0
                
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            cap.release()
            
            if ret: 
                # Resize if configured
                target_size = self.config['parameters'].get('size', -1)
                if target_size > 0:
                    h, w = frame.shape[:2]
                    if max(h, w) > target_size:
                        scale = target_size / max(h, w)
                        new_w = int(w * scale)
                        new_h = int(h * scale)
                        frame = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_AREA)

                frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                frame_image = Image.fromarray(frame_rgb)
                save_path = os.path.join(output_dir, frame_name)
                frame_image.save(save_path)
                return save_path
            self._mark_sampling_error(
                f"Error: Failed to read frame at time={time_sec:.2f}s (frame_idx={frame_idx}) "
                f"from {video_path}"
            )
        except Exception as e:
            self._mark_sampling_error(f"Error extracting frame from {video_path} at {time_sec:.2f}s: {e}")
        return None
    
    def _init_extract_uniform_frames(self, video_path: str, num_frames: int, q_id: str, v_name: str, offset: float = 0.0) -> List[dict]:
        duration = self._get_video_duration(video_path)
        if duration <= 0:
            self._mark_sampling_error(f"Error: Invalid video duration ({duration}) for initial uniform sampling: {video_path}")
            return []

        output_dir = os.path.join(self.config['paths']['video_frames_dir'], q_id, v_name)
        os.makedirs(output_dir, exist_ok=True)
        
        times = np.linspace(0, duration, num_frames)
        times = [min(max(t + offset, 0), duration) for t in times]
        
        frames_info = []
        for i, t in enumerate(times):
            f_name = f"uniform_{i}_{t:.2f}.jpg"
            f_path = self._extract_frame_at_time(video_path, t, output_dir, f_name)
            if f_path:
                frames_info.append({'path': f_path, 'time': t})
            else:
                self._mark_sampling_error(
                    f"Error: Initial uniform sampling failed for {video_path}, "
                    f"index={i}, time={t:.2f}s"
                )

        if len(frames_info) < num_frames:
            self._mark_sampling_error(
                f"Error: Initial uniform sampling incomplete for {video_path}. "
                f"expected={num_frames}, got={len(frames_info)}"
            )
        return frames_info

    def _extract_uniform_frames(self, video_path: str, num_frames: int, q_id: str, v_name: str, offset: float = 0.0) -> List[dict]:
        duration = self._get_video_duration(video_path)
        if duration <= 0:
            self._mark_sampling_error(f"Error: Invalid video duration ({duration}) for uniform sampling: {video_path}")
            return []

        output_dir = os.path.join(self.config['paths']['video_frames_dir'], q_id, v_name)
        os.makedirs(output_dir, exist_ok=True)
        
        times = np.linspace(0, duration, num_frames + 2)[1:-1]
        times = [min(max(t + offset, 0), duration) for t in times]
        
        frames_info = []
        for i, t in enumerate(times):
            f_name = f"uniform_{i}_{t:.2f}.jpg"
            f_path = self._extract_frame_at_time(video_path, t, output_dir, f_name)
            if f_path:
                frames_info.append({'path': f_path, 'time': t})
            else:
                self._mark_sampling_error(
                    f"Error: Uniform sampling failed for {video_path}, "
                    f"index={i}, time={t:.2f}s"
                )

        if len(frames_info) < num_frames:
            self._mark_sampling_error(
                f"Error: Uniform sampling incomplete for {video_path}. "
                f"expected={num_frames}, got={len(frames_info)}"
            )
        return frames_info

    def _add_timestamp_to_frames(self, frames_info: List[dict], video_label: str) -> List[dict]:
        """
        Add timestamp and video label watermark to temporary copies of frames.
        Returns a list of NEW frame paths (temporary).
        """
        new_frames = []
        for f_info in frames_info:
            src_path = f_info['path']
            time_val = f_info['time']
            
            if not os.path.exists(src_path):
                continue
                
            # Create a temp path in the same directory but with _ts suffix
            dir_name = os.path.dirname(src_path)
            file_name = os.path.basename(src_path)
            name, ext = os.path.splitext(file_name)
            dst_path = os.path.join(dir_name, f"{name}_ts{ext}")
            
            # Always regenerate to ensure watermark updates (e.g. if position/style changed)
            try:
                img = cv2.imread(src_path)
                if img is not None:
                    h, w = img.shape[:2]
                    
                    # Dynamic scale based on height (Base 1.0 for 720p)
                    font_scale = max(1.0, h / 400.0)
                    thickness = max(2, int(2 * font_scale))
                    
                    color_label = (0, 255, 255) # Yellow
                    color_time = (0, 0, 255)    # Red
                    color_border = (0, 0, 0)   # Black
                    
                    # 1. Video Label
                    pad_x = int(20 * font_scale)
                    pad_y = int(30 * font_scale)
                    
                    text_size_label = cv2.getTextSize(video_label, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)[0]
                    x_label = pad_x
                    y_label = pad_y + text_size_label[1]
                    
                    # Border & Text
                    cv2.putText(img, video_label, (x_label, y_label), cv2.FONT_HERSHEY_SIMPLEX, font_scale, color_border, thickness + 2, cv2.LINE_AA)
                    cv2.putText(img, video_label, (x_label, y_label), cv2.FONT_HERSHEY_SIMPLEX, font_scale, color_label, thickness, cv2.LINE_AA)

                    # 2. Timestamp (below label)
                    time_text = f"{int(round(time_val))}s"
                    text_size_time = cv2.getTextSize(time_text, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)[0]
                    
                    x_time = pad_x
                    y_time = y_label + int(10 * font_scale) + text_size_time[1]
                    
                    # Border & Text
                    cv2.putText(img, time_text, (x_time, y_time), cv2.FONT_HERSHEY_SIMPLEX, font_scale, color_border, thickness + 2, cv2.LINE_AA)
                    cv2.putText(img, time_text, (x_time, y_time), cv2.FONT_HERSHEY_SIMPLEX, font_scale, color_time, thickness, cv2.LINE_AA)
                    
                    cv2.imwrite(dst_path, img)
            except Exception as e:
                print(f"Error adding watermark: {e}")
                    
            new_frames.append({'path': dst_path, 'time': time_val})
            
        return new_frames

    def _sample_frames(self, video_path: str, option: int, target_start: float, target_end: float, num_frames: int, duration: float, q_id: str, v_name: str, iteration: int) -> List[dict]:
        output_dir = os.path.join(self.config['paths']['video_frames_dir'], q_id, v_name)
        os.makedirs(output_dir, exist_ok=True)

        if num_frames <= 0:
            self._mark_sampling_error(f"Error: Invalid num_frames={num_frames} for sampling video {video_path}")
            return []
        
        if option == 5:
            # Global uniform，每次采样offset递增
            if video_path not in self.uniform_sample_count:
                self.uniform_sample_count[video_path] = 0
            self.uniform_sample_count[video_path] += 1
            offset = (duration / (num_frames+1) * 0.25) * self.uniform_sample_count[video_path] # 每次增加25%间隔的偏移，确保每次采样点都不同
            return self._extract_uniform_frames(video_path, num_frames, q_id, v_name, offset=offset)

        if target_end < target_start:
            self._mark_sampling_error(
                f"Error: Invalid sampling range for {video_path}, "
                f"start={target_start:.2f}, end={target_end:.2f}"
            )
            return []
            
        # For options 1-4, sample within [target_start, target_end]
        times = np.linspace(target_start, target_end, num_frames + 2)[1:-1]
        frames_info = []
        for i, t in enumerate(times):
            f_name = f"iter{iteration}_{i}_{t:.2f}.jpg"
            f_path = self._extract_frame_at_time(video_path, t, output_dir, f_name)
            if f_path:
                frames_info.append({'path': f_path, 'time': t})
            else:
                self._mark_sampling_error(
                    f"Error: Iterative sampling failed for {video_path}, "
                    f"iteration={iteration}, option={option}, index={i}, time={t:.2f}s"
                )

        if len(frames_info) < num_frames:
            self._mark_sampling_error(
                f"Error: Iterative sampling incomplete for {video_path}. "
                f"iteration={iteration}, option={option}, expected={num_frames}, got={len(frames_info)}"
            )
        return frames_info

    def _wm_visual(self, img, video_idx):
        """
        Mode 1: (video_tag) - Add Video Label ONLY.
        """
        h, w = img.shape[:2]
        # Dynamic scale based on height (Base 1.0 for 720p)
        font_scale = max(1.0, h / 400.0)
        thickness = max(2, int(2 * font_scale))
        
        color_label = (0, 255, 255) # Yellow
        color_border = (0, 0, 0)    # Black
        
        # Determine label text
        if self.config['parameters'].get('number_type') == "123":
            label = f"Video {video_idx}"
        else:
            label = f"Video {chr(ord('A') + video_idx - 1)}"
            
        pad_x = int(20 * font_scale)
        pad_y = int(30 * font_scale)
        
        text_size_label = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)[0]
        x_label = pad_x
        y_label = pad_y + text_size_label[1]
        
        # Border & Text
        cv2.putText(img, label, (x_label, y_label), cv2.FONT_HERSHEY_SIMPLEX, font_scale, color_border, thickness + 2, cv2.LINE_AA)
        cv2.putText(img, label, (x_label, y_label), cv2.FONT_HERSHEY_SIMPLEX, font_scale, color_label, thickness, cv2.LINE_AA)
        
        return img

    def _wm_temporal(self, img, video_idx, time_sec):
        """
        Mode 2: (temporal_tag) - Add Timestamp (or progress?) ONLY.
        """
        h, w = img.shape[:2]
        # Dynamic scale based on height (Base 1.0 for 720p)
        font_scale = max(1.0, h / 400.0)
        thickness = max(2, int(2 * font_scale))
        
        color_time = (0, 0, 255)    # Red
        color_border = (0, 0, 0)    # Black
        
        # Calculate Label Position (To check where to put timestamp)
        # Even if label is not drawn, we reserve the space so it matches the other view.
        # Determine label text (just for size calculation)
        if self.config['parameters'].get('number_type') == "123":
            label = f"Video {video_idx}"
        else:
            label = f"Video {chr(ord('A') + video_idx - 1)}"
            
        pad_x = int(20 * font_scale)
        pad_y = int(30 * font_scale)
        
        text_size_label = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)[0]
        y_label_bottom = pad_y + text_size_label[1]
        
        # Timestamp
        text = f"{int(round(time_sec))}s"
        text_size_time = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)[0]
        
        x_time = pad_x
        y_time = y_label_bottom + int(10 * font_scale) + text_size_time[1]
        
        # Border & Text
        cv2.putText(img, text, (x_time, y_time), cv2.FONT_HERSHEY_SIMPLEX, font_scale, color_border, thickness + 2, cv2.LINE_AA)
        cv2.putText(img, text, (x_time, y_time), cv2.FONT_HERSHEY_SIMPLEX, font_scale, color_time, thickness, cv2.LINE_AA)
        
        return img

    def _wm_trans_sequence(self, frame_bank, video_idx, output_dir):
        """
        Mode 3: (trans_frame)
        Insert a transition frame [Video X] BEFORE the frames of the video.
        Format: [Video1][frame1]...[Video2][frame1]...
        """
        watermarked_paths = []
        
        # Determine label
        if self.config['parameters'].get('number_type') == "123":
            label = f"Video {video_idx}"
        else:
            label = f"Video {chr(ord('A') + video_idx - 1)}"

        # Create separator frame
        # Use simple size or detect from first real frame
        h, w = 720, 1280
        if frame_bank and os.path.exists(frame_bank[0][0]):
            tmp = cv2.imread(frame_bank[0][0])
            if tmp is not None:
                h, w = tmp.shape[:2]

        trans_img = np.zeros((h, w, 3), dtype=np.uint8)
        font = cv2.FONT_HERSHEY_SIMPLEX
        # Calculate text position
        text_size = cv2.getTextSize(label, font, 2.0, 3)[0]
        text_x = (w - text_size[0]) // 2
        text_y = (h + text_size[1]) // 2
        cv2.putText(trans_img, label, (text_x, text_y), font, 2.0, (255, 255, 255), 3, cv2.LINE_AA)
        
        trans_path = os.path.join(output_dir, f"trans_{video_idx}.jpg")
        cv2.imwrite(trans_path, trans_img)
        
        # Add separator frame FIRST
        watermarked_paths.append((trans_path, 1.0))
            
        # Add regular frames (just copy them to be safe, or just return path if no other watermark)

        for i, (src, score, _) in enumerate(frame_bank):
             watermarked_paths.append((src, score))
             
        return watermarked_paths

    def _apply_watermark_to_bank(self, frame_bank: List[tuple], video_idx: int, q_id: str, v_name: str, video_duration: float = 0.0) -> List[tuple]:
        # Sort frame bank by timestamp before processing
        # frame_bank items are (path, score, time)
        sorted_bank = sorted(frame_bank, key=lambda x: x[2])
        
        wm_type = self.config['parameters'].get('type_watermark', 'none')
        
        # If disabled or unknown
        if wm_type == 'none':
            return [(f[0], f[1]) for f in sorted_bank]
            
        output_dir = os.path.join(self.config['paths']['key_frames_dir'], q_id, v_name)
        os.makedirs(output_dir, exist_ok=True)
        

            
        watermarked_paths = []
        
        # 1. Apply visual/temporal watermarks first
        processed_frames_with_time = [] 

        for i, (src, score, t_sec) in enumerate(sorted_bank, 1):
            if os.path.exists(src):
                img = cv2.imread(src)
                if img is not None:
                    
                    if "video_tag" in wm_type:
                        img = self._wm_visual(img, video_idx)
                    
                    if 'temporal_tag' in wm_type:
                        # Use passed duration directly
                        img = self._wm_temporal(img, video_idx, t_sec)
                    
                    dst = os.path.join(output_dir, f"watermarked_{i}.jpg")
                    cv2.imwrite(dst, img)
                    watermarked_paths.append((dst, score))
                    # Keep track of time for trans sequence if needed (though transition usually doesn't need time)
                    processed_frames_with_time.append((dst, score, t_sec))

        # 2. Add transition frame if needed
        # Special case for 'trans' because it changes the list structure (adds frames)
        if 'trans_frame' in wm_type:
            # Pass the already processed (watermarked) frames effectively
            return self._wm_trans_sequence(processed_frames_with_time, video_idx, output_dir)
                    
        return watermarked_paths
