# Strong Like Tauren: Requirements

Tags: **v1** = first release, **v1.1** = next, **Later** = not scheduled. Architecture and module contracts are in `ARCHITECTURE.md`.

## Context
Strong Like Tauren is a **WoW Forever** exercise addon (client 1.60.1.71037, TOC `16001`), published on CurseForge. It should know how recently you moved, never interrupt a fight, and avoid the burst/drought pacing common to exercise addons that map each game event straight to reps.

**What goes wrong with event-to-reps pacing:**
- Every event maps straight to reps. There is no global cooldown, no hourly or daily cap, and no recency check.
- "New zone" fires on any zone change, with a short per-zone cooldown that /reload forgets. One flight stacks "New Zone xN".
- Quest stacking is capped only inside one prompt. Deaths stack with no cap ("Death x5" = 50 burpees).
- Skipped reps are banked as "owed". Snooze waits for the next trigger rather than a time.
- Prompts pop shortly after combat even mid-dungeon, at top-center, with a raid-warning sound.
- Level-up never fires again at Forever's permanent level-60 cap, and there is no dated history.
- The result is long skipped streaks with large "owed" totals. Design target: prompts sized and timed so people actually do them.

**Other Forever fitness addons** already have timers, combat waits, flight-path prompts and snooze. Ours differentiates on per-muscle recency/fatigue limits, a deferred queue that merges and replays at safe moments, and bounded pacing. All code is original.

## Decisions
- **Pacing = Timer + Rage.** Time drives the schedule; game events add flavor and bonus sets (section E).
- **v1 extras**: reputation, daily quest + streaks, achievements; import/export of exercise lists as share strings.
- **Publish on CurseForge**: README, packaging, localization scaffolding, hardening.
- **License**: MIT for the code. The "Strong Like Tauren" name and logo remain all rights reserved.
- **Logo**: a Tauren emblem (section M).
- **No external libraries.** Custom minimap button plus the Addon Compartment.
- **Dropped**: party/guild shout-outs. Live Forever realms block addons from posting chat.

## How it works (the pitch, also used on the Health page)
Every 30 minutes you sit, a 2-minute **Walkabout** comes due. Ignoring it never builds debt; it just grows, to 5 minutes at most.
Playing fills **Rage**: a full bar every 90 minutes, faster from quests, dings, deaths and bosses, with repeats worth less.
A full bar earns a **Feat of Strength** (2 exercises), at most one per 45 minutes, delivered with your next Walkabout.
Feats pick the muscles you've rested longest, and no muscle group gets more than 1.5 sets in any hour or 6 in a day.
Anything due in combat or a dungeon waits in your **Totem** until you're free.

| Per hour of play | Leveling (20 quests + ding) | Level 60 (2 quests) | Level 60 (no events) |
|---|---|---|---|
| Rage gained | ~170 (quests 53 + ding 50 + passive 67) | ~83 | 67 |
| Walkabouts | 2 | 2 | 2 |
| Feats of Strength | 1.33 (capped by the 45-min cooldown; extra Rage banks toward Double Feats, so the long-run average is higher) | ~0.8 | 0.67 (floor) |
| Load on any one muscle group | ≤ 1.5 sets | ≤ 1.5 sets | ≤ 1.5 sets |

## Product principles
1. Time drives the schedule; events add flavor.
2. Remembers your body, account-wide (alts share one human).
3. Never interrupts a fight.
4. **Nothing is ever owed**: missed work merges or expires, partials count.
5. One click to done / partial / snooze / swap / skip, no guilt.
6. Real exercise name always visible; the pun is extra.

## Requirements

### A. Tracking & history
- A1 v1 Log every outcome (done / partial / skipped / expired / credited). Each row records time, exercise, amount, load in sets (so later tier edits never rewrite history), tier, source (Walkabout, Feat, manual, away credit, early) and character.
- A2 v1 Body state is account-wide (seated clock, Rage, fatigue, queue, history). Per-character breakdown is just for fun.
- A3 v1 Stats: today / 7 days / lifetime per exercise and muscle group; "last done N min ago"; breaks taken vs. due; longest seated stretch; completion rate, with a gentle "try a lower tier?" when more than 40% were skipped over 7 days.
- A4 v1 Manual log (`/tauren log 20 pushups`, or "went for a run"): resets the seated clock and counts toward fatigue.
- A5 v1 Undo last (10 s toast) and delete rows in History. Totals reverse exactly.
- A6 v1 Retention: raw rows for 90 days (hard cap 6,000); daily totals forever (~0.3 KB/day).
- A7 v1.1 Import difficulty, custom exercises and lifetime totals from other fitness addons when their data is loaded.
- A8 Later CSV export.

### B. Exercise library & customization
- B1 v1 Fields: name, pun, kind (`reps` | `seconds`), standard amount, min/max, muscle groups with weights (legs, push, pull, core, cardio, mobility, walk), intensity, flags (jumping, floor, wrist-load, seated), needs (pull-up bar, band, dumbbells, chair, wall), min rest, preference 0–3 (favorites), event tags.
- B2 v1 ~22 built-ins: timed Walkabout moves (walk, march, calf raises + squats mix, wrist / hip-flexor / hamstring stretches) and Feat exercises (push-ups + desk push-ups, squats, lunges, wall sit, plank, crunches, glute bridge, chair dips, pull-ups, jacks + low-impact jacks, high knees, mountain climbers, burpees).
- B3 v1 Editor: enable/disable, add, edit, delete, reset. Built-ins are edited through overrides, so updates can still add new built-ins.
- B4 v1 Timed exercises: Start → countdown → sound → auto-log. Stop logs a partial.
- B5 v1 Filters: Quiet (no jumping), No floor, Easy on wrists, Equipment I have, Rest day.
- B6 v1 Share strings for exercise lists (format under "Share string").

### C. Intensity tiers
- C1 v1 Multiplier for Feats: **Critter 25% · Peon 50% · Grunt 100% (standard) · Kodo 150% · Tauren 200%** · Custom %.
- C2 v1 Per-exercise and per-group overrides ("Tauren legs, Peon arms").
- C3 v1 Rounding: reps to an integer ≥ 1; seconds to the nearest 5 (min 5); clamped to the exercise's min/max.
- C4 Later Auto-progression suggestion.

### D. Seated clock & health guidance
- D1 v1 The seated clock counts continuous seated play; any completed standing activity resets it. Seated stretches don't reset it unless the accessibility option "Seated breaks count" is on.
- D2 v1 A Walkabout comes due at 30 min (20–60): 2 min (1–5) of timed light movement, because walking beats just standing. Walkabout moves count only 0.1 toward leg fatigue.
- D3 v1 Health-dose presets: Minimum (1 min / 30), Recommended (2 min / 30), Max benefit (5 min / 30).
- D4 v1 Overdue: a "Rooted" debuff stacks every 15 min, and the Walkabout grows +1 min per stack up to 5 min. It never blocks play and is never owed.
- D5 v1 Away detection: the AFK flag (read secret-safely), or no input for 3+ min (ignored on a taxi or loading screen). Away 3–10 min asks "Did you get up?" (no answer = No). Away 10+ min is credited as a break, with a one-click "I was sitting". No passive Rage while away.
- D6 v1 A gap of 10+ min (logout, crash, clock jump) starts a fresh seated stretch and drops the pending Walkabout (not counted as a skip). A backwards clock jump counts as 0. /reload keeps counting.
- D7 v1 Health page (the pitch, what counts, weekly targets, sources) and a first-run disclaimer ("stop if it hurts").
- D8 v1 Walkabout text bundles eye and water cues ("look far away · sip water") instead of adding more timers.
- D9 Later "Totem Stance": a standing-desk toggle that pauses the seated clock.

### E. Pacing engine (the burst/drought fix)
- E1 v1 Two layers: Walkabouts (timer-driven) and Feats of Strength (Rage-driven).
- E2 v1 Rage fills to 100 per Feat and banks up to 200 (setting "Bank extra Rage", default on; off = clamp at 100). It fills passively (+100 per 90 min of non-away play) and persists between sessions. New installs start at 40, so the first Feat comes after about 54 min.
- E3 v1 Event Rage (configurable; 0 disables): quest 10 · level-up 50 · death 35 (repeats within 30 s ignored) · boss kill 30 (ENCOUNTER_END with success) · first visit to a map on this character 15 (never while on a taxi) · Hearthstone 10.
- E4 v1 Diminishing returns: gain = base ÷ (1 + 0.5 × same-type events in the last 60 min).
- E5 v1 A Feat is earned at Rage 100 once 45 min have passed since the last Feat was *earned*. While it waits, the bar shows "Feat in 12m". Rage above 100 stays banked (up to 200) and counts toward the flavor. A Feat spends 100 and leaves the remainder. At Rage 200, with no Feat already waiting, the Feat earned is a **Double Feat** ("ENRAGED!"): it spends 200 and has 2 × the usual exercises (max 6) on distinct primary muscle groups, each with the normal amount; the per-hour and per-day muscle caps still apply. If a Feat is already pending, a new earn merges (+25%) and spends only 100. When the bar reaches the cap during the cooldown, a one-time note says when the next (Double) Feat comes. The Totem shows "Feat in 12m · Rage 175" (or "Double Feat in 12m" at 200).
- E5b v1 ENRAGED!: a new Double Feat prints an in-character chat line, shows big red-orange center text and plays a war-horn sound (the text and sound are held while the game is busy; the reminder toast follows at the next safe moment with the title "ENRAGED! Double Feat of Strength" and a red glow). Achievements: Unbridled Rage (first completed Double Feat), Berserker (10).
- E6 v1 A Feat is 2 exercises (configurable 1–3) on different primary muscle groups. It is delivered with the next Walkabout, or alone if none is due within 30 min, and can be done early from the Totem.
- E7 v1 Flavor comes from the biggest Rage source: death → cardio "penance", boss → legs, ding → +25%, zone → march, hearth → water + walk.
- E8 v1 Rest day: Walkabouts continue, Rage pauses, a pending Feat is removed silently, and rest day switches off at the next day rollover (days start at 4 am).

### F. Recency & fatigue
- F1 v1 Hard caps on raw load: ≤ 1.5 standard sets per muscle group in any 60 min and ≤ 6 per day. Sets are normalized to your tier, so the caps hold at every tier.
- F2 v1 Decayed fatigue (half-life 60 min; Troll Regeneration 40 · Standard 60 · Ancient 90) only ranks choices and feeds "Why this?".
- F3 v1 Picker: filters → min rest → caps (shrinks a set if at least 50% fits) → weighted random by preference × time since last done ÷ fatigue × flavor match. It never repeats the previous pick. Fallback: "March in place".
- F4 v1 "Why this?" tooltip ("Legs resting — squats 22 min ago; picked Core").
- F5 v1 Swap keeps the same load, excludes earlier picks, and allows up to 3 per slot.

### G. Delivery: the Totem, snooze, safe moments
- G1 v1 **Totem**: a movable corner tracker, clamped to the screen, that stacks pending items (icon, pun + real name, amount, Done / Partial / Snooze / Swap / Skip). It collapses to a header showing the seated clock, Rage bar and rep bar.
- G2 v1 Quiet states (the Totem updates silently; no toast or sound): combat (+15 s after it ends), boss encounter, loading (+5 s), dead, raid / battleground / arena / scenario, dungeon (setting: hold until exit [default] or nudge between pulls), cinematics, away.
- G3 v1 Nudge moments: taxi start, entering a rest area, leaving an instance, combat ending in the open world, return from away, login + 10 s.
- G4 v1 Early offer ("Flight time — break now?"): at most once per seated stretch, once at least half the interval has passed.
- G5 v1 Snooze 5 / 10 / 20 min, until after combat, or until after the instance; the clock keeps running. After a Skip, the next Walkabout waits a full interval.
- G6 v1 The queue holds at most 1 Walkabout (a new one upgrades it instead of duplicating) and 1 Feat. A second earned Feat adds +25% once; total Feat bonus is capped at +50%. Feats expire after 3 h (logged as expired, no penalty).
- G7 v1 Nudge backoff: 10 → 20 → 40 → 60 min while ignored; any click resets it. Nudges never take focus or block play; sound and center text are optional.
- G8 v1 Partials log what you did, and the remainder is never owed. A partial Walkabout of 1+ min resets the clock.
- G9 v1 Pause reminders: 30 min / 1 h / until reload.

### H. Progress & fun
- H1 v1 Reputation with the **Bloodhoof Athletic Club**: Hated 0 → Hostile 500 → Unfriendly 1.5k → Neutral 3k → Friendly 6k → Honored 12k → Revered 24k → Exalted 45k. Gains: Walkabout +25, each Feat exercise +25 × fraction done, daily +150, manual +10; capped at 600/day and never decreasing (about 3–4 months to Exalted at 2 h/day).
- H2 v1 Daily quest "[Daily] Earthmother's Calling": 3 completions. The streak counts consecutive *played* days (20+ min) where the daily was done, so days off never break it.
- H3 v1 Achievements (Kodo Thighs: 1,000 squats; Shield Wall: 10 min of planks; Exalted; 7-day streak; …) with a toast.
- H4 Later Hardcore extras (`C_GameRules.IsHardcoreActive`).
- H5 Later Party "Bloodlust Break". At risk: addon messages were refused on live realms.

### I. Settings, UI & commands
- I1 v1 Main window (`/tauren`, alias `/slt`) with Today · History · Exercises · Settings · Health tabs, plus a page under Esc → Options → AddOns (opening waits until combat ends).
- I2 v1 Minimap button and Addon Compartment entry. Tooltip: seated time, Rage, next break. Left-click opens the window; right-click pauses.
- I3 v1 Commands: `now` · `up` · `log <n> <exercise>` · `snooze <min>` · `pause` · `tier <name>` · `stats` · `selftest` · `sim <scenario>` · `debug` · `bug` · `resetui`.
- I4 v1 First-run setup: tier, filters, equipment, health dose, disclaimer.
- I5 v1 Totem lock / scale / position; sound and center-text toggles.

### J. Flavor
- J1 v1 Random quips per situation: "Zug zug." · "Strong like Tauren!" · "Time is money, friend! Snoozed 10 min." · "At least I have chicken." (skip) · "The Spirit Healer demands penance." · "Rage banked full — Double Feat in 12m." · "Rooted (x2): 60 min seated."
- J2 v1 Vocabulary: Walkabout, Feat of Strength, Totem, Rage, Rooted (debuff), Earthmother's Vigor (buff after a break).
- J3 v1 Exercise puns: Kodo Squats, War Stomp (jacks), Shield Wall (plank), Totem Stance (wall sit), Hamstring (stretch), Whirlwind (torso twists), Plainsrunning (high knees), Thunder Bluff Climbers (mountain climbers), Spirit Healer's Penance (burpees), Hoof Raises (calf raises), Moonwell Dips (chair dips), Zeppelin Hang (pull-ups), Unclench the Mouse Paw (wrist stretch).

### K. Non-functional (Forever client)
- K1 v1 A single `StrongLikeTauren.toc`: `## Interface: 16001`, both SavedVariables, `AddonCompartmentFunc` (plus OnEnter/OnLeave if they work on Forever), IconTexture = our logo icon.
- K2 v1 `Game/Api.lua` is the only file that calls WoW APIs. Each call is wrapped in pcall and checked with `issecretvalue`, returning nil when unknown. Event payloads only trigger logic and are never stored.
- K3 v1 Forever detection via `select(4, GetBuildInfo())` in 16000–19999 (WOW_PROJECT_ID is unreliable on Forever).
- K4 v1 Timestamps come from `GetServerTime()` (fallback `time()`) and are clamped so they never go backwards. The day key is the local date with a 4 am rollover.
- K5 v1 Character key: a random id stored in the per-character file and re-linked by UnitGUID after renames (names are "First Surname" and realms are hidden).
- K6 v1 Options page via `Settings.RegisterCanvasLayoutCategory` + `RegisterAddOnCategory`, opened with `OpenToCategory(cat:GetID())`.
- K7 v1 UI: a solid background under backdrops (the stock dialog backdrop is see-through on Forever); fixed-size Totem rows, re-laid-out only outside combat.
- K8 v1 Event-driven; a 15 s ticker (1 s while a countdown runs); fatigue cached per minute.
- K9 v1 Schema version with per-version migrations run in pcall. A failed migration moves the old data to `db.broken`, resets to defaults and prints one message. Defaults also repair wrong types.
- K10 v1 Every handler runs in xpcall, logging to a 10-entry error log (`/tauren bug`). No globals beyond the saved data, slash commands and compartment function; no hooks; no protected calls.
- K11 v1 Strings live in a locale table (enUS; missing strings fall back to the key). Status is shown with text + icon, never color alone.

### L. Publishing
- L1 v1 README (features, commands, how pacing works, health sources, disclaimer, "a crash loses that session's data"), CHANGELOG, and LICENSE: **MIT for the code. The "Strong Like Tauren" name and the artwork (`Media/`, `art/`, `docs/logo.png`) are excluded and remain all rights reserved.** State this in LICENSE, the README and the CurseForge description, and pick "MIT" in CurseForge's dropdown.
- L2 v1 `.pkgmeta` (CurseForge packager) plus `release.ps1`, which zips a clean `StrongLikeTauren/` folder (no art/, docs/, tools/ or dev files).
- L3 v1 TOC metadata: colored Title, Notes, Author, Version, IconTexture; add `X-Curse-Project-ID` once the project exists.
- L4 v1 Clean-install test (see Verification 5).
- L5 v1 CurseForge listing copy (it becomes the README intro and is kept in sync with shipped features):
  - *Summary*: "A smart workout buddy for WoW Forever: it breaks up your sitting every 30 minutes, turns questing, dings
    and deaths into bonus sets, and never interrupts a fight."
  - *Description bullets*: Walkabouts every ~30 min · Rage-powered Feats of Strength (capped and floored) · Remembers your
    muscles · Never interrupts a fight · Your workout, your rules · Tiers Critter → Tauren · Progress (history, rep,
    daily quest, streaks, achievements) · `/tauren` · "Not medical advice."

### M. Branding
Source artwork: a 1600×1600 WebP emblem of a Tauren, kept as `art/logo-source.webp` (Windows' WebP decoder reads it).
- M1 v1 Keep the original as `art/logo-source.webp` (not shipped).
- M2 v1 `Media/SLT_Logo.tga`: 256×256, 32-bit, white background removed with an auto-detected circular alpha mask. Used in the main-window header, first-run splash and achievement toasts.
- M3 v1 `Media/SLT_Icon.tga`: 64×64 tight crop of the tauren head inside a ring (the banner text is unreadable at ~20 px). Used for the TOC IconTexture, minimap button, compartment and Totem header. Compare it with the full emblem at minimap size and keep whichever reads better.
- M4 v1 `docs/logo.png`: 512×512, for the README and the CurseForge project avatar.
- M5 v1 UI palette borrowed from the logo: leather-brown panels, gold headings, Mulgore-green accents.
- Conversion: `tools/make-art.ps1` uses Windows imaging to resize, crop and mask, with a small hand-written TGA writer (power-of-two sizes, as WoW requires). Check the preview PNGs by eye before using them.

## Share string
`SLT1!<record>;<record>!<CCCC>`. Each record is comma-separated `key=value` pairs (id, n, p, k, s, lo, hi, g, i, f, q, r).
Bytes outside `[A-Za-z0-9.-]` become `~HH` (space becomes `+`), so no `|` escape codes or chat substitutions get through.
`CCCC` is a Fletcher-16 checksum. The decoder rejects unknown versions, bad checksums and anything over 60 records or 8 KB.
It clamps numbers, strips `|` and control characters, caps names at 40 characters, never uses `loadstring`, and shows a
preview with Add / Update / Skip. Strings are copied from a select-all edit box.

## Health basis (what the defaults are built on)
| Finding | Source | Design use |
|---|---|---|
| 5 min light walking every 30 min cut post-meal glucose spikes ~58% and BP 4–5 mmHg vs. sitting all day; 1 min/hour helped BP, not glucose | Duran, ..., Diaz 2023, *Med Sci Sports Exerc* | 30-min Walkabouts; "Max benefit" = 5 min |
| 3 min of squats / calf raises / knee raises every 30 min during 4 h of *evening* sitting: glucose −31.5%, insulin −26.6% | Gale et al. 2023, *MSSE* | Squats and calf raises as Walkabout moves |
| 2 min light walking every 20 min improved glucose; standing breaks did not | Bailey & Locke 2015, *J Sci Med Sport* | "Walk, don't just stand" |
| Long uninterrupted sitting bouts linked to higher mortality; press summary: lowest risk with bouts < 30 min | Diaz et al. 2017, *Ann Intern Med* | 30-min max seated stretch |
| ≥ 9.5 h/day sedentary associated with higher mortality | Ekelund et al. 2019, *BMJ* | Seated-play total on the Today tab |
| Limit sedentary time; any intensity helps; 150–300 min moderate/week; strength ≥ 2 days/week | WHO 2020 guidelines (Bull et al., *Br J Sports Med*) | Health page targets; daily quest |
| ~3 bouts/day of 1–2 min vigorous activity ↔ 38–40% lower all-cause mortality (observational) | Stamatakis et al. 2022, *Nat Med* (VILPA) | Feats of Strength as "exercise snacks" |
| DVT / pulmonary embolism case reports after marathon gaming | *J Med Case Rep* 2013 ("gamer's thrombosis") | Calf raises in Walkabouts; overdue escalation |

## Verification
1. **Loads on Forever**: `/dump select(4, GetBuildInfo())` → 16001; listed with the logo, not flagged "out of date"; `/tauren` opens.
2. **`/tauren selftest`** (fake clock + API stub):
   - Util: 4 am day key, round-to-5, defaults repair.
   - Codec: round-trip of all built-ins including reserved characters and UTF-8; a one-character change fails the checksum; `SLT9` is rejected; names containing `|cff` are sanitized.
   - Rage: the 10 / 6.67 / 5 series; events leave the window after 60 min; cooldown blocks at 44:59 and allows at 45:00; gains while capped still set the flavor; Rage banks to 200 (100 with banking off); spend leaves the remainder; a steady ~175 Rage per cycle produces a 4-slot Double Feat within a few cycles with the muscle caps intact.
   - Seated: a 599 s gap continues and 600 s starts fresh; backwards clock; the 3-min and 10-min away branches; Rooted stacks at 45 and 60 min.
   - Picker: all 32 filter combinations × equipment produce a Walkabout and a Feat (or the fallback); never repeats the previous pick; caps hold; rounding; Swap keeps the load.
   - Queue / History / Progress: +25% merge only once; expiry; Walkabout never over 5 min; pruning leaves totals identical; apply(−1) exactly reverses apply(+1); the streak survives days off.
   - DB: an old-version fixture and a garbage file both migrate.
3. **`/tauren sim`** (assumes every popup is completed):

   | Scenario | Expected |
   |---|---|
   | A. Leveling 3 h: a quest every 3 min, dings at 40/100/160 | 6 Walkabouts; Feats earned at 40/100/160 (+25% ding), each riding with the next Walkabout; 6 popups; no group over 1.5 sets/hour |
   | B. Level 60, 3 h, no events | 6 Walkabouts; Feats at 90 and 180 (the floor) |
   | C. Raid 3 h: 8 bosses, deaths at 60/61/130 | Nothing shown inside; on exit one popup: 5-min Walkabout + one merged Feat at 125% |
   | D. AFK-heavy 2 h (away 20–60, 85–91 → "Yes") | 2 breaks credited, 2 prompts, no Feat |
   | E. Never takes breaks, 4 h | Popups at 30/50/90/150/210; queue never above 1 Walkabout + 1 Feat; Walkabout ≤ 5 min |
   | F. /reload, then a 2-day gap | Reload keeps clock and queue; the gap starts fresh, drops the Walkabout, expires the Feat, keeps Rage |
4. **In-game checklist**:
   - Combat: a break due mid-fight stays silent in the Totem, then the toast comes 15 s after combat ends.
   - Dungeon: held until you exit, then one merged popup.
   - Nudges: flight path and inn each nudge.
   - Away: AFK 3+ min brings the return prompt.
   - Snooze: 5 min comes back on time.
   - Persistence: /reload keeps everything.
   - Exercises: the timed plank auto-logs; partial / swap / skip / undo all work; a custom timed exercise shows up in picks; share strings round-trip.
   - Progress: rep and achievement toasts fire.
   - Entry points: minimap button, compartment and the Esc → Options page all work; first-run setup runs.
5. **Clean install**: fresh profile with a few popular addons enabled, `/console scriptErrors 1`, a 2-hour session, zero Lua errors.
6. **Package**: `release.ps1` → the zip contains only runtime files; install from the zip and repeat step 1.
