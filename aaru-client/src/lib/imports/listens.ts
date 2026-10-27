/** MUS-004: listening history files. They fill the listening log, never the library. */
export const LISTEN_FILE_SOURCES = [
  {
    source: 'spotify',
    label: 'Spotify',
    hint: 'Ask Spotify for your Extended streaming history (Account → Privacy). Unzip it and add one Streaming_History_Audio file at a time. Podcasts and plays under 30 s are left out.',
    accept: '.json,application/json',
  },
  {
    source: 'youtube',
    label: 'YouTube',
    hint: 'Google Takeout → YouTube and YouTube Music → history, in JSON. Add watch-history.json: YouTube Music plays and artist Topic channels come in, other videos are left out.',
    accept: '.json,application/json',
  },
] as const
