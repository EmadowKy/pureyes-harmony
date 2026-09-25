"""Bounded, source-linked evidence cards for multi-video investigations."""

import math
import re


def _timestamp(value):
    if isinstance(value, str):
        try:
            parts = [float(part) for part in value.strip().split(":")]
            if 1 <= len(parts) <= 3 and all(0 <= part < 60 for part in parts[-2:]):
                value = sum(part * (60 ** offset) for offset, part in enumerate(reversed(parts)))
        except (TypeError, ValueError):
            return None
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        return None
    return round(float(value), 2)


def cards_from_result(tool_name, result, video_items, selected_video=None, query_text=""):
    """Store tool observations as candidates, never as confirmed conclusions."""
    if not isinstance(result, dict) or result.get("error") or result.get("available") is False:
        return []
    by_segment = {item.get("meta", {}).get("id"): (i, item)
                  for i, item in enumerate(video_items, 1)
                  if item.get("meta", {}).get("id") is not None}
    by_video = {item["video_id"]: (i, item) for i, item in enumerate(video_items, 1)}
    cards = []
    if tool_name == "search_visual_semantics_batch":
        for entry in result.get("results") or []:
            if not isinstance(entry, dict):
                continue
            cards.extend(cards_from_result("search_visual_semantics", entry.get("result"),
                                           video_items, selected_video,
                                           str(entry.get("query") or query_text)))
        return cards[:6]
    if tool_name == "search_face_tracks":
        for group in result.get("matched_face_groups") or []:
            for occurrence in group.get("occurrences") or []:
                match = by_segment.get(occurrence.get("segment_id"))
                seconds = _timestamp(occurrence.get("timestamp_sec", occurrence.get("start_time")))
                if match and seconds is not None:
                    i, item = match
                    cards.append(_card(i, item, seconds, tool_name,
                                       f"人脸分组 {str(group.get('face_group_name') or '')[:60]} 出现"))
    elif selected_video and tool_name not in ("read_frame_image", "read_frames"):
        match = by_video.get(selected_video.get("video_id"))
        if not match:
            return []
        i, item = match
        samples = result.get("matches") or result.get("sampled_results") or []
        if len(samples) > 6:
            samples = [samples[int(p * (len(samples) - 1) / 5)] for p in range(6)]
        for sample in samples:
            if not isinstance(sample, dict):
                continue
            seconds = _timestamp(sample.get("timestamp_sec"))
            if seconds is None:
                continue
            if tool_name == "search_video_text":
                detail = f"OCR 候选文字：{str(sample.get('text') or '')[:140]}"
            elif tool_name == "search_visual_semantics":
                detail = f"画面语义候选（查询：{str(query_text)[:70]}）：{str(sample.get('class_name') or '场景')[:70]}"
            else:
                detail = f"索引目标 {str(sample.get('class_name') or '')[:60]}，轨迹 {str(sample.get('track_id') or '')[:60]}"
            cards.append(_card(i, item, seconds, tool_name, detail))
    return cards[:6]


def frame_card(video_items, video_id, timestamp_sec, description):
    seconds = _timestamp(timestamp_sec)
    if seconds is None or not isinstance(description, str) or not description.strip():
        return None
    for i, item in enumerate(video_items, 1):
        if item["video_id"] == video_id:
            return _card(i, item, seconds, "read_frame_image", description.strip()[:180], "frame_description")
    return None


def frame_cards_from_text(text, video_items, read_frames):
    """Accept model observations only when tied to an actually-read video frame."""
    allowed = {(item["video_id"], round(float(item["timestamp_sec"]), 2))
               for item in read_frames if isinstance(item, dict)
               and isinstance(item.get("video_id"), str)
               and type(item.get("timestamp_sec")) in (int, float)}
    cards, consumed = [], set()
    pattern = re.compile(r"^\s*FRAME_OBSERVATION\s+(\S+)\s+([0-9]+(?:\.[0-9]+)?)\s*:\s*(.+?)\s*$")
    lines = (text or "").splitlines()
    cleaned = []
    for line in lines:
        match = pattern.match(line)
        if not match:
            cleaned.append(line)
            continue
        video_id, timestamp, description = match.groups()
        key = (video_id, round(float(timestamp), 2))
        if key not in allowed or key in consumed:
            cleaned.append(line)
            continue
        card = frame_card(video_items, video_id, key[1], description)
        if card:
            cards.append(card)
            consumed.add(key)
    return cards, "\n".join(cleaned).strip()


def _card(index, item, seconds, source, detail, kind="index_candidate"):
    return {"video_index": index, "video_id": item["video_id"],
            "segment_id": item.get("meta", {}).get("id"), "timestamp_sec": seconds,
            "source": source, "kind": kind, "description": detail}


def select_memory(cards, question, limit=18):
    terms = set(re.findall(r"[a-z0-9]+|[\u4e00-\u9fff]{2}", (question or "").lower()))
    scored = []
    for card in cards:
        if not isinstance(card, dict) or _timestamp(card.get("timestamp_sec")) is None:
            continue
        description = str(card.get("description") or "")
        if description and card.get("video_id"):
            relevance = sum(term in f"{description} {card.get('question', '')}".lower() for term in terms)
            scored.append((relevance, card.get("turn_index", 0), card))
    scored.sort(key=lambda row: (row[0], row[1]), reverse=True)
    selected, seen, counts = [], set(), {}
    for _, _, card in scored:
        vid = card["video_id"]
        key = (vid, card["timestamp_sec"], card.get("source"), card["description"])
        if key in seen or counts.get(vid, 0) >= 5:
            continue
        seen.add(key); counts[vid] = counts.get(vid, 0) + 1; selected.append(card)
        if len(selected) >= limit:
            break
    return sorted(selected, key=lambda c: (c.get("video_index", 0), c["timestamp_sec"]))


def format_memory(cards, max_chars=4800):
    if not cards:
        return ""
    lines = ["【调查证据记忆：按视频归档的候选观察，不等于最终事实】"]
    current = None
    for card in cards:
        video = (card.get("video_index"), card["video_id"])
        if video != current:
            header = f"视频 {video[0]} ({video[1]})："
            if sum(map(len, lines)) + len(header) > max_chars:
                break
            lines.append(header); current = video
        label = "单帧视觉描述，需复核" if card.get("kind") == "frame_description" else "索引候选，需画面核验"
        line = (f"- {card['timestamp_sec']:.2f}s [{card['source']}; {label}; "
                f"第 {card.get('turn_index', '?')} 轮] {card['description'][:180]}")
        if sum(map(len, lines)) + len(line) > max_chars:
            break
        lines.append(line)
    lines.append("仅将这些记录作为检索线索；跨视频同人或事件关联仍需对照画面核验。")
    return "\n".join(lines)
