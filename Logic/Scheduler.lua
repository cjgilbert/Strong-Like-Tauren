local ADDON, ns = ...
local U, C = ns.U, ns.C
local Seated, Rage, Queue, History = ns.Seated, ns.Rage, ns.Queue, ns.History
local Picker, Progress, Library = ns.Picker, ns.Progress, ns.Library

-- The pacing engine. Pure: `now`, the game context and env = { defs, byId, rng, char } are passed in.
-- Every function returns a list of action tables; the UI (or the simulator) carries them out:
--   toast {w, f, moment}   ask {dur}   credit {row, prevAcc, dur}   offer {moment}   due {item}
--   feat {item, flavor, merged}   rooted {n}   done {row, item, finished, undo}   skip {item}
--   daily   standing {name}   achieve {a}   expired {item}   fresh   rageCapped {left}
--
-- ctx (game context): combat, encounter, loading, dead, cinematic, inst ("none"|"party"|"raid"|"pvp"|"arena"|
--   "scenario"), taxi, resting, away, awaySince, settleUntil, pausedSession
local S = {}
ns.Scheduler = S
S.TICK_CAP = 20 -- seatedNow never extrapolates more than about one tick (15 s) past the last tick

local function push(acts, a)
  acts[#acts + 1] = a
  return a
end

local function dayOf(db, now)
  return U.dayKey(now, db.settings.dayStart)
end

local function pickerFor(db, env, now)
  return Picker.context(db, env.defs, env.byId, now, env.rng)
end

local function kindOf(env, x)
  local d = env.byId[x]
  return d and d.kind or "r"
end

-- Seated clock ---------------------------------------------------------------------------------------

-- Fresh seated stretch. A pending, untouched Walkabout is no longer needed: it is removed and returned.
function S.resetClock(db, now)
  Seated.fresh(db.body, now)
  db.nudge.ignored = 0
  local W = Queue.get(db.queue, "W")
  if W and not W.slots[1].o then
    Queue.remove(db.queue, W.id)
    return W
  end
end

-- Seated seconds right now (for display between ticks).
function S.seatedNow(db, now, ctx)
  local B = db.body
  if ctx and ctx.away then return B.acc end
  return B.acc + math.min(S.TICK_CAP, math.max(0, now - (B.lastTick or now)))
end

-- Login (not a tick). Time with the game closed is never seated time. A gap of 10+ minutes since the saved logout
-- starts a fresh stretch and drops the pending Walkabout; a shorter one keeps acc but is not added. A /reload
-- (isReload) keeps counting. Call before any UI shows the clock; calling with isReload=true first is safe (only the
-- 10-minute rule applies), then again at PLAYER_ENTERING_WORLD with the real flag.
function S.login(db, now, env, isReload)
  local acts = {}
  local B = db.body
  local gap = now - (B.lastTick or now)
  if gap < 0 then gap = 0 end
  if gap >= 600 then
    Seated.fresh(B, now)
    Queue.dropWalk(db.queue)
    db.nudge.ignored = 0
    B.awayStart, B.awayFrom = nil, nil
    B.lastTick = now
    push(acts, { t = "fresh" })
  elseif not isReload then
    B.awayStart, B.awayFrom = nil, nil
    B.lastTick = now
  end
  return acts
end

-- Credits a break without exercise ("I got up", time away). Returns the credit row.
function S.credit(db, now, env, src)
  local W = S.resetClock(db, now)
  return History.append(db, { t = now, d = dayOf(db, now), x = "walk", k = "s", a = 0, l = 0, o = "cred",
                              s = src or "up", c = env.char, q = W and W.id or nil })
end

-- "I was sitting": undoes an automatic away credit.
function S.undoCredit(db, rowId, prevAcc)
  History.undo(db, rowId)
  if prevAcc then db.body.acc = prevAcc end
end

function S.awayReturn(db, now, dur, missed, env, acts)
  local s, B = db.settings, db.body
  if dur >= s.away.credit * 60 then
    local prevAcc = B.acc + missed
    local row = S.credit(db, now, env, "away")
    push(acts, { t = "credit", row = row.id, prevAcc = prevAcc, dur = dur })
    return true
  else
    B.acc = B.acc + missed
    if dur >= s.away.ask * 60 then
      push(acts, { t = "ask", dur = dur })
      return "ask"
    end
  end
end

-- Delivery -------------------------------------------------------------------------------------------

-- Quiet = the game is busy; may = a nudge is allowed right now.
function S.gate(db, now, ctx)
  local s, N = db.settings, db.nudge
  local inst = ctx.inst or "none"
  local quiet = ctx.loading or ctx.combat or ctx.encounter or ctx.dead or ctx.cinematic
    or (ctx.settleUntil and now < ctx.settleUntil)
    or inst == "raid" or inst == "pvp" or inst == "arena" or inst == "scenario"
    or (inst == "party" and s.dungeon == "hold")
  local snoozed = now < (N.snoozeUntil or 0) or (N.snoozeInst and inst ~= "none")
  local paused = now < (N.pauseUntil or 0) or ctx.pausedSession
  quiet = quiet and true or false
  local away = ctx.away and true or false
  return { quiet = quiet, away = away, snoozed = snoozed and true or false, paused = paused and true or false,
           may = s.enabled and not quiet and not away and not snoozed and not paused }
end

-- What would be shown now: the Walkabout (with a Feat riding along), or a Feat alone once it has waited 30 min.
function S.deliverable(db, now)
  local W, F = Queue.get(db.queue, "W"), Queue.get(db.queue, "F")
  if W then return W, F end
  if F and (db.settings.feat.delivery == "asap" or now - F.t >= 1800) then return nil, F end
  return nil, nil
end

-- Nudge limiter: 10 -> 20 -> 40 -> 60 min while nudges are ignored; any click resets it.
function S.nudgeWait(db)
  local N = db.nudge
  return math.min(db.settings.nudge.gap * 60 * 2 ^ (N.ignored or 0), 3600)
end

function S.deliver(db, now, ctx, env, acts, moment, bypassLimiter)
  local W, F = S.deliverable(db, now)
  if not W and not F then return false end
  if not S.gate(db, now, ctx).may then return false end
  local N = db.nudge
  if not bypassLimiter and now < (N.lastAt or 0) + S.nudgeWait(db) then return false end
  N.lastAt = now
  N.ignored = (N.ignored or 0) + 1
  push(acts, { t = "toast", w = W, f = F, moment = moment })
  return true
end

-- Tick (every 15 s in game) -----------------------------------------------------------------------------
function S.tick(db, now, ctx, env)
  local acts = {}
  local B, s = db.body, db.settings
  local asked = false -- "were you away?" is on screen: hold the Walkabout until it is answered
  local last = B.lastTick or now
  if now < last then last = now end -- clock went backwards: count nothing
  local dt = now - last
  B.lastTick = now
  local dayKey = dayOf(db, now)
  if B.restDay and B.restDay ~= dayKey then B.restDay = nil end

  -- Logged off, crashed or slept for 10+ minutes: fresh stretch, the pending Walkabout is dropped (not a skip).
  if dt >= 600 then
    Seated.fresh(B, now)
    Queue.dropWalk(db.queue)
    db.nudge.ignored = 0
    B.awayStart, B.awayFrom = nil, nil
    dt = 0
    push(acts, { t = "fresh" })
  end

  if not s.enabled then return acts end

  -- Away: no seated time and no passive Rage. Coming back decides what the time away was.
  if ctx.away then
    if not B.awayStart then
      B.awayFrom = now
      B.awayStart = math.min(now, ctx.awaySince or now)
    end
  else
    if B.awayStart then
      local dur, missed = now - B.awayStart, now - (B.awayFrom or now)
      B.awayStart, B.awayFrom = nil, nil
      local res = S.awayReturn(db, now, dur, missed, env, acts)
      if res == true then dt = 0 end -- credited: the stretch starts fresh
      asked = (res == "ask")
    end
    B.acc = B.acc + dt
    local day = History.day(db, dayKey)
    day.play = day.play + dt
    if B.acc > day.seatMax then day.seatMax = B.acc end
    if not B.restDay then Rage.passive(B.rage, dt, s.rage.full) end
  end

  -- Walkabout due (or growing while ignored).
  local level = Seated.dueLevel(B.acc, s.walk.every)
  if level > 0 and not asked and B.acc >= (B.skipUntil or 0) then
    local minutes = Seated.walkMinutes(level, s.walk.dose, s.walk.max)
    local P
    local it, created = Queue.upsertWalk(db.queue, now, minutes, level - 1, function(m)
      P = P or pickerFor(db, env, now)
      return Picker.walkSlot(P, m, nil)
    end)
    if created then
      local day = History.day(db, dayKey)
      day.w.due = day.w.due + 1
      push(acts, { t = "due", item = it })
    end
    if level - 1 > (B.rooted or 0) then
      B.rooted = level - 1
      push(acts, { t = "rooted", n = B.rooted })
    end
  end

  -- Feat of Strength earned.
  if not B.restDay and Rage.ready(B.rage, now, s.rage.cd) then
    local flavor = Rage.spend(B.rage, now)
    B.cappedNoted = nil
    local bonus = (flavor == "level") and 0.25 or 0
    local P = pickerFor(db, env, now)
    local it, created, merged = Queue.addFeat(db.queue, now, flavor, bonus, s.feat.expireH,
      function(b, fl) return Picker.featSlots(P, s.feat.slots, b, fl) end,
      function(slot, factor) Picker.rescale(env.byId, slot, factor) end)
    local day = History.day(db, dayKey)
    day.f.earn = day.f.earn + 1
    push(acts, { t = "feat", item = it, flavor = flavor, merged = merged, created = created })
  elseif not B.restDay and B.rage.v >= 100 and not B.cappedNoted then
    B.cappedNoted = true
    push(acts, { t = "rageCapped", left = Rage.cooldownLeft(B.rage, now, s.rage.cd) })
  end

  -- Expired Feats (logged, no penalty).
  for _, it in ipairs(Queue.expire(db.queue, now)) do
    for _, sl in ipairs(it.slots) do
      if not sl.o then
        History.append(db, { t = now, d = dayKey, x = sl.x, k = kindOf(env, sl.x), a = sl.a, l = 0, o = "exp",
                             s = (it.k == "W") and "walk" or "feat", p = sl.p, c = env.char, q = it.id })
      end
    end
    push(acts, { t = "expired", item = it })
  end

  if not asked then S.deliver(db, now, ctx, env, acts) end
  return acts
end

-- Moments: taxi, rest, leave (instance), combat (ended, open world), return, login --------------------------
function S.moment(db, kind, now, ctx, env)
  local acts = {}
  if not db.settings.enabled then return acts end
  if kind == "leave" then db.nudge.snoozeInst = nil end
  local shown = S.deliver(db, now, ctx, env, acts, kind, kind == "leave")
  if not shown and (kind == "taxi" or kind == "rest" or kind == "leave") then
    local B, s = db.body, db.settings
    if not Queue.get(db.queue, "W") and not B.earlyOffered and B.acc >= s.walk.every * 60 / 2
        and S.gate(db, now, ctx).may then
      B.earlyOffered = true
      push(acts, { t = "offer", moment = kind })
    end
  end
  return acts
end

-- Player actions ---------------------------------------------------------------------------------------

-- Bookkeeping when an item is fully resolved: daily quest progress if anything was done.
local function finishItem(db, it, dayKey, acts, row)
  Queue.remove(db.queue, it.id)
  if Queue.anyDone(it) then
    if row then row.cn = true end
    if Progress.onCompletion(db, dayKey) then
      local got = Progress.addRep(db, C.REP.daily, dayKey)
      if row then row.r = (row.r or 0) + got end
      push(acts, { t = "daily" })
    end
  end
end

-- Completes a slot. amount nil = the full planned amount; less = partial (never owed).
function S.complete(db, itemId, idx, amount, now, env)
  local acts = {}
  local it = Queue.byId(db.queue, itemId)
  local sl = it and it.slots[idx]
  if not sl or sl.o then return acts end
  local a = amount and math.max(0, math.floor(amount + 0.5)) or sl.a
  if a <= 0 then return S.skip(db, itemId, idx, now, env) end
  local d = env.byId[sl.x]
  local isW = (it.k == "W")
  local dayKey = dayOf(db, now)
  local before = { acc = db.body.acc, rooted = db.body.rooted, item = U.copy(it), standing = Progress.standing(db.prog.rep) }
  sl.o = (a >= sl.a) and "done" or "part"
  sl.done = a
  local row = { t = now, d = dayKey, x = sl.x, k = d and d.kind or (isW and "s" or "r"), a = a,
                l = (sl.u and sl.u > 0) and (a / sl.u) or 0, g = d and U.copy(d.g) or nil, o = sl.o,
                s = isW and "walk" or "feat", p = sl.p, c = env.char, q = it.id }
  local frac = math.min(1, a / math.max(1, sl.a))
  row.r = Progress.addRep(db, isW and C.REP.walk or U.round(C.REP.featSlot * frac), dayKey)
  History.append(db, row)
  local finished = Queue.finished(it)
  if finished then finishItem(db, it, dayKey, acts, row) end

  -- Standing activity resets the seated clock (a Walkabout needs at least a minute).
  if (Library.isStanding(d) or db.settings.filters.seatedOk) and (not isW or a >= 60) then
    local W = S.resetClock(db, now)
    if W then
      before.droppedW = U.copy(W)
      before.credRow = History.append(db, { t = now, d = dayKey, x = W.slots[1].x, k = "s", a = 0, l = 0, o = "cred",
                                            s = "move", c = env.char, q = W.id }).id
    end
  end

  local after = Progress.standing(db.prog.rep)
  if after > before.standing then push(acts, { t = "standing", name = C.STANDINGS[after].name }) end
  for _, ach in ipairs(Progress.checkAchievements(db, now)) do push(acts, { t = "achieve", a = ach }) end
  db.nudge.ignored = 0
  push(acts, { t = "done", row = row.id, item = it, slot = idx, finished = finished, undo = before })
  return acts
end

-- Reverses a completion within the undo window: history, rep, daily count, clock and the queue item.
function S.undo(db, rowId, before)
  local row = History.undo(db, rowId)
  if not row then return false end
  Progress.removeRep(db, row.r)
  if row.cn then
    local day = History.day(db, row.d)
    day.dn = math.max(0, (day.dn or 1) - 1)
  end
  if before then
    if before.credRow then History.undo(db, before.credRow) end
    db.body.acc = before.acc or db.body.acc
    db.body.rooted = before.rooted or db.body.rooted
    local function restore(item)
      if item and not Queue.byId(db.queue, item.id) and not Queue.get(db.queue, item.k) then
        if item.k == "W" then table.insert(db.queue.items, 1, item) else db.queue.items[#db.queue.items + 1] = item end
      elseif item then
        local cur = Queue.byId(db.queue, item.id)
        if cur then cur.slots = item.slots end
      end
    end
    restore(before.item)
    restore(before.droppedW)
  end
  return true
end

-- Skips a slot (idx) or the whole item (idx nil). After skipping a Walkabout the next one waits a full interval.
function S.skip(db, itemId, idx, now, env)
  local acts = {}
  local it = Queue.byId(db.queue, itemId)
  if not it then return acts end
  local dayKey = dayOf(db, now)
  for i, sl in ipairs(it.slots) do
    if not sl.o and (idx == nil or idx == i) then
      sl.o = "skip"
      History.append(db, { t = now, d = dayKey, x = sl.x, k = kindOf(env, sl.x), a = sl.a, l = 0, o = "skip",
                           s = (it.k == "W") and "walk" or "feat", p = sl.p, c = env.char, q = it.id })
    end
  end
  if it.k == "W" then db.body.skipUntil = db.body.acc + db.settings.walk.every * 60 end
  if Queue.finished(it) then finishItem(db, it, dayKey, acts, nil) end
  db.nudge.ignored = 0
  push(acts, { t = "skip", item = it })
  return acts
end

function S.swap(db, itemId, idx, now, env)
  local it = Queue.byId(db.queue, itemId)
  if not it then return nil, "gone" end
  db.nudge.ignored = 0
  return Picker.swap(pickerFor(db, env, now), it, idx)
end

function S.snooze(db, minutes, now)
  db.nudge.snoozeUntil = now + minutes * 60
  db.nudge.ignored = 0
end

function S.snoozeInstance(db)
  db.nudge.snoozeInst = true
  db.nudge.ignored = 0
end

function S.pause(db, seconds, now)
  db.nudge.pauseUntil = now + seconds
end

function S.resume(db)
  db.nudge.pauseUntil = 0
  db.nudge.snoozeUntil = 0
  db.nudge.snoozeInst = nil
end

-- Click on "acknowledge" (any interaction): resets the nudge backoff.
function S.ack(db)
  db.nudge.ignored = 0
end

-- Creates a Walkabout right now ("/tauren now" or an accepted early offer).
function S.forceWalk(db, now, env)
  local P = pickerFor(db, env, now)
  local W = Queue.upsertWalk(db.queue, now, db.settings.walk.dose, 0, function(m) return Picker.walkSlot(P, m, nil) end)
  db.nudge.lastAt = now
  db.nudge.ignored = 0
  return { { t = "toast", w = W, f = Queue.get(db.queue, "F"), moment = "manual" } }
end

-- Manual log: "/tauren log 20 pushups" or the History tab. Counts like a Feat exercise.
function S.manualLog(db, x, amount, now, env)
  local acts = {}
  local d = env.byId[x]
  amount = tonumber(amount)
  if not d or not amount or amount <= 0 then return nil, "invalid" end
  local dayKey = dayOf(db, now)
  local pct = d.walk and 100 or Library.effectivePct(d, db.settings)
  local unit = d.std * pct / 100
  local standingBefore = Progress.standing(db.prog.rep)
  local row = { t = now, d = dayKey, x = x, k = d.kind, a = math.floor(amount + 0.5), l = amount / unit,
                g = U.copy(d.g), o = "done", s = "man", p = pct, c = env.char }
  row.r = Progress.addRep(db, C.REP.manual, dayKey)
  History.append(db, row)
  row.cn = true
  if Progress.onCompletion(db, dayKey) then
    row.r = row.r + Progress.addRep(db, C.REP.daily, dayKey)
    push(acts, { t = "daily" })
  end
  if Library.isStanding(d) or db.settings.filters.seatedOk then
    local W = S.resetClock(db, now)
    if W then
      History.append(db, { t = now, d = dayKey, x = W.slots[1].x, k = "s", a = 0, l = 0, o = "cred", s = "move",
                           c = env.char, q = W.id })
    end
  end
  local after = Progress.standing(db.prog.rep)
  if after > standingBefore then push(acts, { t = "standing", name = C.STANDINGS[after].name }) end
  for _, ach in ipairs(Progress.checkAchievements(db, now)) do push(acts, { t = "achieve", a = ach }) end
  push(acts, { t = "done", row = row.id, manual = true })
  return acts
end

function S.rageEvent(db, kind, now)
  if db.body.restDay or not db.settings.enabled then return 0 end
  return Rage.event(db.body.rage, kind, now, db.settings.rage.w, C.RAGE_DEDUPE)
end

function S.setRestDay(db, on, now)
  if on then
    db.body.restDay = dayOf(db, now)
    local F = Queue.get(db.queue, "F")
    if F then Queue.remove(db.queue, F.id) end
  else
    db.body.restDay = nil
  end
end

-- Summary for the UI.
function S.status(db, now, ctx)
  local B, s = db.body, db.settings
  local seated = S.seatedNow(db, now, ctx)
  local every = s.walk.every * 60
  local cd = Rage.cooldownLeft(B.rage, now, s.rage.cd)
  return {
    seated = seated,
    every = every,
    dueIn = math.max(0, math.max(every, B.skipUntil or 0) - seated),
    rooted = B.rooted or 0,
    rage = B.rage.v,
    featCooldown = cd,
    restDay = B.restDay and true or false,
    W = Queue.get(db.queue, "W"),
    F = Queue.get(db.queue, "F"),
  }
end
