# Friend invites, friend profiles and basic social

Owner request, 2026-10-21: share an Aaru link with a friend; it opens the app on iPhone (or the
web where there is no app); a friend with an account becomes a friend at once, one without an
account signs up first and then becomes a friend. Friends can see each other's profile and what
they are watching, with a few basic interactions.

## Decisions (owner)

- The first invite's job is **getting connected**. Profile richness comes second.
- **One-use links.** A fresh link per invite (`aaruapp.com/i/{code}`), spent by the first
  person who accepts it, live for 14 days, revocable, at most 20 open per sender.
- **Android:** the web flow now. An Android app is a later, separate project; the `/i/*` path is
  kept for its `assetlinks.json`.
- **iPhone without the app:** the web flow (Aaru is TestFlight-only, so there is no App Store
  banner). iPhone or Mac with the app: a universal link opens it.
- **Visibility:** friends see each other's library by default, behind one "Show my library to
  friends" switch. Strangers see nothing, ever.
- **Interactions:** reactions on activity, recommending a title, comparing libraries, inviting
  a friend to a group. No DMs (P6).
- **Invite with a title:** a link may carry one title ("Watch Arrival with me"); the friend
  chooses whether to add it to Plan to watch.
- **Look:** the invite is a letter (medallion, serif headline, the poster as a postscript, one
  ink button). "Invite a friend" sits at the top of Friends on web and iOS.

## Shape

Three PRs:

1. **Invite links (SOC-002).** `social_invites`, `/v1/social/invites*`, the public preview
   `/v1/invites/{code}`, web `/i/{code}`, the AASA file, the iOS `InviteSheet`, and a
   `next` that survives sign-in (including the emailed link).
2. **Profile and activity.** `social_settings`, a friends-only profile with compare, and
   `/v1/activity` read from the action journal at query time.
3. **Interactions.** Reactions (SOC-007), recommendations (SOC-006), and group invites from a
   profile.

## Rules that carry through

- Accepting an invite makes both people friends at once. The sender asked by sending it, the
  friend by opening it. Both need a handle.
- Every dead end is one 404: unknown, spent, revoked or expired code, an inviter who left, and
  a block either way.
- The preview shows only the inviter's name, handle and chosen title.
- Adding the invite's title is the friend's tap: the same journaled write as Add, and it never
  touches a title they already have.
- Agents get none of this (VIEWS.md).
- Group invite links stay forbidden. These are friend invites only.

## Calls made by the builder

- The inviter is not pushed when an invite is accepted yet. That needs a new notification
  category and a toggle on both clients, and waits for SOC-005's friend categories.
- Universal links need the Associated Domains capability on both App IDs. The `seed_signing`
  lane turns it on and reissues profiles; run it before merging the entitlement.
