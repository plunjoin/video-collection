export interface StoryBookmark {
  videoId: number;
  videoName: string;
  episodeName: string;
  episodeIndex: number;
  routeIndex: number;
  currentTime: number;
  duration: number;
  updatedAt: number;
}

export function readLatestBookmark(): StoryBookmark | null {
  try {
    const value = JSON.parse(localStorage.getItem('bllii_story_bookmark') || 'null');
    if (!value || !Number.isInteger(value.videoId) || value.videoId <= 0 || typeof value.videoName !== 'string' || typeof value.episodeName !== 'string') return null;
    if (![value.episodeIndex, value.routeIndex].every(n => Number.isInteger(n) && n >= 0)) return null;
    if (![value.currentTime, value.duration, value.updatedAt].every(n => typeof n === 'number' && Number.isFinite(n) && n >= 0)) return null;
    return value;
  } catch { return null; }
}
