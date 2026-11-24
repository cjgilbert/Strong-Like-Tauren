# Strong Like Tauren — architecture & module contracts

Target client: **World of Warcraft: Forever** (build 1.60.1, TOC `16001`, Midnight-family API with "secret values").
Requirements and design rationale: `docs/REQUIREMENTS.md`. Load order: `StrongLikeTauren.toc`.

## Layers

| Layer | Files | Rule |
|---|---|---|
| Pure | `Locales/`, `Core/Util.lua`, `Core/Const.lua`, `Data/`, `Logic/`, `Store/`, `Test/` | No WoW API calls (only `date` via `ns.U.date`). Must run under LuaJIT: `luajit tools/run-tests.lua`. |
| Game | `Game/Api.lua` | The **only** file that queries game state. Every call is `pcall`-wrapped and secret-checked; returns `nil` when unknown. |
| Glue | `Core/Actions.lua`, `Game/Events.lua`, `Core/Commands.lua`, `Core/Init.lua` | Wire events → Scheduler → actions → UI. |
| UI | `UI/` | Frames only. Game state comes from `ns.Api`/`ns.ctx`; changes go through `ns.Do.*`. |

Every file starts with `local ADDON, ns = ...`. Modules: `ns.L ns.U ns.C ns.D ns.Library ns.History ns.Fatigue ns.Rage
ns.Seated ns.Picker ns.Queue ns.Progress ns.Codec ns.Scheduler ns.DB ns.Api ns.Do ns.UI ns.Events ns.Commands
ns.SelfTest ns.Sim`. Globals allowed: `StrongLikeTaurenDB`, `StrongLikeTaurenCharDB`, slash commands, the three
`StrongLikeTauren_OnCompartment*` functions, and named frames prefixed `StrongLikeTauren`. No hooks, no protected calls.

## Runtime state (set up by `Core/Init.lua`)
- `ns.db` account DB (`StrongLikeTaurenDB`), `ns.cdb` character DB (`StrongLikeTaurenCharDB`).
- `ns.env = { defs, byId, rng, char }` — effective exercise library (`Library.build(ns.D.EXERCISES, ns.db.lib)`),
  RNG (`U.rng(seed)`), this character's index. Rebuilt by `ns.Do.libraryChanged()`.
- `ns.ctx` — live game context, owned by `Game/Events.lua`:
  `combat, encounter, loading, dead, cinematic` (bools), `inst` (`"none"|"party"|"raid"|"pvp"|"arena"|"scenario"`),
  `taxi, resting, away` (bools), `awaySince` (time), `settleUntil` (time), `pausedSession` (bool), `lastInput` (time).
- `ns.now()` → `ns.Api.now()`: `GetServerTime()` (fallback `time()`), clamped so it never goes backwards.
- `ns.ready` → true after PLAYER_LOGIN setup.

## Data shapes
- **Exercise def** (`Data/Exercises.lua`, `Library.build`): `id, name, pun, desc, kind ("r"|"s"), std, lo, hi,
  g {group=weight}, int, flags {jump,floor,wrist,seated}, needs, rest, pref (1-3), tags, walk, icon, on, builtin|custom,
  pct (override), primary`.
- **Queue item** (`db.queue.items`, max one `W` and one `F`): `id, k ("W"|"F"), t, exp, min, rooted, bonus, merged,
  flavor, slots, double`. **Slot**: `x (exercise id), a (planned amount), l (load), u (unit), p (tier %), sets, walk, why,
  swaps, o (outcome once resolved), done (amount done)`.
- **Log row** (`db.log.rows`): see header of `Logic/History.lua`. **Day** (`db.days[key]`): `ex, g, w{due,done,skip,cred},
  f{earn,done,skip,exp}, seatMax, play, dn, dq`. **Totals**: `db.totals{ex,g,walks,walkSec,feats,credited}`.
- **Settings** (`db.settings`): paths from `C.OPTIONS` (e.g. `walk.every`, `filters.quiet`) plus `groupPct{group=pct}`,
  `totem{point,x,y,...}`. Validate with `C.validate(C.OPTION_BY_PATH[path], value)`.
- **Body**: `db.body{acc, lastTick, paused (time the seated clock was paused, nil = running), rooted, skipUntil, earlyOffered, restDay, rage{v,lastFeatAt,src,ev,last}}`. `Rage.v` is 0–100 per Feat and banks up to `C.RAGE_BANK` (200) when `settings.rage.bank` is on (else clamped at 100). `Rage.passive/event(..., bank)` take the bank flag; `Rage.spend(R, now, size)` removes `100*size` and keeps the remainder. A Double Feat (`S.tick`: v >= 200, banking on, no Feat pending) spends 200 and builds `min(6, 2*feat.slots)` slots; its queue item has `double = true`.
- **Progress**: `db.prog{rep, repDay, dailies, doubles (completed Double Feats), enraged (earned), streak{cur,best,last}, ach{id=time}}`; standings `C.STANDINGS`.

## Scheduler (`Logic/Scheduler.lua`) — UI must go through `ns.Do`, not call it directly
`tick(db,now,ctx,env)`, `moment(db,kind,now,ctx,env)` (kinds: taxi, rest, leave, combat, return, login),
`complete(db,itemId,idx,amount|nil,now,env)`, `skip(db,itemId,idx|nil,now,env)`, `swap(db,itemId,idx,now,env)`,
`undo(db,rowId,before)`, `credit(db,now,env,src)`, `undoCredit(db,rowId,prevAcc)`, `forceWalk(db,now,env)`,
`manualLog(db,x,amount,now,env)`, `snooze(db,min,now)`, `snoozeInstance(db)`, `pause(db,sec,now)`, `resume(db)`,
`ack(db)`, `rageEvent(db,kind,now)`, `setRestDay(db,on,now)`, `status(db,now,ctx)`, `gate(db,now,ctx)`, `snoozed(db,now,ctx)`→bool (timed snooze running, or "until I leave" inside an instance; the UI hides Totem rows and the reminder while true; nothing is skipped or logged),
`pauseClock(db,now)`→bool (sets `body.paused`=time, banks <=1 tick of acc) / `resumeClock(db,now)`→pause seconds|nil (continues the clock, not a break; no away credit for the paused time), `seatedNow(db,now,ctx)` (extrapolates at most `S.TICK_CAP`=20 s past lastTick; frozen `acc` while paused), `deliverable(db,now)`,
`login(db,now,env,isReload)` (gap since saved logout: 10+ min => fresh stretch + Walkabout dropped; shorter => acc kept,
offline time not added; reload keeps counting; run via `ns.Do.login` at PLAYER_LOGIN and PLAYER_ENTERING_WORLD).

Snooze end: `tick` notices an expired `nudge.snoozeUntil` (`now >= snoozeUntil`, the exact complement of `snoozed()`), clears it and sets `nudge.snoozeEnd`; the next `deliver` (this tick, or the next safe moment such as `combat`) bypasses the 10-minute limiter once but still obeys the quiet/away/pause gates, then clears the flag. The Totem's 1-second check calls `ns.Do.tick()` when it sees the snooze end, so the reminder shows the same second the rows reappear; `tick` is safe to call more often than every 15 s (dt is just smaller). "Until I leave" ends on the `leave` moment.

New work: `tick` sets `nudge.fresh` when it creates a Walkabout or earns a Feat (created, or a merge that made it bigger). `deliver` treats `fresh` like `snoozeEnd`: bypasses the limiter once, still obeys the gate, clears it on delivery (or when nothing is deliverable). The limiter (10 -> 20 -> 40 -> 60 min) only paces re-nudges of work already reminded about and ignored. `settings.feat.delivery` defaults to `"asap"` (a Feat alone is deliverable at once); under `"walk"` a lone Feat is deliverable after 30 min and the Totem hides it until then (`S.deliverable` is the single source for both). `db.nudge.log` keeps the last 20 attempts that had something deliverable, `{t, r}` with `r` = `"shown"`, `"limiter"` or the gate's `why`; a blocked reason is only logged when it differs from the previous entry. `/tauren debug` prints the last 5.

### Action tables (returned by Scheduler; handled by `ns.dispatch` in `Core/Actions.lua`)
| Action | Fields | UI behaviour |
|---|---|---|
| `toast` | `w, f, moment` | `UI.Toast:Show(w, f, moment)`, sound `toast`, optional center text, refresh |
| `due` / `rooted` / `expired` / `fresh` / `rageCapped` | item / n / item / – / left, bank | refresh Totem (silent) |
| `enraged` | `item, flavor` (pushed with `feat` for a new Double Feat; `db.prog.enraged` counts them) | chat line `D.QUIPS.enraged`; when the gate is open (`Scheduler.gate().may`) big red-orange center text `UI.Toast:Center` and `ns.sound("enraged")` (held while busy) |
| `feat` | `item, flavor, merged` | refresh; chat line `D.QUIPS.flavor[flavor]` or a `D.QUIPS.feat` line |
| `ask` | `dur` | `UI.Prompts:AskAway(dur)` → `ns.Do.answerAway(yes)` |
| `credit` | `row, prevAcc, dur` | `UI.Prompts:Credit(action)` with "I was sitting" → `ns.Do.undoCredit(row, prevAcc)` |
| `offer` | `moment` | `UI.Prompts:Offer(moment)` → "Break now" → `ns.Do.forceWalk()` |
| `done` | `row, item, slot, finished, undo, manual` | `UI.Prompts:Undo(action)` (10 s), sound `done`, a `done` quip |
| `skip` | `item` | a `skip` quip, refresh |
| `daily` | – | chat + `UI.Toast:Message(...)` "Daily complete" |
| `standing` | `name` | chat "You are now <name> with the Bloodhoof Athletic Club.", sound `achieve` |
| `achieve` | `a` | `UI.Toast:Achievement(a)`, sound `achieve` |

## `ns.Do` facade (`Core/Actions.lua`) — the only way UI changes state
`tick() moment(kind) complete(itemId,idx,amount) skip(itemId,idx) swap(itemId,idx)→ok,why snooze(min) snoozeInstance()
pause(sec) pauseSession() resume() pauseClock() resumeClock(auto) forceWalk() gotUp() manualLog(x,amount)→ok,err undo(doneAction)
undoCredit(rowId,prevAcc) answerAway(yes) setRestDay(on) setSetting(path,value)→stored setGroupPct(group,pct|nil)
libraryChanged() deleteRow(rowId) ack()`. Plus helpers: `ns.dispatch(acts)`, `ns.UI.refreshAll()`, `ns.say(msg)`
(chat line with a gold "Strong Like Tauren:" prefix), `ns.quip(kind, ...)`, `ns.sound(role)` (first existing
`SOUNDKIT` name from `C.SOUNDS[role]`, only if `settings.nudge.sound`). Every `ns.Do` call runs inside `xpcall`
and logs errors with `DB.logError`.

## `Game/Api.lua`
`now() isForever() inCombat() instanceType() onTaxi() resting() afk() dead() mapId() zoneName() cursor()→x,y
player()→{name,class,guid} safe(v) playSound(soundkitName) probe()→{ {name, value, secret} }`.
Secret values: `if issecretvalue and issecretvalue(v) then return nil end` (wrap in pcall).

## `Game/Events.lua`
- One event frame; `RegisterEvent` wrapped in `pcall` (unknown events must not error); handlers in `xpcall`.
- Keeps `ns.ctx` current and detects transitions → `ns.Do.moment(kind)`: taxi start → `taxi`; resting start → `rest`;
  instance → none → `leave`; combat end in the open world → `combat` after a 15 s settle (`ctx.settleUntil`);
  loading screen end sets a 5 s settle; login → `login` after 10 s; away → present → `return` (after the tick).
- Away: `ctx.away = Api.afk() or (not taxi and not loading and now - lastInput >= 180)`; `awaySince = lastInput`.
  `lastInput` updates on GLOBAL_MOUSE_DOWN, PLAYER_STARTED_MOVING, MODIFIER_STATE_CHANGED, PLAYER_TARGET_CHANGED,
  UNIT_SPELLCAST_START (player) and cursor movement (polled each tick).
- Rage: QUEST_TURNED_IN→quest, PLAYER_LEVEL_UP→level, PLAYER_DEAD→death, ENCOUNTER_END success==1→boss,
  ZONE_CHANGED_NEW_AREA (not on taxi, `Api.mapId()` not yet in `ns.cdb.zones`) → zone, UNIT_SPELLCAST_SUCCEEDED
  (player, `C.HEARTH_SPELLS[spellID]`) → hearth. Payloads are triggers only — never stored.
- Paused clock: `E.pausePoll` (1 s ticker, works only while `body.paused`) polls the cursor; any input signal seen more than 5 s after pausing calls `ns.Do.resumeClock(true)` ("Welcome back!" chat line). Tick while paused: no acc, no passive Rage, no away tracking, no delivery; `S.gate().paused` is true.
- Ticker: `C_Timer.NewTicker(15, ns.Do.tick)`. PLAYER_LOGOUT: `ns.db.body.lastTick = ns.now()`.

## UI modules (`ns.UI.*`)
- `Theme` — palette from the logo (leather brown panels, gold headings, Mulgore green, amber, red, rage red) and
  builders: `Panel(parent,name,w,h)`, `Button(parent,text,w,h,onClick)`, `IconButton(parent,texture,size,tip,onClick)`,
  `Check(parent,label,get,set)`, `Stepper(parent,label,get,set,min,max,step,fmt)`, `Segmented(parent,options,get,set)`,
  `Bar(parent,w,h,color)` (StatusBar with `.text`), `Text(parent,font,text,color)`, `Header(parent,text)`,
  `Scroll(parent,w,h)`→scroll,content, `EditBox(parent,w,h,multiline)`, `Tooltip(owner,lines)`. Builders that bind
  data return objects with `:Refresh()`. Every panel gets a **solid background texture** under its backdrop.
- `Totem` (header has fixed 14 px Pause/Play and "I got up" icon buttons next to the seated bar; collapse button applies immediately even in combat; `:Init :Refresh :Show :Hide :ResetPosition`), `Toast` (`:Show(w,f,moment) :Achievement(a)
  :Message(title,text,icon) :Hide`), `Countdown` (`:Start(itemId,idx) :Stop`), `Prompts` (`:AskAway :Credit :Offer
  :Partial(itemId,idx) :Undo`), `MinimapButton` (`:Init :Refresh`).
- `Main` (`:Toggle(tab) :Show(tab) :Hide :Refresh :IsShown`), tabs `today history exercises settings health`, each
  registered as `ns.UI.Tabs[key] = { title, build = function(parent) return frame end, refresh = function(frame) end }`.
- `Share` (`:Export :Import`), `FirstRun` (`:Show`), `Options` (`:Register :Open`).

## Commands (`/tauren`, `/slt`)
`(none)` toggle window · `now` · `up` · `log <n> <exercise>` · `snooze <min>` · `pause [min]` · `resume` ·
`tier <critter|peon|grunt|kodo|tauren|NN>` · `rest on|off` · `stats` · `selftest` · `sim <A-F|all>` · `debug` ·
`bug` · `resetui` · `help`.
