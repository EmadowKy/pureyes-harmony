export class TextChunk {
  content: string = '';
  isBold: boolean = false;
  isTimestamp: boolean = false;
  videoNum: number = 0;
  timeStr: string = '';
}

export function timeToSeconds(timeStr: string): number {
  if (!timeStr) {
    return 0;
  }
  const parts = timeStr.split(':').map(x => parseInt(x) || 0);
  if (parts.length === 2) {
    return parts[0] * 60 + parts[1];
  } else if (parts.length === 3) {
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  }
  return 0;
}

export function parseAnswerToChunks(answerText: string): Array<Array<TextChunk>> {
  if (!answerText) {
    return [];
  }
  const paragraphs = answerText.split('\n');
  const result: Array<Array<TextChunk>> = [];
  const tsRegex = /\[video:\s*["']?([^"',\]]+)["']?\s*,\s*time:\s*["']?([^"',\s\]\*]+)["']?\]?/g;
  const boldRegex = /\*\*([^*]+)\*\*/g;

  for (let i = 0; i < paragraphs.length; i++) {
    let paraText = paragraphs[i];
    if (!paraText) {
      const emptyChunk = new TextChunk();
      emptyChunk.content = '';
      result.push([emptyChunk]);
      continue;
    }

    let isBullet = false;
    const bulletMatch = paraText.match(/^(\s*[*•-]\s+)/);
    if (bulletMatch) {
      isBullet = true;
      paraText = paraText.substring(bulletMatch[0].length);
    }

    const paraChunks: Array<TextChunk> = [];

    // Phase 1: Parse bold first
    const boldChunks: Array<Record<string, Object>> = [];
    let lastIdx = 0;
    let boldMatch: RegExpExecArray | null = null;
    boldRegex.lastIndex = 0;

    while ((boldMatch = boldRegex.exec(paraText)) !== null) {
      if (boldMatch.index > lastIdx) {
        boldChunks.push({
          "content": paraText.substring(lastIdx, boldMatch.index),
          "isBold": false
        });
      }
      boldChunks.push({
        "content": boldMatch[1],
        "isBold": true
      });
      lastIdx = boldRegex.lastIndex;
    }

    if (lastIdx < paraText.length) {
      boldChunks.push({
        "content": paraText.substring(lastIdx),
        "isBold": false
      });
    }

    if (boldChunks.length === 0) {
      boldChunks.push({ "content": paraText, "isBold": false });
    }

    // Phase 2: For each bold chunk, parse timestamps
    let isFirst = true;
    for (let j = 0; j < boldChunks.length; j++) {
      const bc = boldChunks[j];
      const isBold = bc["isBold"] as boolean;
      const textToParse = bc["content"] as string;

      tsRegex.lastIndex = 0;
      let tsLastIdx = 0;
      let tsMatch: RegExpExecArray | null = null;

      while ((tsMatch = tsRegex.exec(textToParse)) !== null) {
        if (tsMatch.index > tsLastIdx) {
          let contentStr = textToParse.substring(tsLastIdx, tsMatch.index);
          if (isFirst && isBullet) {
            contentStr = "•  " + contentStr;
            isFirst = false;
          }
          const chunk = new TextChunk();
          chunk.content = contentStr;
          chunk.isBold = isBold;
          paraChunks.push(chunk);
        }

        const vNumStr = tsMatch[1].trim();
        const tStr = tsMatch[2].trim();

        let videoNum = parseInt(vNumStr);
        if (isNaN(videoNum)) {
          const code = vNumStr.toUpperCase().charCodeAt(0);
          if (code >= 65 && code <= 90) {
            videoNum = code - 65 + 1;
          } else {
            videoNum = 1;
          }
        }

        let contentStr = `视频${videoNum}(${tStr})`;
        if (isFirst && isBullet) {
          contentStr = "•  " + contentStr;
          isFirst = false;
        }

        const chunk = new TextChunk();
        chunk.content = contentStr;
        chunk.isBold = isBold;
        chunk.isTimestamp = true;
        chunk.videoNum = videoNum;
        chunk.timeStr = tStr;
        paraChunks.push(chunk);

        tsLastIdx = tsRegex.lastIndex;
      }

      if (tsLastIdx < textToParse.length) {
        let contentStr = textToParse.substring(tsLastIdx);
        if (isFirst && isBullet) {
          contentStr = "•  " + contentStr;
          isFirst = false;
        }
        const chunk = new TextChunk();
        chunk.content = contentStr;
        chunk.isBold = isBold;
        paraChunks.push(chunk);
      }
    }

    result.push(paraChunks);
  }

  return result;
}

export function formatAnswerToPlainText(answerText: string): string {
  if (!answerText) {
    return '';
  }
  const tsRegex = /\[video:\s*["']?([^"',\]]+)["']?\s*,\s*time:\s*["']?([^"',\s\]\*]+)["']?\]?/g;
  let formatted = answerText.replace(tsRegex, (match: string, vNumStr: string, tStr: string): string => {
    let videoNum = parseInt(vNumStr.trim());
    if (isNaN(videoNum)) {
      const code = vNumStr.trim().toUpperCase().charCodeAt(0);
      if (code >= 65 && code <= 90) {
        videoNum = code - 65 + 1;
      } else {
        videoNum = 1;
      }
    }
    return `视频${videoNum}(${tStr.trim()})`;
  });

  const lines = formatted.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const bulletMatch = lines[i].match(/^(\s*[*•-]\s+)/);
    if (bulletMatch) {
      lines[i] = "•  " + lines[i].substring(bulletMatch[0].length);
    }
  }
  formatted = lines.join('\n');
  formatted = formatted.replace(/\*\*([^*]+)\*\*/g, '$1');
  return formatted;
}


