export class InvestigationLayout {
  mode: string = 'compact';
  evidenceWidth: number = 0;
  resourceWidth: number = 0;
  playerHeight: number = 0;
}

// Widths are the actual content area in vp, including split-screen resizing.
export function investigationLayout(width: number, height: number): InvestigationLayout {
  const result = new InvestigationLayout();
  if (!Number.isFinite(width) || width < 840) return result;
  result.mode = width >= 1180 ? 'expanded' : 'split';
  result.resourceWidth = result.mode === 'expanded' ? 208 : 0;
  const chatWidth = Math.max(400, Math.min(600, Math.round(width * 0.43)));
  result.evidenceWidth = width - chatWidth;
  const videoWidth = result.evidenceWidth - result.resourceWidth - 32;
  const availableHeight = Number.isFinite(height) && height > 0 ? height : 600;
  result.playerHeight = Math.max(120, Math.min(videoWidth * 9 / 16, availableHeight * 0.48));
  return result;
}

export class InvestigationClip {
  id: number = 0;
  title: string = '';
  videoName: string = '';
  mediaUrl: string = '';
  thumbnailUrl: string = '';
  duration: number = 0;
}

export class InvestigationFocus {
  segmentId: number = 0;
  seconds: number = 0;
  revision: number = 0;
}

export class InvestigationEvidenceMark {
  segmentId: number = 0;
  seconds: number = 0;
  label: string = '';
}

export function evidenceFocus(clips: Array<InvestigationClip>, segmentId: number,
  seconds: number, revision: number): InvestigationFocus | undefined {
  const clip = clips.find((item: InvestigationClip): boolean => item.id === segmentId);
  if (!clip || !clip.mediaUrl || !Number.isFinite(seconds) || seconds < 0) return undefined;
  const focus = new InvestigationFocus();
  focus.segmentId = segmentId;
  focus.seconds = clip.duration > 0 ? Math.min(seconds, clip.duration) : seconds;
  focus.revision = revision + 1;
  return focus;
}

export function evidenceMarks(marks: Array<InvestigationEvidenceMark>,
  clips: Array<InvestigationClip>): Array<InvestigationEvidenceMark> {
  const seen = new Set<string>();
  return marks.filter((mark: InvestigationEvidenceMark): boolean => {
    if (!Number.isFinite(mark.seconds) || mark.seconds < 0 ||
      !clips.some((clip: InvestigationClip): boolean => clip.id === mark.segmentId)) return false;
    const key = `${mark.segmentId}:${Math.round(mark.seconds * 1000)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, 200);
}

export class InvestigationFace {
  id: number = 0;
  name: string = '';
  imageUrl: string = '';
  count: number = 0;
}

export class InvestigationFaceRecord {
  id: number = 0;
  segmentId: number = 0;
  seconds: number = 0;
  imageUrl: string = '';
}

export function faceRecordsForClip(raw: Array<Record<string, Object>>,
  segmentId: number): Array<InvestigationFaceRecord> {
  return raw.filter((item: Record<string, Object>): boolean => item['segment_id'] === segmentId)
    .map((item: Record<string, Object>): InvestigationFaceRecord => {
      const record = new InvestigationFaceRecord();
      record.id = item['id'] as number;
      record.segmentId = segmentId;
      const seconds = item['start_time_offset'] as number;
      record.seconds = Number.isFinite(seconds) && seconds >= 0 ? seconds : 0;
      record.imageUrl = (item['crop_url'] as string) || '';
      return record;
    });
}
