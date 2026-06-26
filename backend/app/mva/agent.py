import os
import cv2
import numpy as np
from PIL import Image
import re
from typing import List, Dict, Tuple, Any
import time

class ToolAgent:
    def __init__(self, model, processor, config, device_id):
        self.model = model
        self.processor = processor
        self.config = config
        self.device_id = device_id

    def Qwen_VL(self, messages, max_tokens=512):
        from utils import Qwen_VL
        return Qwen_VL(messages, self.device_id, self.config['models']['main_model_path'], max_tokens)

    def decide_action(self, question: str, frame_bank: List[Tuple[str, float, float]], current_frames_info: List[dict], video_duration: float, video_label: str = "ONE of the videos", current_video_desc: str = "", other_videos_desc: Dict[str, str] = {}, options_text: str = "", question_analysis: str = "") -> Tuple[List[float], int, float, float]:
        """
        Score newly sampled frames (current_frames_info) AND decide the next sampling action in one go.
        
        frame_bank: [(path, old_score, time), ...] - The accumulated best frames (Already scored). used for context.
        current_frames_info: [{'path': str, 'time': float}, ...] - The frames from the LAST action (current receptive field), which need SCORING.
        
        Returns: (scores_for_current_frames, option_id, target_start, target_end)
        """
        # Prepare inputs
        # 1. We want to score `current_frames_info`. So we must show these images.
        # 2. We use `frame_bank` as context (maybe text or limit images?). 
        #    To save tokens/complexity, we might just list the frame bank timestamps for context, 
        #    since `current_frames_info` are the ones needing visual evaluation.
        
        current_paths = [x['path'] for x in current_frames_info]
        bank_paths = [x[0] for x in frame_bank] # Optional: visual context from bank? 
        # If we include ALL bank images + current images, it might be too many (16+8=24).
        # Strategy: Show CURRENT frames visually. Describe BANK frames textually (or skip visual context of bank if valid).
        # Considering the user wants to score the *new* frames, let's focus on them.
        
        start_time = 0.0
        end_time = video_duration
        if current_frames_info:
            start_time = current_frames_info[0]['time']
            end_time = current_frames_info[-1]['time']
            
        is_global = (end_time - start_time) >= video_duration * 0.9

        prompt_template = self.config['prompts'].get('tool_combined_action')
        
        # Build text context for the frame bank
        bank_context_str = "None"
        if frame_bank:
            bank_times = [f"{x[2]:.2f}s(Score:{x[1]:.2f})" for x in frame_bank]
            bank_context_str = ", ".join(bank_times)

        # Format other videos description
        other_videos_str = "\n".join([f"{k}: {v}" for k, v in other_videos_desc.items() if v])
        if not other_videos_str:
            other_videos_str = "None"

        prompt = prompt_template.replace("{QUESTION}", question) \
                                .replace("{VIDEO_LABEL}", video_label) \
                                .replace("{START_TIME}", f"{start_time:.2f}") \
                                .replace("{END_TIME}", f"{end_time:.2f}") \
                                .replace("{DURATION}", f"{video_duration:.2f}") \
                                .replace("{NUM_FRAMES}", str(len(current_paths))) \
                                .replace("{IS_GLOBAL}", str(is_global)) \
                                .replace("{CURRENT_VIDEO_DESC}", current_video_desc) \
                                .replace("{OTHER_VIDEOS_DESC}", other_videos_str) \
                                .replace("{OPTIONS}", options_text) \
                                .replace("{QUESTION_ANALYSIS}", question_analysis)
        content = []
        if self.config['parameters'].get('print_output', False):
            print("============Tool Agent Prompt===========")
            print(f"Question: {question}")
            print(f"Options: {options_text}")
            print(f"Question Analysis: {question_analysis}")
            print(f"Video Label: {video_label}")
            print(f"Start Time: {start_time:.2f}")
            print(f"End Time: {end_time:.2f}")
            print(f"Duration: {video_duration:.2f}")
            print(f"Number of Current Frames: {len(current_paths)}")
            print(f"Current Video Description: {current_video_desc}")
            print(f"Other Videos Description: {other_videos_str}")
            print("============Tool Agent Current Frame for Scoring===========")
        # Add visual content ONLY for current frames (to score them)
        for f in current_paths:
            content.append({"type": "image", "image": f})
            if self.config['parameters'].get('print_output', False):
                print(f)
        content.append({"type": "text", "text": prompt})
        
        messages = [{"role": "user", "content": content}]
        output = self.Qwen_VL(messages, max_tokens=256)
        if self.config['parameters'].get('print_output', False):
            print("============Tool Agent Output===========")
            print(output)
        # Parse Scores
        scores = []
        score_line_match = re.search(r'Scores:\s*([0-9\.\s]+)', output)
        if score_line_match:
            raw_scores = score_line_match.group(1).strip()
            matches = re.findall(r'\b(0\.\d+|1\.00?|0)\b', raw_scores)
            for m in matches:
                try:
                    scores.append(float(m))
                except: pass
        
        # Pad/Truncate scores
        while len(scores) < len(current_paths):
            scores.append(0.5) # Default neutral score if missing
        scores = scores[:len(current_paths)]
        
        # Parse Decision
        option = 5
        target_start = 0.0
        target_end = video_duration
        
        decision_line_match = re.search(r'Decision:.*', output)
        if decision_line_match:
            decision_text = decision_line_match.group(0)
            
            opt_match = re.search(r'Option\s*(\d)', decision_text)
            if opt_match:
                option = int(opt_match.group(1))
                
            # Improved regex to handle various separators (comma, space, hyphen) and optional brackets
            range_match = re.search(r'Range:.*?([\d\.]+)[,\s\-]+([\d\.]+)', decision_text)
            if range_match:
                target_start = float(range_match.group(1))
                target_end = float(range_match.group(2))
        
        if option in [3, 4] and not is_global:
            option = 1
        
        if self.config['parameters'].get('print_output', False):
            print("\n=============Parsed Description and Status============")
            print(f"Parsed Scores: {scores}")
            print(f"Parsed Option: {option}")
            print(f"Parsed Target Start: {target_start}")
            print(f"Parsed Target End: {target_end}")
            
        return scores, option, target_start, target_end




class DescAgent:
    def __init__(self, model, processor, config, device_id):
        self.model = model
        self.processor = processor
        self.config = config
        self.device_id = device_id

    def Qwen_VL(self, messages, max_tokens=4096):
        from utils import Qwen_VL
        return Qwen_VL(messages, self.device_id, self.config['models']['main_model_path'], max_tokens)

    def describe_and_evaluate(self, question: str, frames: List[str], desc_old: str, other_descs: Dict[str, str], video_duration: float, video_label: str = "ONE of the videos", options_text: str = "", question_analysis: str = "") -> Tuple[str, float, bool, bool]:
        """
        Generate a description from frames AND evaluate status (score, termination) in one go.
        frames: New frames to describe.
        desc_old: The accumulated description.
        other_descs: Descriptions of other videos.
        
        Returns: (desc_new_part, score_new, video_terminated, global_terminated)
        """
        other_descs_text = "\n".join([f"{k}: {v}" for k, v in other_descs.items() if v])
        
        prompt_template = self.config['prompts'].get('desc_combined_action')
        # If no template, use default

        prompt = prompt_template.replace("{QUESTION}", question) \
                                .replace("{VIDEO_LABEL}", video_label) \
                                .replace("{DURATION}", f"{video_duration:.2f}") \
                                .replace("{DESC_OLD}", desc_old) \
                                .replace("{OTHER_DESCS_TEXT}", other_descs_text) \
                                .replace("{OPTIONS}", options_text) \
                                .replace("{QUESTION_ANALYSIS}", question_analysis)

        content = []
        if self.config['parameters'].get('print_output', False):
            print("============Desc Agent Prompt===========")
            print(f"Question: {question}")
            print(f"Options: {options_text}")
            print(f"Question Analysis: {question_analysis}")
            print(f"Video label: {video_label}")
            print(f"Old Description: {desc_old}")
            print(f"Other Videos Description: {other_descs_text}")
            print("============Desc Agent Frame for Description===========")

        for f in frames:
            content.append({"type": "image", "image": f})
            if self.config['parameters'].get('print_output', False):
                print(f)
        content.append({"type": "text", "text": prompt})
        
        messages = [{"role": "user", "content": content}]
        output = self.Qwen_VL(messages, max_tokens=384)
        if self.config['parameters'].get('print_output', False):
            print("============Desc Agent Output===========")
            print(output)
        
        desc_new = "No new description."
        score_new = 0.5
        video_terminated = False
        global_terminated = False
        
        # Parse Description (Support both "New Description" and "New Evidence")
        desc_match = re.search(r'(New Description|New Evidence):\s*(.*?)---', output, re.DOTALL | re.IGNORECASE)
        if desc_match:
            desc_new = desc_match.group(2).strip()
        else:
            # Fallback if separator missing
            desc_match = re.search(r'(New Description|New Evidence):\s*(.*)', output, re.DOTALL | re.IGNORECASE)
            if desc_match:
                # Be careful not to include Score line
                all_text = desc_match.group(2)
                score_idx = all_text.find("Score:")
                if score_idx != -1:
                    desc_new = all_text[:score_idx].strip()
                else:
                    desc_new = all_text.strip()
                    
        # Parse Status
        score_match = re.search(r'Score:\s*(0\.\d+|1\.00?|0)', output)
        if score_match:
            try:
                score_new = float(score_match.group(1))
            except: pass
            
        v_term_match = re.search(r'Video Terminated:\s*(True|False)', output, re.IGNORECASE)
        if v_term_match:
            video_terminated = v_term_match.group(1).lower() == 'true'
            
        g_term_match = re.search(r'Global Terminated:\s*(True|False)', output, re.IGNORECASE)
        if g_term_match:
            global_terminated = g_term_match.group(1).lower() == 'true'

        if self.config['parameters'].get('print_output', False):
            print("\n=============Parsed Description and Status============")
            print(f"Parsed Description: {desc_new}")
            print(f"Parsed Score: {score_new}")
            print(f"Parsed Video Terminated: {video_terminated}")
            print(f"Parsed Global Terminated: {global_terminated}")
            
        return desc_new, score_new, video_terminated, global_terminated
        