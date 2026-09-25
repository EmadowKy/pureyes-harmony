"""Question-specific exploration priorities; ratings are planning hints only."""

import json
import math


class VideoPriorities:
    def __init__(self, video_items):
        self.entries = [{"index": i, "video_id": item["video_id"], "relevance": 0.5,
                         "evidence": 0.0, "explored": False}
                        for i, item in enumerate(video_items, 1)]

    def update(self, ratings):
        if isinstance(ratings, str):
            try:
                ratings = json.loads(ratings)
            except (ValueError, TypeError):
                return
        if isinstance(ratings, dict):
            ratings = ratings.get("video_scores")
        if not isinstance(ratings, list):
            return
        for rating in ratings:
            if not isinstance(rating, dict):
                continue
            index = rating.get("video_index")
            if type(index) is not int or not 1 <= index <= len(self.entries):
                continue
            entry = self.entries[index - 1]
            for key in ("relevance", "evidence"):
                value = rating.get(key)
                if type(value) in (int, float) and math.isfinite(value) and 0 <= value <= 1:
                    if key != "evidence" or entry["explored"]:
                        entry[key] = float(value)

    def mark_explored(self, video_id):
        for entry in self.entries:
            if entry["video_id"] == video_id:
                entry["explored"] = True

    @staticmethod
    def priority(entry):
        return entry["relevance"] * (1 - entry["evidence"]) + (0.1 * entry["relevance"] if not entry["explored"] else 0)

    def guidance(self):
        if len(self.entries) < 2:
            return ""
        rows = sorted(self.entries, key=self.priority, reverse=True)
        text = ["【逐视频探索优先级（规划提示，不是事实证据）】"]
        for row in rows:
            text.append(f"视频 {row['index']} ({row['video_id']}): 相关性 {row['relevance']:.2f}，已有证据充分度 {row['evidence']:.2f}，{'已探索' if row['explored'] else '尚未探索'}，优先级 {self.priority(row):.2f}")
        text.append("分数仅用于安排探索顺序，不代替画面证据；必要时可调整顺序。")
        return "\n".join(text)
