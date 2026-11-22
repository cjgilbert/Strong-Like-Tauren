# Changelog

## 0.1.6

- New: extra Rage now banks up to 200 instead of going to waste; at 200 your next Feat is a Double Feat with twice the exercises (Settings: Bank extra Rage).
- New: a Double Feat is an ENRAGED! moment: a red-orange center banner, a war-horn sound, a red-glow reminder titled "ENRAGED! Double Feat of Strength", and the achievements Unbridled Rage and Berserker.

## 0.1.5

- Fixed: reminders could stop appearing for the rest of a session after a cutscene, boss fight or loading screen whose end the game didn't report.
- New: the Totem says when reminders are on hold and why; `/tauren debug` shows the reason.

## 0.1.4

- Changed: snoozing hides the snoozed exercises completely; when the snooze ends they return as a normal reminder (same sound, popup and quiet-time rules, waiting for a safe moment if needed).

## 0.1.3

- Changed: the due reminder appears top-center with a glow, closes on click, Escape or X, and pauses its 10-second timer while hovered.
- New: choose the reminder sound (Alert, Horn, Chime, Menu) with a Test button in Settings; Alert (ready check) is the default.

## 0.1.2

- Changed: due Walkabouts and Feats now show a compact reminder that plays a soft sound, flashes the taskbar and closes itself after 10 seconds (nothing is skipped; skip from the Totem).

## 0.1.1

- New: Totem buttons to pause the seated clock while you step away (auto-resumes on any input after 5 seconds) and to reset it when you've already been up.
- Fixed: the reminder popup now updates as you finish exercises and hides when everything is done.
- Fixed: long exercise names are no longer cut off with "..." in the popup and Totem.
- Fixed: the Undo popup has an OK button, and every popup has a close X that never changes your history.
- Fixed: the reputation bar always shows reputation (no lingering exercise name or green color).
- Fixed: the seated clock resets on login after the game was closed for 10+ minutes; time with the game closed never counts as sitting.
- Fixed: collapsing or expanding the Totem takes effect immediately, even in combat.

## 0.1.0

First release, for WoW Forever (interface 16001).

- Walkabouts: a timed 2-minute break every ~30 minutes of seated play (1 to 5 minutes, 20 to 60 minute interval), with a "Rooted" debuff that grows overdue breaks to 5 minutes and is never owed.
- Rage and Feats of Strength: passive Rage plus quest, level-up, death, boss, new-map and Hearthstone sources with diminishing returns; a Feat of 2 exercises at most once per 45 minutes.
- Totem: a movable corner tracker for pending items, with Done / Partial / Snooze / Swap / Skip.
- Safe moments: nothing pops up in combat, boss encounters, loading screens, instances or while dead; nudges at taxi starts, rest areas, instance exits and similar.
- Fatigue-aware exercise picker: recency, per-hour and per-day muscle caps, "Why this?", Swap, and a fallback move.
- About 22 built-in exercises with puns, an exercise editor, custom exercises, and timed exercises with a countdown.
- Intensity tiers Critter, Peon, Grunt, Kodo and Tauren, plus custom percentages and per-exercise and per-group overrides.
- Filters: Quiet, No floor, Easy on wrists, Equipment I have, and Rest day.
- Away detection with "Did you get up?" and automatic break credit.
- History, stats, manual logging (`/tauren log`), and undo.
- Share strings for exercise lists, with checksum and safe import preview.
- Reputation with the Bloodhoof Athletic Club, the daily quest "Earthmother's Calling", streaks, and achievements.
- Main window (`/tauren`, `/slt`), Esc, Options, AddOns page, minimap button, and Addon Compartment entry.
- First-run setup with health disclaimer and a Health tab with cited sources.
- `/tauren selftest` and `/tauren sim` for in-game verification.
