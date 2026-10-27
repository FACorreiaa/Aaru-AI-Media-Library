import { describe, expect, it } from 'vitest'
import { mainVideo, seasonEpisode } from './dom'
import { readerFor, remembers } from './index'
import { readDisneyPlus } from './disneyplus'
import { readNetflix } from './netflix'
import { readPrimeVideo } from './primevideo'
import { readYouTube } from './youtube'

// Fixtures are the parts of each player these readers look at, as of 2026-10. Check them against
// the live sites when a reader stops matching.
const page = (html: string) =>
  new DOMParser().parseFromString(`<body>${html}</body>`, 'text/html')

describe('Netflix', () => {
  const url = new URL('https://www.netflix.com/watch/81434512?trackId=1')

  it('reads an episode from the title overlay', () => {
    const doc = page(
      '<div data-uia="video-title"><h4>Severance</h4><span>S2:E3</span><span>Who Is Alive?</span></div>',
    )
    expect(readNetflix(doc, url)).toEqual({
      source: 'netflix',
      ref: '81434512',
      type: 'show',
      title: 'Severance',
      season: 2,
      episode: 3,
      episodeTitle: 'Who Is Alive?',
    })
  })

  it('reads a limited series as season 1', () => {
    const doc = page(
      '<div data-uia="video-title"><h4>Baby Reindeer</h4><span>E3</span><span>Episode 3</span></div>',
    )
    expect(readNetflix(doc, url)).toMatchObject({ season: 1, episode: 3 })
  })

  it('reads a film, and nothing off the player or before the overlay shows', () => {
    const film = page('<div data-uia="video-title">Roma</div>')
    expect(readNetflix(film, url)).toEqual({
      source: 'netflix',
      ref: '81434512',
      type: 'movie',
      title: 'Roma',
    })
    expect(readNetflix(page(''), url)).toBeNull()
    expect(
      readNetflix(film, new URL('https://www.netflix.com/browse')),
    ).toBeNull()
  })
})

describe('Disney+', () => {
  it('reads an episode and a film, inside a shadow root too', () => {
    const doc = page('<div id="player"></div>')
    const host = doc.getElementById('player')!
    host.attachShadow({ mode: 'open' }).innerHTML =
      '<div class="title-field">Andor</div><div class="subtitle-field">S2:E4 Harvest</div>'
    expect(
      readDisneyPlus(doc, new URL('https://www.disneyplus.com/play/abc-123')),
    ).toEqual({
      source: 'disney_plus',
      ref: 'abc-123',
      type: 'show',
      title: 'Andor',
      season: 2,
      episode: 4,
      episodeTitle: 'Harvest',
    })
    expect(
      readDisneyPlus(
        page('<div class="title-field">Soul</div>'),
        new URL('https://www.disneyplus.com/en-gb/video/f00d'),
      ),
    ).toEqual({
      source: 'disney_plus',
      ref: 'f00d',
      type: 'movie',
      title: 'Soul',
    })
  })
})

describe('Prime Video', () => {
  it('reads an episode with its numbers in the ref, and a film', () => {
    const url = new URL('https://www.primevideo.com/detail/0ABCDEF/')
    const doc = page(
      '<h1 class="atvwebplayersdk-title-text">The Boys</h1><h2 class="atvwebplayersdk-subtitle-text">Season 4, Ep. 2 Life Among the Septics</h2>',
    )
    expect(readPrimeVideo(doc, url)).toEqual({
      source: 'prime_video',
      ref: '0ABCDEF:4:2',
      type: 'show',
      title: 'The Boys',
      season: 4,
      episode: 2,
      episodeTitle: 'Life Among the Septics',
    })
    const film = page('<h1 class="atvwebplayersdk-title-text">Air</h1>')
    expect(
      readPrimeVideo(
        film,
        new URL('https://www.amazon.co.uk/gp/video/detail/B0X1'),
      ),
    ).toMatchObject({ ref: 'B0X1', type: 'movie', title: 'Air' })
  })
})

describe('YouTube', () => {
  const url = new URL('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s')
  // jsdom loads no media: the main video's duration and position are set by hand.
  const watch = ({
    id = 'dQw4w9WgXcQ',
    player = 'html5-video-player',
    duration = 213,
    title = 'Never Gonna Give You Up',
    channel = 'Rick Astley',
  } = {}) => {
    const doc = page(
      `<ytd-watch-flexy video-id="${id}"><div id="movie_player" class="${player}"><video class="html5-main-video"></video></div><ytd-watch-metadata><h1><yt-formatted-string>${title}</yt-formatted-string></h1><ytd-video-owner-renderer><ytd-channel-name><a href="/@RickAstleyYT">${channel}</a></ytd-channel-name></ytd-video-owner-renderer></ytd-watch-metadata></ytd-watch-flexy>`,
    )
    const video = doc.querySelector('video')!
    Object.defineProperty(video, 'duration', { value: duration })
    Object.defineProperty(video, 'currentTime', { value: 42 })
    return doc
  }

  it('reads the video on a watch page, and its main video', () => {
    const doc = watch()
    expect(readYouTube(doc, url)).toEqual({
      source: 'youtube',
      ref: 'dQw4w9WgXcQ',
      type: 'video',
      title: 'Never Gonna Give You Up',
      channel: 'Rick Astley',
    })
    expect(mainVideo(doc)).toMatchObject({ duration: 213, currentTime: 42 })
  })

  it('reads nothing off a watch page, or before the page shows the URL’s video', () => {
    const doc = watch()
    expect(
      readYouTube(doc, new URL('https://www.youtube.com/shorts/dQw4w9WgXcQ')),
    ).toBeNull()
    expect(
      readYouTube(
        doc,
        new URL('https://music.youtube.com/watch?v=dQw4w9WgXcQ'),
      ),
    ).toBeNull()
    expect(
      readYouTube(doc, new URL('https://www.youtube.com/watch?v=short')),
    ).toBeNull()
    expect(readYouTube(watch({ id: 'oHg5SJYRHA0' }), url)).toBeNull()
  })

  it('says a Topic channel’s video is music: the channel is the artist (SCR-011)', () => {
    const topic = watch({
      title: 'Teardrop',
      channel: 'Massive Attack - Topic',
    })
    expect(readYouTube(topic, url)).toMatchObject({
      title: 'Teardrop',
      music: { artist: 'Massive Attack', track: 'Teardrop' },
    })
    expect(readYouTube(watch(), url)).not.toHaveProperty('music')
  })

  it('reads nothing while an ad plays, or on a live stream', () => {
    const ad = watch({ player: 'html5-video-player ad-showing' })
    expect(readYouTube(ad, url)).toBeNull()
    const live = watch({ player: 'html5-video-player ytp-live' })
    expect(readYouTube(live, url)).toBeNull()
    expect(readYouTube(watch({ duration: Infinity }), url)).toBeNull()
  })
})

describe('sites', () => {
  it('picks a reader by host', () => {
    expect(readerFor('www.netflix.com')).toBe(readNetflix)
    expect(readerFor('www.amazon.de')).toBe(readPrimeVideo)
    expect(readerFor('www.youtube.com')).toBe(readYouTube)
    expect(readerFor('music.youtube.com')).toBeNull()
  })

  it('remembers what an overlay showed, but not on YouTube', () => {
    expect(remembers(readNetflix)).toBe(true)
    expect(remembers(readYouTube)).toBe(false)
  })

  it('reads the season-and-episode shapes the sites use', () => {
    expect(seasonEpisode('S1:E2 Pilot')).toEqual({
      season: 1,
      episode: 2,
      rest: 'Pilot',
    })
    expect(seasonEpisode('Season 3 Episode 10')).toEqual({
      season: 3,
      episode: 10,
      rest: '',
    })
    expect(seasonEpisode('S2 E5 - Part Two')).toEqual({
      season: 2,
      episode: 5,
      rest: 'Part Two',
    })
    expect(seasonEpisode('Bonus feature')).toBeNull()
  })
})
