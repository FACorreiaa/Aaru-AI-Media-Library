# App Store Connect: privacy label and age rating (REL-007)

_Checked against the code and Apple's pages on 13 November 2026._

A fill-in sheet for the two questionnaires App Store Connect asks before 1.0, in the order the
site asks them. Every answer has its evidence. `docs/privacy.md` is the source of truth for what
Aaru collects; `aaru-ios/Aaru/PrivacyInfo.xcprivacy` declares the same types, and the three must
agree. When Aaru starts collecting something new, change `docs/privacy.md` first, then the
manifest, then this sheet, then the label in App Store Connect.

The label covers the iPhone, iPad and Mac app (one record). It describes what the app sends to
Aaru's server and what the server and its processors keep, not only what the binary stores.

Apple's definitions used here
([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)):

- **Collect**: "transmitting data off the device in a way that allows you and/or your
  third-party partners to access it for a period longer than what is necessary to service the
  transmitted request in real time." Data processed only on the device is not collected.
- **Linked**: tied to the user's identity through their account, device or other details.
  Everything Aaru keeps under an account is linked.
- **Tracking**: linking data with third-party data for advertising, or sharing it with a data
  broker. Aaru does neither.

## Part A: App Privacy

### First questions

| Question | Answer | Why |
| --- | --- | --- |
| Do you or your third-party partners collect data from this app? | **Yes** | An account, a library, and the rest below |
| Is any of it used to track the user? | **No**, for every type | No ad SDK, no IDFA, no `AppTrackingTransparency`, no `AdSupport`, no data broker. The only third-party SDK in the app is Sentry (`Package.resolved`), whose own manifest declares no tracking. `NSPrivacyTracking` is `false` in both manifests |
| Privacy policy URL | `https://aaruapp.com/privacy` | Renders `docs/privacy.md` |

### Data types

For every "yes" the tracking answer is **No**. Purposes use Apple's names.

| Apple's data type | Collected? | Purposes | Linked to identity | Evidence |
| --- | --- | --- | --- | --- |
| **Contact Info** | | | | |
| Name | **Yes** | App Functionality | Yes | First and last name if given, `users.first_name/last_name`; privacy.md "Your account" |
| Email Address | **Yes** | App Functionality | Yes | Sign-in email, sent to Resend for the sign-in mail; privacy.md "Your account", "Your email" |
| Phone Number | No | | | Never asked for (phone matching is out of scope, CLAUDE.md) |
| Physical Address | No | | | Never asked for |
| Other User Contact Info | No | | | |
| **Health & Fitness** | | | | |
| Health | No | | | No HealthKit |
| Fitness | No | | | |
| **Financial Info** | | | | |
| Payment Info | No | | | Apple takes the payment; Aaru never sees a card (privacy.md "Aaru Plus") |
| Credit Info | No | | | |
| Other Financial Info | No | | | |
| **Location** | | | | |
| Precise Location | No | | | `NSLocationDefaultAccuracyReduced` is on, and `ConcertPoint` rounds to two decimals on the device before anything is sent (`aaru-ios/Aaru/Discover/ConcertTypes.swift`). Two decimals is below Apple's line of three |
| Coarse Location | **Yes** | App Functionality | Yes | The saved "Concerts near" city with its rounded position, `concert_places`; privacy.md "Concerts". "Use my location" alone is not stored and would not count |
| **Sensitive Info** | No | | | Aaru asks for none. See Part C, item 7 |
| **Contacts** | **Yes** | App Functionality | Yes | Friends, pending requests, blocks and group membership (`social_friendships`, `social_friend_requests`, `social_blocks`, `group_members`). Apple's definition names "social graph". The device address book is never read (no `Contacts` framework). See the reading below |
| **User Content** | | | | |
| Emails or Text Messages | **Yes** | App Functionality | Yes | Group messages, stored readable (`group_messages`); privacy.md "Groups". The last 30 go to Anthropic when someone tags @aaru |
| Photos or Videos | **Yes** | App Functionality | Yes | The profile photo (`avatars`, kept); pictures sent to capture or attached to a chat (`capture_images`, `chat_attachments`, up to an hour, read by Anthropic); privacy.md "Your photo", "Capture", "Files in a chat" |
| Audio Data | **No** | | | See the reading below |
| Gameplay Content | No | | | Not a game. Points, streaks and badges are counted under Other User Content and Product Interaction |
| Customer Support | No | | | No in-app support form; "Contact" opens Mail |
| Other User Content | **Yes** | App Functionality, Product Personalization | Yes | Library, status, ratings, notes, progress, lists, shelves, favorites, imports, listens, Board posts and comments, reactions, recommendations, chats with Aaru and the text and files sent to it, reports, followed sports; privacy.md "What Aaru stores". Personalization: the Tonight strip is built from the library and the user's answers |
| **Browsing History** | No | | | The app has no browser and reads no other app. See Part C, item 6 |
| **Search History** | **Yes** | App Functionality | **No** | Only this: a concert search by artist name is cached with its results for a few hours, shared and tied to nobody (privacy.md "Concerts"; `internal/concerts`). Title searches are forwarded to the catalog and not kept; there is no per-user search table and request logs hold the route only. Declared because a cache outlives the request |
| **Identifiers** | | | | |
| User ID | **Yes** | App Functionality, Analytics | Yes | The account id, the handle, and the sign-in provider's identifier. The server's PostHog events are keyed by the account id (`internal/telemetry/posthog.go`) |
| Device ID | **Yes** | App Functionality | Yes | The APNs device token and Live Activity tokens, kept with the account (`apns_devices`, `live_activity_tokens`); privacy.md "Notifications". No IDFA, no `identifierForVendor`. Declared because a push token is a device-level id kept with an account |
| **Purchases** | | | | |
| Purchase History | **Yes** | App Functionality | Yes | Apple's signed subscription record (`entitlements`); privacy.md "Aaru Plus". Plus is off sale (BIL-005), so 1.0 collects none in practice. It is declared because the purchase code ships in the binary (`aaru-ios/Aaru/Plus`) and starts working the moment a product exists in App Store Connect, with no app update to change the label in |
| **Usage Data** | | | | |
| Product Interaction | **Yes** | Analytics, Product Personalization | Yes | The server's product counts sent to PostHog under the account id (privacy.md "Product counts"); the Tonight picks shown, started, and answered (`tonight_picks`, `tonight_feedback`). The app holds no analytics SDK |
| Advertising Data | No | | | No ads |
| Other Usage Data | No | | | |
| **Diagnostics** | | | | |
| Crash Data | **Yes** | App Functionality | No | Sentry; `beforeSend` removes the user, the request and the breadcrumbs (`aaru-ios/Aaru/CrashReporting.swift`); privacy.md "Error reports" |
| Performance Data | **Yes** | App Functionality | No | Sentry app hang reports (`enableAppHangTracking = true`). Tracing is off (`tracesSampleRate = 0`) |
| Other Diagnostic Data | **Yes** | App Functionality | No | Sentry error reports; server request logs and counts to Grafana Cloud, which hold no account id (privacy.md "Server logs and health") |
| **Surroundings** | | | | |
| Environment Scanning | No | | | The 3D owl uses RealityKit to draw a model, with no camera and no scene understanding |
| **Body** | | | | |
| Hands | No | | | |
| Head | No | | | |
| **Other Data** | | | | |
| Other Data Types | **Yes** | App Functionality | Yes | The device's time zone, sent with each request (`aaru-api/.../TimeZoneMiddleware.swift`) and kept with points and streak days (privacy.md "Points, streaks and badges"); the country chosen for Sports' "Where to watch" |

Sixteen types are "yes": Name, Email Address, Coarse Location, Contacts, Emails or Text
Messages, Photos or Videos, Other User Content, Search History, User ID, Device ID, Purchase
History, Product Interaction, Crash Data, Performance Data, Other Diagnostic Data, Other Data
Types. The app's manifest declares exactly these.

### Readings that could go either way

- **Audio (not collected).** A spoken question is sent to Aaru's server, turned into text by
  the cluster's own Whisper, and dropped: `chatTranscribe` holds it in memory only
  (`aaru-server-v2/internal/httpapi/chat.go`), no table has an audio column, and no third party
  receives it. That is "servicing the request in real time", so by Apple's definition the audio
  is not collected. The words it becomes are kept as a chat turn and are declared under Other
  User Content. If the audio is ever stored, logged or sent to a hosted speech API, this
  becomes **Yes**, linked, App Functionality.
- **Contacts (collected).** Aaru never reads the address book, and many apps with friends do not
  tick Contacts. Apple's definition does say "social graph", and the friends list is one, so it
  is declared. The owner may read it the narrower way; the manifest then loses the entry too.
- **Search History (collected, not linked).** The narrow reading is "no": no search is kept
  against an account. The shared concert cache keeps a typed artist name for hours, so the
  cautious answer is yes, not linked.
- **Device ID (collected).** Apple's examples are the advertising id "or other device-level
  ID". A push token identifies one install on one device and is kept with the account.
- **Purchase History (collected).** Explained in the table. If the owner would rather the label
  describe 1.0 exactly, answer No now and change the label, and the manifest, in the release
  that puts Plus on sale. Do not forget that the switch is in App Store Connect, not in a build.

### What the manifests declare beyond data types

Required-reason APIs, from a search of `aaru-ios`, `aaru-core` and `aaru-api` for every API in
Apple's five categories. Codes checked against
[NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
and
[NSPrivacyAccessedAPITypeReasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).

| Category | App | Widgets | Reason | Where |
| --- | --- | --- | --- | --- |
| User defaults | **CA92.1** | not used | Read and write information only the app itself can access | `@AppStorage` in Calendar, Library and Appearance; `UserDefaults.standard` in `OnboardingGate`, `ReviewPrompter`, `PushRegistrar`, `AssistantModel`, `SessionStore` (Debug) |
| File timestamp | **C617.1** | **C617.1** | Timestamps of files inside the app container or app group container | `aaru-ios/Shared/NowPlayingArtwork.swift` sorts the Live Activity art by modification date to keep the newest dozen; `Shared/` compiles into both targets |
| System boot time | not used | not used | | No `systemUptime`, no `mach_absolute_time` |
| Disk space | not used | not used | | |
| Active keyboards | not used | not used | | |

The app and the widgets share data through files in the App Group container
(`Shared/WidgetSnapshot.swift`) and the keychain, never through an App Group defaults suite, so
1C8F.1 does not apply. Sentry uses user defaults, boot time and file timestamps itself and
declares them in its own manifest (CA92.1, 35F9.1, C617.1); an SDK's use is not repeated here.

## Part B: Age rating

The questionnaire as App Store Connect asks it since the 2025 change (4+, 9+, 13+, 16+, 18+),
from Apple's
[Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).
Capabilities and controls are yes or no; content descriptors are None, Infrequent or Frequent.
That page lists no question about AI or chatbots; if the site shows one, see the last row.

| Item | Answer | Why |
| --- | --- | --- |
| **In-app controls** | | |
| Parental Controls | **No** | None in the app |
| Age Assurance | **No** | No age check and no Declared Age Range API. The terms ask for 13 or older (`docs/terms.md`) |
| **Capabilities** | | |
| Unrestricted Web Access | **No** | No `WKWebView` and no in-app browser. Links (tickets, where to watch, terms, Discord) leave for Safari; `ASWebAuthenticationSession` opens only Google, Trakt and MyAnimeList sign-in |
| User-Generated Content | **Yes** | Board posts and comments, group messages, profile photos, names, notes on recommendations and share links. Friends-only, but still content from other people |
| Social Media | **Yes** | The Board is a stream of friends' posts with upvotes and comments, and friend activity takes reactions. No public feed and no discovery, but Apple's wording ("interaction with user-generated content through a social feed") fits. See Part C, item 3 |
| Social Media Disabled for Users Under 13 | **No** | Would need the Declared Age Range API before social features turn on; Aaru does not call it |
| Messaging and Chat | **Yes** | Group channels, and the one-to-one chat with Aaru |
| Advertising | **No** | None |
| **Mature themes** | | |
| Profanity or Crude Humor | **Infrequent** | Catalog titles and synopses, and what friends write |
| Horror/Fear Themes | **Infrequent** | Posters and synopses of horror films and shows |
| Alcohol, Tobacco, or Drug Use or References | **Infrequent** | Synopses and posters only |
| **Medical or wellness** | | |
| Medical or Treatment Information | **None** | |
| Health or Wellness Topics | **None** | |
| **Sexuality or nudity** | | |
| Mature or Suggestive Themes | **Infrequent** | Synopses mention crime, war and abuse; some posters and covers are suggestive. See Part C, item 2 |
| Sexual Content or Nudity | **Infrequent** | Poster and cover art of films rated for adults by age (not TMDB's "adult" class), album covers, book covers |
| Graphic Sexual Content and Nudity | **None**, once Part C item 1 is settled | TMDB calls send `include_adult=false`; AniList's Discover rows, manga search, first-run picks and credits send or filter `isAdult`. Anime search does not |
| **Violence** | | |
| Cartoon or Fantasy Violence | **Infrequent** | Poster art and synopses |
| Realistic Violence | **Infrequent** | Poster art and synopses |
| Prolonged Graphic or Sadistic Realistic Violence | **None** | Aaru plays no video; a poster is the most it shows |
| Guns or Other Weapons | **Infrequent** | Poster art |
| **Chance-based activities** | | |
| Gambling | **None** | No wagering. The Sports tab shows fixtures, scores and TV listings: no odds, no betting links |
| Simulated Gambling | **None** | Points are earned by tracking, never staked or spent |
| Contests | **Infrequent** | The weekly friends leaderboard ranks friends by points; it is opt-in and has no prize. Streaks and badges are personal goals. Not gambling |
| Loot Boxes | **None** | Nothing random is sold or awarded |
| **If asked about AI** | Say yes | The owl answers questions and @aaru posts in groups, written by Anthropic's model. A scope gate turns away questions that are not about media (`internal/agent/scope.go`) |

### Expected rating

**13+** on iOS 26, iPadOS 26 and macOS 26, and **12+** on earlier systems. Social Media alone
gives 13+; so do infrequent Sexual Content or Nudity and infrequent Realistic Violence, so the
rating holds even if the owner reads the Board as not social media. Regional ratings follow
from the same answers: 16+ in Australia, A16 in Brazil, 15+ in Korea and 16+ in Vietnam, all
because of Social Media.

Answering Frequent to Mature or Suggestive Themes would make it 16+. Answering anything but
None to Graphic Sexual Content makes the app Unrated, which the App Store does not publish.

## Part C: what makes an honest answer awkward

1. **Anime search does not hide adult works.** `AniList.Search`
   (`aaru-server-v2/internal/catalog/anilist.go`) adds `isAdult: false` for manga only. AniList
   returns adult anime when the filter is absent (checked: a search by one such title returned
   it), with its cover. MyAnimeList's read-back also asks for `nsfw=true`
   (`internal/mal/api.go`), so an adult entry on a user's own list comes across. Until anime
   search filters as manga search does, "Graphic Sexual Content: None" is not safely true.
   This is a code change and was left alone here.
2. **Books and albums have no filter at all.** Open Library and MusicBrainz / Cover Art Archive
   are shown as they come. Explicit covers exist in both. "Infrequent" is a fair answer; "None"
   would not be.
3. **Social Media: yes or no.** Aaru's rule is "no global feed, no public profile", and the
   Board is friends-only. Apple's question is about a feed of user content with interaction,
   and the Board is one. Yes costs nothing in the worldwide rating (13+ either way) and raises
   Australia, Brazil, Korea and Vietnam. No is defensible only if the owner is ready to argue it
   in review.
4. **User-generated content needs a filter (guideline 1.2).** Apple asks for four things:
   filtering objectionable material, reporting, blocking, and published contact details.
   Reporting (posts, group messages, people), blocking and a contact address exist. **A word
   filter exists since SOC-012 (2026-11-13):** the server refuses a short list of slurs, explicit
   sexual terms and threats in Board posts and comments, group messages, group and channel names
   and topics, recommendation and share-link notes, names and handles
   (`aaru-server-v2/internal/moderation`), on Aaru's own server, before anything is saved. Still
   open: it is English only and a word list, not a classifier; it does not look at photos
   (avatars); and it does not scan what was saved before it shipped. Review may still ask about
   photos.
5. **Sharing with a third-party AI needs explicit permission (guideline 5.1.2(i)).** The
   guideline now reads: "You must clearly disclose where personal data will be shared with third
   parties, including with third-party AI, and obtain explicit permission before doing so." The
   owl, capture and @aaru send the user's words, pictures and parts of their library to
   Anthropic. `docs/privacy.md` says so; the app never names Anthropic and asks no permission
   before the first question (no such string in `Localizable.xcstrings`). In a group, tagging
   @aaru also sends the other members' last 30 messages, which they did not send themselves.
6. **Browsing history, through other doors.** The browser extension, Stremio, Plex and Jellyfin
   report what the user plays elsewhere, and YouTube videos show in Now playing. None of it is
   collected by the iPhone or Mac app, so the label says No. The data is still in the account
   the app shows. The extension's own store listings need their own answers.
7. **Sensitive info by inference.** Aaru asks for nothing sensitive, but a library, a note or a
   chat can reveal beliefs, health or sexuality. The label says No because none is asked for or
   derived; `docs/privacy.md` is where a reader learns what is stored.
8. **No age check.** The terms say 13 or older and the rating will say 13+, but nothing in the
   app asks. With Social Media answered yes, a reviewer may ask how under-13s are kept out.
9. **Purchases declared while nothing is sold.** The label will list Purchases for an app with
   no in-app purchase. It is explained in Part A; a reviewer or a user may still ask.
10. **The label is longer than "private-first" suggests.** Sixteen types, twelve linked to
    identity. Every one is the account working as described, none is tracking, and the label
    has no way to say "only your friends" or "only until read". The privacy policy does.

## Not verified

- Xcode's privacy report (Organizer, "Generate Privacy Report") needs a signed archive; the
  unsigned builds here could not make one. Run it on the first release archive and compare it
  with Part A. It will also list what Sentry's manifest adds, which is already in the table.
- Nothing was uploaded, so no ITMS-91053 or ITMS-91056 mail has been seen or ruled out.
- The questionnaire was read from Apple's reference page, not from the App Store Connect form.
  If the form asks something this sheet lacks, answer it from the evidence above and add a row.
- The processors' own retention (Sentry 90 days, PostHog a year) is taken from `docs/privacy.md`.
