# Changelog

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
