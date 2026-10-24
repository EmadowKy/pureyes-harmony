export function timelineTick(epoch: number, granularity: string): string {
  if (!Number.isFinite(epoch) || epoch <= 0) return '';
  const date = new Date(epoch * 1000);
  const pad = (value: number): string => value.toString().padStart(2, '0');
  if (granularity === 'day') return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  const time = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  return granularity === 'second' ? `${time}:${pad(date.getSeconds())}` : time;
}

export function replayClock(startEpoch: number, offsetSeconds: number, endEpoch: number): number {
  if (!Number.isFinite(startEpoch) || startEpoch <= 0 ||
      !Number.isFinite(offsetSeconds) || offsetSeconds < 0) return 0;
  const epoch = Math.floor(startEpoch + offsetSeconds);
  return endEpoch > startEpoch ? Math.min(epoch, endEpoch) : epoch;
}
