# Changelog

## 1.1.0

- New History tab (key `5`): what the account played lately, newest first, under Today / Yesterday / ... Signed out it says to sign in; Premium is not needed.
- Adverts are skipped by themselves: Solfa presses the Skip button every second until the advert is gone.
- New setting (off by default): with Brave as the engine's browser, let its ad blocker fetch its filter lists so it blocks adverts.
- Fixed: Settings > Browser for the engine offered Chrome, Brave and Vivaldi even when they were not installed; picking one left Solfa off with "no Chromium-family browser found". It now offers only the browsers it finds, and a missing one is named.

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
