# Changelog

## 1.2.0

A new look, many more things to do from the panel, and a friendlier Off state. Thank you to everyone who sent code: @shinodanpen, @ndecool, @RobLW, @theflysurfer and @mxKeaton.

### New look

- The whole panel and bar are redesigned: a calm palette that follows your Omarchy theme, a new logo, the bar pill that flows into the open panel, a Settings rail, and an all-keys sheet (`?`).
- While a song plays, its cover's colour glows softly behind the panel's header (inspired by [Spinbloom](https://github.com/TeXaCoNy/spinbloom)). (#36)
- Compact panel: on short screens a playlist or album page keeps at least four rows in view. Settings: Auto, Always or Never. (#27, @shinodanpen)
- Plain text in the bar at rest, for see-through bars: the pill comes back on hover. Off unless you turn it on in Settings. (#26, @shinodanpen)
- The bar keeps the player's shape while Solfa starts, so it no longer jumps from "Nothing playing" to the song. (#32)

### Off, and the first run

- When Solfa is off, the bar and the panel show the last song, asleep. A click on its cover turns Solfa on and plays it from where you left it. While it loads, the song is already there, with a loader on its cover. (#35)
- The place in the song is kept every few seconds and before turning off, and Play on plays that exact song, even when YouTube Music brings back another one (for example one played later on a phone).
- A click on the bar while Solfa is off opens the panel only. It never starts the browser by itself.
- First run: a welcome card. Click the record to start, or a chip to start on Search, Your library or Synced lyrics. When you are signed out, Sign in is one click away.

### New in the panel

- Save a song to a playlist, and adding a song a playlist already has no longer adds it twice. (#15, @shinodanpen)
- Remove a song from a playlist of your own, with Undo. (#19, @shinodanpen)
- Find a song in a playlist or album (`F`). (#17, @shinodanpen)
- Copy the playing song's link (`c`). (#16, @shinodanpen)
- Go to artist opens a picker when a song has two or more artists.

### Fixed

- Signing in could come back signed out: Solfa now waits for YouTube's own sign-in step, and sees its cookie when it is set again. (#20, @ndecool)
- Sign in clicked while Solfa's helper was still starting did nothing. It now says "Solfa's helper is restarting". (#22, @ndecool)
- A sign-in window playing a song was not seen as having reached the app.
- Lyrics: a line wider than the panel now wraps instead of being cut with an ellipsis. (#30, @shinodanpen)
- Queue: a click on an autoplay song did nothing. It now plays it. (#28)
- Search: the All view follows YouTube Music's own ranking, videos and episodes included. (#14, @shinodanpen)
- A shuffled playlist's queue keeps loading after the page recycles, and the queue panel loads its next page. (#18, @shinodanpen)
- The library lists every playlist, not only the first 25. (#6, @RobLW)
- A library page that fails keeps the rows already listed. (#10)
- The orphan lease outlasts a shell restart. (#8, @theflysurfer)
- The open-panel underline is as wide as the widget's content. (#13, @shinodanpen)
- The equaliser bars in a row stop when playback is paused.
- QML lint is clean on Qt 6.12. (#12, @shinodanpen)

## 1.1.0

- New History tab (key `5`): what the account played lately, newest first, under Today / Yesterday / ... Signed out it says to sign in; Premium is not needed.
- Adverts are skipped by themselves: Solfa presses the Skip button every second until the advert is gone.
- New setting (off by default): with Brave as the engine's browser, let its ad blocker fetch its filter lists so it blocks adverts.
- Fixed: Settings > Browser for the engine offered Chrome, Brave and Vivaldi even when they were not installed; picking one left Solfa off with "no Chromium-family browser found". It now offers only the browsers it finds, and a missing one is named.
- Fixed: moving another widget in the bar (or anything else that makes the shell build Solfa's service again) stopped the song and brought it back 3 seconds later when the browser or the Brave ad-blocker setting was not the default. The new service judged the running engine against its own default settings, before the shell had handed over the real ones, and restarted it. It now waits for the settings, and a change of them restarts the engine once.
- Fixed: after the shell reloaded (a bar layout change), the engine could start in Chromium instead of the browser chosen in Settings, and the sign-in was lost (Chromium cannot read another browser's cookies). The shell no longer starts the engine on settings it has not received yet.
- Fixed: the engine now keeps to the browser its profile was built with. A start that is not told the browser takes it from the launch key, then from a `.solfa-browser` mark in the profile. Auto still picks the first installed browser. A start with no settings at all on an existing profile is not opened by a guess: Solfa says "waiting for the browser setting".

## 1.0.2

- Fixed: on a free (non-Premium) account every song stopped at 0:49 and Play did nothing.
- Fixed: Sign out could fail with "YouTube Music is not ready yet" while a song played.
- A fresh install starts off: nothing loads until you turn Solfa on.
- Adverts are clearly marked: a "This is an ad" badge with the time left, and a Skip ad button.
- Google's cookie question (asked in the EU) can be answered from the panel, with the reason it is asked.
- While signing in, Solfa's icon breathes in the bar and in the panel.

## 1.0.1

- Fixed: after the bridge restarted (a plugin update or a settings change), the panel could stay on "Starting Solfa" and never load. The shell now reconnects to the bridge whenever it comes back.
- After an update, if the shell still runs the old Solfa code, the panel now says to restart the shell (`omarchy-restart-shell`) instead of staying on "Starting Solfa".

## 1.0.0

- First release.
