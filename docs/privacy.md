# Privacy policy

_Last updated 20 October 2026._

Aaru is a private media library: what you watch and read, kept for you. This page says what
Aaru stores, who else sees any of it, and how to delete it. If anything here stops matching
what Aaru does, this page changes first.

## The short version

- Your library is **private**. There is no public profile and no feed, and your library is
  never shared with other users. If you choose a handle, people who know it can send you a
  friend request; friends see your handle and name, nothing else.
- **Group chats are not end-to-end encrypted.** Messages in a group are stored readable on
  Aaru's server so the group works across your devices; the apps say so in every group.
- **No ads, no tracking, no analytics.** Aaru does not sell or rent data, and has no
  advertising or analytics code in the apps or on the website.
- You can **delete your account** in Settings. That removes your library and account at once.

## What Aaru stores

**Your account.** How you sign in (Apple, Google or email), the identifier that service gives
Aaru, your email address when the service shares it, and a display name if you have one.
Sign-in sessions are stored only as one-way hashes; on the web the session lives in a secure,
HttpOnly cookie. Email sign-in codes are stored hashed and expire after 15 minutes.

**Your library.** The titles you add, their status, whether you own them, ratings, notes,
episode progress, your lists and saved shelves, and a short history of your changes so they
can be undone.

**Imports.** When you import a file (IMDb, Letterboxd, Goodreads, and others), Aaru reads it and
keeps the rows it found with that import so you can review the plan before anything changes.
The uploaded file itself is not kept. If you connect Trakt, Aaru stores Trakt's access tokens
encrypted and uses them only to import your history; disconnecting removes them.

**Stremio.** If you connect Stremio, Aaru stores the link only as a one-way hash, with its name,
what it may do, and when it was last used. While it is connected, Stremio tells Aaru when you
start, pause and stop playing something, and Aaru keeps that playback session (the title,
episode, position and length) so it can tick off what you finished. Your changes from Stremio
appear in your history like any other. Revoking the link in Settings stops all of it.

**Profile and friends.** If you choose a handle, Aaru stores it. Anyone who types your exact
handle can see it with your name and send you a friend request; nobody can search or browse for
you. Aaru stores pending requests, who your friends are, who you blocked, and any report you
send about another user (the reason and your note). The person you block or report is not
told. Deleting your account removes all of it; a report someone sent about you keeps its reason
but no longer points to you.

**Groups.** If you create or join a group, Aaru stores the group's name, its channels, who is in
it and with what role, invites waiting for an answer, and where you last read in each channel.
Every message you send in a group is stored as you wrote it, with who you tagged, and the other
members of that group can read it. Group messages are **not end-to-end encrypted**: Aaru's
server can read them. Nobody outside the group can find it or see anything in it. Deleting a
message empties it straight away. Deleting your account empties every message you sent in any
group and removes you from them; a group you owned passes to another member, or goes if nobody
else was in it. The export includes your groups and the messages you wrote.

**Notifications.** If you turn on new-episode alerts, Aaru stores your device's push token and
that setting.

**Catalog data** (titles, posters, episode lists) is shared by everyone and is not about you.

## Who else is involved

Aaru only uses these services, and only for the purpose listed:

- **Hetzner** (Germany) runs Aaru's server and database and holds encrypted backups.
- **Cloudflare** serves the website at aaruapp.com and its DNS.
- **Apple** for Sign in with Apple and push notifications; **Google** for Sign in with Google.
- **Resend** sends sign-in emails, so it receives your email address and that email.
- **Trakt**, only if you connect it, for importing your history.
- **Stremio**, only if you connect it. Your Stremio app asks Aaru for your rows and reports
  what you play; Aaru does not send anything to Stremio's servers.
- **TMDB, TVmaze, AniList and Open Library** provide catalog data. Aaru's server sends them
  what you search for and catalog ids, never who you are.

## How long it is kept

Everything stays until you delete it or delete your account. Deleting your account removes
it from the live database immediately. Encrypted backups are kept for 30 days, and one
backup a month is kept for 12 months, so a deleted account is fully gone from backups
within a year.

## Your choices

- **Delete your account:** Settings → Delete account, in the app or on the web.
- **Export:** Settings → Export your data, in the app or on the web. JSON has everything; CSV
  opens in a spreadsheet and imports back into Aaru.
- **Questions or requests:** privacy@aaruapp.com.

Aaru is run by an individual developer based in the European Union. You have the rights the
GDPR gives you: access, correction, deletion, portability and objection.
