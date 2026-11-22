local ADDON, ns = ...
local U, C = ns.U, ns.C

-- /tauren selftest: unit tests for the pure logic, run under a fake clock with a throwaway database.
-- Also runs offline: luajit tools/run-tests.lua
local T = {}
ns.SelfTest = T

local cases = {}
local function case(name, fn) cases[#cases + 1] = { name = name, fn = fn } end

local function ok(cond, msg) if not cond then error("expected true: " .. (msg or ""), 2) end end
local function eq(a, b, msg)
  if a ~= b then error(("expected %s, got %s %s"):format(tostring(b), tostring(a), msg or ""), 2) end
end
local function near(a, b, eps, msg)
  if type(a) ~= "number" or math.abs(a - b) > (eps or 1e-6) then
    error(("expected ~%s, got %s %s"):format(tostring(b), tostring(a), msg or ""), 2)
  end
end

T.T0 = 1795262400 -- 2026-11-21 12:00 UTC: a fixed start so results are reproducible

-- A fresh world: database, library, environment and an idle game context.
function T.world(seed, now)
  now = now or T.T0
  local db = ns.DB.init(nil, now)
  db.settings.firstRun = false
  local defs, byId = ns.Library.build(ns.D.EXERCISES, db.lib)
  local env = { defs = defs, byId = byId, rng = U.rng(seed or 42), char = 1 }
  return db, env, now
end

local function idle() return { inst = "none" } end

local function findAct(acts, t)
  for _, a in ipairs(acts) do if a.t == t then return a end end
end

-- Advances the world in 15 s ticks, returning all actions.
local function run(db, env, from, to, ctx)
  local all = {}
  for now = from, to, 15 do
    for _, a in ipairs(ns.Scheduler.tick(db, now, ctx or idle(), env)) do
      a.at = now
      all[#all + 1] = a
    end
  end
  return all
end

-- Util / DB --------------------------------------------------------------------------------------------
case("util: day key rolls over at 4 am local time", function()
  local lt = U.date("*t", T.T0)
  local at3 = T.T0 - (lt.hour - 3) * 3600 - lt.min * 60 - lt.sec
  local at5 = at3 + 2 * 3600
  eq(U.dayKey(at3, 4), U.date("%Y-%m-%d", at3 - 86400), "03:00 belongs to the previous day")
  eq(U.dayKey(at5, 4), U.date("%Y-%m-%d", at5), "05:00 belongs to today")
end)

case("util: rounding helpers", function()
  eq(U.round5(12), 10); eq(U.round5(13), 15); eq(U.round5(37.5), 40); eq(U.round(2.5), 3); eq(U.round(2.49), 2)
  eq(U.fmtClock(65), "1:05"); eq(U.fmtClock(3725), "1:02:05"); eq(U.fmtDuration(3900), "1h 05m")
end)

case("db: settings repair clamps and replaces bad values", function()
  local s = ns.DB.repairSettings({ tier = 999, walk = { every = "x", dose = 2.4 }, filters = { quiet = "yes" },
                                   dungeon = "nope", groupPct = { legs = 150, push = "x", bogus = 50 } })
  eq(s.tier, 300); eq(s.walk.every, 30); eq(s.walk.dose, 2); eq(s.filters.quiet, false); eq(s.dungeon, "hold")
  eq(s.groupPct.legs, 150); eq(s.groupPct.push, nil); eq(s.groupPct.bogus, nil)
  eq(s.cap.hour, 1.5); eq(s.rage.w.death, 35)
end)

case("db: garbage saved variables load cleanly", function()
  local db = ns.DB.init("hello", T.T0)
  eq(db.v, C.SCHEMA)
  local db2, note = ns.DB.init({ foo = 1 }, T.T0)
  eq(note, "unrecognised"); ok(db2.broken and db2.broken.foo == 1, "kept the unknown table")
  local db3 = ns.DB.init({ v = 1, settings = "x", body = { acc = "nope", rage = 7 },
    log = { rows = { 1, { t = 5 }, { t = T.T0, x = "squat", o = "done", d = "2026-11-21" } } },
    queue = { items = { { k = "W" }, { k = "F", slots = { { x = "squat", a = 10 } } } } } }, T.T0)
  eq(#db3.log.rows, 1, "bad rows dropped"); eq(db3.body.acc, 0); eq(type(db3.body.rage), "table")
  eq(#db3.queue.items, 1, "bad queue items dropped"); eq(db3.settings.tier, 100)
end)

case("db: character key is stable and re-links by GUID", function()
  local db = ns.DB.init(nil, T.T0)
  local rng = U.rng(7)
  local cdb, idx = ns.DB.initChar(db, nil, { name = "Bloodhoof Runner", guid = "Player-1-AAA" }, rng)
  local _, idx2 = ns.DB.initChar(db, cdb, { name = "Bloodhoof Runner" }, rng)
  eq(idx, idx2, "same file keeps the index")
  local _, idx3 = ns.DB.initChar(db, nil, { guid = "Player-1-AAA" }, rng)
  eq(idx, idx3, "lost file re-linked by GUID")
  local _, idx4 = ns.DB.initChar(db, nil, { guid = "Player-1-BBB" }, rng)
  ok(idx4 ~= idx, "another character gets a new index")
end)

-- Codec ------------------------------------------------------------------------------------------------
case("codec: every built-in round-trips", function()
  local defs = ns.Library.build(ns.D.EXERCISES, {})
  local str = ns.Codec.encode(defs)
  ok(not str:find("|", 1, true), "no pipe characters")
  local back, bad = ns.Codec.decode(str)
  ok(back, bad); eq(#back, #defs)
  for i, d in ipairs(defs) do
    local b = back[i]
    eq(b.id, d.id); eq(b.kind, d.kind); eq(b.std, d.std); eq(b.needs, d.needs); eq(b.walk, d.walk)
    for g, w in pairs(d.g) do near(b.g[g], w, 0.051, d.id .. " " .. g) end
    for f in pairs(d.flags) do ok(b.flags[f], d.id .. " flag " .. f) end
  end
end)

case("codec: reserved characters, UTF-8 and pipes", function()
  local def = { id = "cweird1", name = "Ünïcødé |cffff0000 ~+!;,=:/%t", kind = "s", std = 30,
                g = { core = 1 }, flags = { floor = true }, tags = { death = true } }
  local str = ns.Codec.encode({ def })
  ok(not str:find("|", 1, true), "escaped")
  local back = assert(ns.Codec.decode(str))
  eq(back[1].name, "Ünïcødé cffff0000 ~+!;,=:/%t", "pipe stripped, rest intact")
  ok(back[1].tags.death and back[1].flags.floor)
end)

case("codec: damaged, foreign and future strings are rejected", function()
  local str = ns.Codec.encode({ ns.D.EXERCISES[8] })
  local broken = str:sub(1, 10) .. (str:sub(11, 11) == "a" and "b" or "a") .. str:sub(12)
  local r, why = ns.Codec.decode(broken)
  ok(r == nil and why:find("damaged"), "checksum catches a one-character change")
  r = ns.Codec.decode("hello world"); ok(r == nil)
  local body = "SLT9!id=x,n=x,k=r,s=5,g=legs:10"
  r, why = ns.Codec.decode(body .. "!" .. ns.Codec.checksum(body))
  ok(r == nil and why:find("newer"), "newer version")
end)

-- Rage -------------------------------------------------------------------------------------------------
case("rage: diminishing returns 10 / 6.67 / 5 and a 60-minute window", function()
  local R, w = ns.Rage.new(0), { quest = 10 }
  near(ns.Rage.event(R, "quest", 1000, w), 10)
  near(ns.Rage.event(R, "quest", 1010, w), 10 / 1.5)
  near(ns.Rage.event(R, "quest", 1020, w), 5)
  near(ns.Rage.event(R, "quest", 1000 + 3600 + 15, w), 10 / 1.5, 1e-6, "older events leave the window")
end)

case("rage: Feat cooldown blocks at 44:59 and allows at 45:00", function()
  local R = ns.Rage.new(100)
  R.lastFeatAt = 5000
  ok(not ns.Rage.ready(R, 5000 + 45 * 60 - 1, 45))
  ok(ns.Rage.ready(R, 5000 + 45 * 60, 45))
end)

case("rage: gains while capped still choose the flavor", function()
  local R = ns.Rage.new(100)
  ns.Rage.event(R, "death", 100, { death = 35 })
  eq(R.v, 100)
  eq(ns.Rage.spend(R, 200), "death")
  eq(R.v, 0)
  local R2 = ns.Rage.new(0)
  ns.Rage.event(R2, "death", 100, { death = 35 }, C.RAGE_DEDUPE)
  eq(ns.Rage.event(R2, "death", 110, { death = 35 }, C.RAGE_DEDUPE), 0, "double death event ignored")
end)

-- Seated clock -----------------------------------------------------------------------------------------
case("login: 2 h offline starts fresh and drops the Walkabout", function()
  local db, env, now = T.world()
  run(db, env, now, now + db.settings.walk.every * 60 + 60)
  ok(ns.Queue.get(db.queue, "W"), "walkabout pending")
  ok(db.body.acc > 0)
  db.body.lastTick = now + 100 -- saved at logout
  local t = now + 100 + 7200
  local acts = ns.Scheduler.login(db, t, env, false)
  eq(db.body.acc, 0); ok(findAct(acts, "fresh"))
  ok(not ns.Queue.get(db.queue, "W"), "walkabout dropped")
  eq(ns.Scheduler.seatedNow(db, t, idle()), 0)
end)

case("login: 5 min offline keeps acc but does not add the gap", function()
  local db, env, now = T.world()
  run(db, env, now, now + 900)
  local acc = db.body.acc
  local last = db.body.lastTick
  ns.Scheduler.login(db, last + 300, env, false)
  eq(db.body.acc, acc)
  near(ns.Scheduler.seatedNow(db, last + 300, idle()), acc, 1e-6)
  ns.Scheduler.tick(db, last + 315, idle(), env)
  near(db.body.acc, acc + 15, 1e-6)
end)

case("login: /reload keeps counting", function()
  local db, env, now = T.world()
  run(db, env, now, now + 900)
  local acc, last = db.body.acc, db.body.lastTick
  ns.Scheduler.login(db, last + 8, env, true)
  ns.Scheduler.tick(db, last + 8, idle(), env)
  near(db.body.acc, acc + 8, 1e-6)
end)

case("seatedNow extrapolates at most one tick", function()
  local db, env, now = T.world()
  run(db, env, now, now + 300)
  local acc, last = db.body.acc, db.body.lastTick
  near(ns.Scheduler.seatedNow(db, last + 10, idle()), acc + 10, 1e-6)
  near(ns.Scheduler.seatedNow(db, last + 7200, idle()), acc + ns.Scheduler.TICK_CAP, 1e-6)
end)

case("pause: 10 min paused changes nothing; resume continues; no toast", function()
  local db, env, now = T.world()
  local every = db.settings.walk.every * 60
  run(db, env, now, now + every - 30) -- nearly due
  local t = db.body.lastTick
  local acc, rage = db.body.acc, db.body.rage.v
  ok(ns.Scheduler.pauseClock(db, t + 5), "pauses")
  ok(not ns.Scheduler.pauseClock(db, t + 6), "second pause is a no-op")
  local frozen = db.body.acc
  ok(frozen >= acc and frozen <= acc + 5 + 1e-6, "pause banks at most what was shown")
  ok(ns.Scheduler.gate(db, t + 6, idle()).paused and not ns.Scheduler.gate(db, t + 6, idle()).may, "gate reports paused")
  local acts = run(db, env, t + 15, t + 15 + 600, { inst = "none", away = true, awaySince = t })
  eq(db.body.acc, frozen, "acc unchanged")
  eq(db.body.rage.v, rage, "rage unchanged")
  ok(not findAct(acts, "toast") and not findAct(acts, "ask") and not findAct(acts, "credit") and not findAct(acts, "due"),
    "no toast, prompt or due while paused")
  eq(ns.Scheduler.seatedNow(db, t + 700, idle()), frozen, "seatedNow is frozen")
  local resumeAt = t + 15 + 600
  ok(ns.Scheduler.resumeClock(db, resumeAt) >= 600, "resume reports pause length")
  ok(not ns.Scheduler.resumeClock(db, resumeAt), "resume when not paused is nil")
  ns.Scheduler.tick(db, resumeAt + 15, idle(), env)
  near(db.body.acc, frozen + 15, 1e-6, "clock continues from where it was")
end)

case("pause: stays paused across /reload; a 10+ min gap at login clears it", function()
  local db, env, now = T.world()
  run(db, env, now, now + 300)
  ns.Scheduler.pauseClock(db, db.body.lastTick)
  local acc, at = db.body.acc, db.body.paused
  ok(at, "paused stamp stored in body")
  local last = db.body.lastTick
  ns.Scheduler.login(db, last + 8, env, true)
  eq(db.body.paused, at, "reload keeps the pause")
  ns.Scheduler.tick(db, last + 20, idle(), env)
  eq(db.body.acc, acc)
  ns.Scheduler.login(db, last + 8 + 3600, env, false)
  eq(db.body.paused, nil, "fresh login clears the pause"); eq(db.body.acc, 0)
end)

case("pause: I got up clears the pause and resets the clock", function()
  local db, env, now = T.world()
  run(db, env, now, now + 600)
  ns.Scheduler.pauseClock(db, db.body.lastTick)
  ok(db.body.acc > 0)
  ns.Scheduler.credit(db, db.body.lastTick + 60, env, "up")
  eq(db.body.paused, nil); eq(db.body.acc, 0)
  ns.Scheduler.tick(db, db.body.lastTick + 15, idle(), env)
  near(db.body.acc, 15, 1e-6, "clock runs again")
end)

case("seated: 599 s gap continues, 600 s starts fresh", function()
  local db, env, now = T.world()
  run(db, env, now, now + 600)
  local acc = db.body.acc
  ns.Scheduler.tick(db, now + 600 + 599, idle(), env)
  near(db.body.acc, acc + 599, 1e-6)
  local acts = ns.Scheduler.tick(db, now + 600 + 599 + 600, idle(), env)
  eq(db.body.acc, 0); ok(findAct(acts, "fresh"))
end)

case("seated: a backwards clock adds nothing", function()
  local db, env, now = T.world()
  run(db, env, now, now + 300)
  local acc = db.body.acc
  ns.Scheduler.tick(db, now + 100, idle(), env)
  eq(db.body.acc, acc)
end)

case("seated: Rooted stacks at 45 and 60 minutes", function()
  eq(ns.Seated.dueLevel(29 * 60, 30), 0); eq(ns.Seated.dueLevel(30 * 60, 30), 1)
  eq(ns.Seated.dueLevel(45 * 60, 30), 2); eq(ns.Seated.dueLevel(60 * 60, 30), 3)
  eq(ns.Seated.walkMinutes(3, 2, 5), 4); eq(ns.Seated.walkMinutes(9, 2, 5), 5)
end)

case("seated: away 2 / 5 / 15 minutes", function()
  local db, env, now = T.world()
  run(db, env, now, now + 600)
  local base = db.body.acc
  local t = now + 600
  local away = { inst = "none", away = true, awaySince = t }
  run(db, env, t + 15, t + 120, away)
  local acts = ns.Scheduler.tick(db, t + 135, idle(), env)
  ok(not findAct(acts, "ask"), "2 minutes: nothing to ask")
  near(db.body.acc, base + 135, 1e-6, "short away counts as sitting")
  t = t + 150
  run(db, env, t, t + 300, { inst = "none", away = true, awaySince = t })
  acts = ns.Scheduler.tick(db, t + 315, idle(), env)
  ok(findAct(acts, "ask"), "5 minutes: ask")
  t = t + 330
  run(db, env, t, t + 900, { inst = "none", away = true, awaySince = t })
  acts = ns.Scheduler.tick(db, t + 915, idle(), env)
  local cr = findAct(acts, "credit")
  ok(cr, "15 minutes: credited"); eq(db.body.acc, 0)
  ns.Scheduler.undoCredit(db, cr.row, cr.prevAcc)
  ok(db.body.acc > 0, "'I was sitting' restores the clock")
end)

-- Picker -----------------------------------------------------------------------------------------------
case("picker: every filter and equipment combination yields a Walkabout and a Feat", function()
  local equipSets = { {}, { chair = true, wall = true, stairs = true, bar = true, band = true, dumbbells = true } }
  for mask = 0, 15 do
    for _, eqp in ipairs(equipSets) do
      local db, env, now = T.world(mask + 1)
      db.settings.filters = { quiet = mask % 2 == 1, noFloor = math.floor(mask / 2) % 2 == 1,
                              wrists = math.floor(mask / 4) % 2 == 1, seatedOk = math.floor(mask / 8) % 2 == 1 }
      db.settings.equip = eqp
      local P = ns.Picker.context(db, env.defs, env.byId, now, env.rng)
      local w = ns.Picker.walkMove(P)
      ok(w and w.walk, "walk move for mask " .. mask)
      local slots = ns.Picker.featSlots(P, 2, 0, nil)
      ok(#slots >= 1, "feat for mask " .. mask)
      for _, sl in ipairs(slots) do
        local d = env.byId[sl.x]
        ok(ns.Library.allowed(d, db.settings) or sl.x == "march", "respects filters: " .. sl.x)
      end
    end
  end
end)

case("picker: two slots on different muscle groups, never the previous pick", function()
  for seed = 1, 25 do
    local db, env, now = T.world(seed)
    ns.History.append(db, { t = now - 7200, d = U.dayKey(now - 7200, 4), x = "squat", k = "r", a = 15, l = 1,
                            g = { legs = 1, core = 0.1 }, o = "done", s = "feat", p = 100, c = 1 })
    local P = ns.Picker.context(db, env.defs, env.byId, now, env.rng)
    local slots = ns.Picker.featSlots(P, 2, 0, nil)
    eq(#slots, 2)
    ok(env.byId[slots[1].x].primary ~= env.byId[slots[2].x].primary, "different groups")
    ok(slots[1].x ~= "squat" and slots[2].x ~= "squat", "previous pick avoided")
  end
end)

case("picker: hourly cap blocks a tired muscle group", function()
  for seed = 1, 20 do
    local db, env, now = T.world(seed)
    ns.History.append(db, { t = now - 600, d = U.dayKey(now - 600, 4), x = "lunge", k = "r", a = 15, l = 1.5,
                            g = { legs = 1 }, o = "done", s = "feat", p = 100, c = 1 })
    local P = ns.Picker.context(db, env.defs, env.byId, now, env.rng)
    for _, sl in ipairs(ns.Picker.featSlots(P, 3, 0, nil)) do
      ok(not (env.byId[sl.x].g.legs or 0 > 0) or sl.x == "march", "no legs after 1.5 sets: " .. sl.x)
    end
  end
end)

case("picker: amounts round to reps and 5-second steps", function()
  local _, env = T.world()
  local squat, plank = env.byId.squat, env.byId.plank
  eq((ns.Picker.amount(squat, 150, 1)), 23)
  eq((ns.Picker.amount(squat, 25, 1)), 4)
  eq((ns.Picker.amount(plank, 125, 1)), 40)
  eq((ns.Picker.amount(plank, 25, 1)), 10, "clamped to the exercise minimum")
  local a, l = ns.Picker.amount(squat, 100, 1)
  eq(a, 15); near(l, 1)
end)

case("picker: swap keeps the load and stops after 3", function()
  local db, env, now = T.world(3)
  local P = ns.Picker.context(db, env.defs, env.byId, now, env.rng)
  local item = { k = "F", slots = ns.Picker.featSlots(P, 2, 0.25, nil) }
  local sets = item.slots[1].sets
  local seen = { [item.slots[1].x] = true }
  for i = 1, 3 do
    local new = ns.Picker.swap(P, item, 1)
    ok(new, "swap " .. i); near(new.sets, sets, 1e-9); ok(not seen[new.x], "new exercise each time")
    seen[new.x] = true
  end
  local none, why = ns.Picker.swap(P, item, 1)
  ok(none == nil and why == "limit")
end)

-- Queue / History / Progress -----------------------------------------------------------------------------
case("queue: a second Feat merges +25% only once", function()
  local db, env, now = T.world()
  db.body.rage.v = 100
  local acts = ns.Scheduler.tick(db, now, idle(), env)
  local F = ns.Queue.get(db.queue, "F")
  ok(F and findAct(acts, "feat"))
  local a1 = F.slots[1].a
  run(db, env, now + 15, now + 45 * 60 - 15)
  db.body.rage.v = 100
  run(db, env, now + 45 * 60, now + 45 * 60)
  eq(F.bonus, 0.25); ok(F.slots[1].a >= a1, "scaled up")
  run(db, env, now + 45 * 60 + 15, now + 90 * 60 - 15)
  db.body.rage.v = 100
  run(db, env, now + 90 * 60, now + 90 * 60)
  eq(F.bonus, 0.25, "only once"); eq(#db.queue.items, 2, "never more than one W and one F")
end)

case("queue: Feats expire after 3 hours without penalty", function()
  local db, env, now = T.world()
  db.body.rage.v = 100
  ns.Scheduler.tick(db, now, idle(), env)
  local rep = db.prog.rep
  local acts = ns.Scheduler.tick(db, now + 3 * 3600 + 1, { inst = "none" }, env) -- gap -> fresh, then expiry
  ok(findAct(acts, "expired")); eq(ns.Queue.get(db.queue, "F"), nil); eq(db.prog.rep, rep)
end)

case("queue: the Walkabout never exceeds 5 minutes", function()
  local db, env, now = T.world()
  run(db, env, now, now + 4 * 3600, { inst = "raid" })
  local W = ns.Queue.get(db.queue, "W")
  eq(W.min, 5); eq(W.slots[1].a, 300); ok(W.rooted >= 10)
end)

case("history: undo exactly reverses, pruning keeps totals", function()
  local db, env, now = T.world()
  local function snapshot() return ns.U.copy(db.totals) end
  local before = snapshot()
  local r = ns.History.append(db, { t = now, d = U.dayKey(now, 4), x = "squat", k = "r", a = 15, l = 1,
                                    g = { legs = 1, core = 0.1 }, o = "done", s = "feat", p = 100, c = 1 })
  eq(db.totals.ex.squat, 15)
  ns.History.undo(db, r.id)
  eq(db.totals.ex.squat, 0); near(db.totals.g.legs, before.g.legs or 0)
  for i = 1, 10 do
    local t = now - (100 + i) * 86400
    ns.History.append(db, { t = t, d = U.dayKey(t, 4), x = "pushup", k = "r", a = 10, l = 1, g = { push = 1 },
                            o = "done", s = "feat", p = 100, c = 1 })
  end
  table.sort(db.log.rows, function(a, b) return a.t < b.t end)
  local totals = snapshot()
  eq(ns.History.prune(db, now), 10)
  eq(db.totals.ex.pushup, totals.ex.pushup); eq(#db.log.rows, 0)
end)

case("scheduler: completing work logs it, grants rep and resets the clock; undo restores", function()
  local db, env, now = T.world()
  run(db, env, now, now + 30 * 60)
  local W = ns.Queue.get(db.queue, "W")
  ok(W, "Walkabout due at 30 min")
  local acts = ns.Scheduler.complete(db, W.id, 1, nil, now + 30 * 60 + 5, env)
  local done = findAct(acts, "done")
  ok(done and done.finished); eq(db.body.acc, 0); eq(db.prog.rep, C.REP.walk); eq(db.totals.walks, 1)
  ns.Scheduler.undo(db, done.row, done.undo)
  eq(db.totals.walks, 0); eq(db.prog.rep, 0); ok(ns.Queue.get(db.queue, "W"), "Walkabout back in the Totem")
  ok(db.body.acc > 0, "clock restored")
end)

case("scheduler: a partial is logged as done-so-far and never owed", function()
  local db, env, now = T.world()
  db.body.rage.v = 100
  ns.Scheduler.tick(db, now, idle(), env)
  local F = ns.Queue.get(db.queue, "F")
  local planned = F.slots[1].a
  ns.Scheduler.complete(db, F.id, 1, math.max(1, math.floor(planned / 2)), now + 10, env)
  eq(F.slots[1].o, planned > 1 and "part" or "done")
  ns.Scheduler.skip(db, F.id, nil, now + 20, env)
  eq(ns.Queue.get(db.queue, "F"), nil, "item resolved, nothing owed")
end)

case("scheduler: quiet in combat and dungeons, nudges once free", function()
  local db, env, now = T.world()
  local acts = run(db, env, now, now + 30 * 60, { inst = "none", combat = true })
  ok(not findAct(acts, "toast"), "no toast in combat")
  local m = ns.Scheduler.moment(db, "combat", now + 30 * 60 + 15, idle(), env)
  ok(findAct(m, "toast"), "toast after combat")
  local db2, env2 = T.world()
  acts = run(db2, env2, now, now + 40 * 60, { inst = "party" })
  ok(not findAct(acts, "toast"), "held in a dungeon")
  m = ns.Scheduler.moment(db2, "leave", now + 40 * 60 + 15, idle(), env2)
  ok(findAct(m, "toast"), "toast on leaving")
end)

case("scheduler: snooze hides work, ends with one prompt delivery that still respects the gates", function()
  local S = ns.Scheduler
  local db, env, now = T.world()
  run(db, env, now, now + 30 * 60) -- a Walkabout is due and was delivered once
  local t = now + 30 * 60
  ok(ns.Queue.get(db.queue, "W"), "walkabout pending")
  db.nudge.lastAt = t - 120 -- last toast 2 min before the snooze
  local logs = #db.log.rows
  S.snooze(db, 10, t)
  ok(S.snoozed(db, t + 1, idle()) and not S.snoozed(db, t + 601, idle()), "snoozed() follows the timer")
  db.body.rage.v = 100 -- a Feat is earned during the snooze
  local acts = run(db, env, t + 15, t + 10 * 60 - 15)
  ok(not findAct(acts, "toast"), "no toast during the snooze")
  ok(ns.Queue.get(db.queue, "F"), "the Feat joined the queue quietly")
  local seat = db.body.acc
  local end1 = run(db, env, t + 10 * 60, t + 10 * 60)
  local toast = findAct(end1, "toast")
  ok(toast, "toast fires at 10:00 despite the limiter")
  ok(toast.f, "the Feat earned during the snooze is included")
  eq(#db.log.rows, logs, "snoozing logged nothing")
  ok(db.body.acc >= seat, "seated clock kept running")
  -- snooze ends while in combat: waits for the combat moment (limiter bypassed there too)
  local db2, env2 = T.world()
  run(db2, env2, now, now + 30 * 60)
  db2.nudge.lastAt = t - 120
  S.snooze(db2, 10, t)
  local a2 = run(db2, env2, t + 15, t + 11 * 60, { inst = "none", combat = true })
  ok(not findAct(a2, "toast"), "no toast while in combat at snooze end")
  local m = S.moment(db2, "combat", t + 11 * 60 + 15, idle(), env2)
  ok(findAct(m, "toast"), "toast on the combat moment")
  ok(not db2.nudge.snoozeEnd, "flag cleared after delivery")
end)

case("progress: streak survives days off, breaks on a played day without the daily", function()
  local db = T.world()
  local function day(k, play, dq) db.days[k] = { ex = {}, g = {}, w = { due = 0, done = 0, skip = 0, cred = 0 },
    f = { earn = 0, done = 0, skip = 0, exp = 0 }, seatMax = 0, play = play, dn = 0, dq = dq } end
  day("2026-11-01", 3600, false)
  for _ = 1, 3 do ns.Progress.onCompletion(db, "2026-11-01") end
  eq(db.prog.streak.cur, 1)
  day("2026-11-03", 3600, false)
  for _ = 1, 3 do ns.Progress.onCompletion(db, "2026-11-03") end
  eq(db.prog.streak.cur, 2, "a day off (11-02) doesn't break it")
  day("2026-11-04", 3600, false)
  day("2026-11-05", 3600, false)
  for _ = 1, 3 do ns.Progress.onCompletion(db, "2026-11-05") end
  eq(db.prog.streak.cur, 1, "played 11-04 without the daily")
  eq(db.prog.streak.best, 2)
end)

case("progress: reputation standings and the daily cap", function()
  local db = T.world()
  local gained, newSt = ns.Progress.addRep(db, 500, "2026-11-21")
  eq(gained, 500); eq(newSt, C.STANDINGS[2].name)
  gained = ns.Progress.addRep(db, 500, "2026-11-21")
  eq(gained, 100, "600 per day")
  gained = ns.Progress.addRep(db, 50, "2026-11-22")
  eq(gained, 50, "cap resets the next day")
end)

case("progress: achievements fire once", function()
  local db, env, now = T.world()
  db.totals.walks = 1
  local got = ns.Progress.checkAchievements(db, now)
  eq(#got, 1); eq(got[1].id, "first_walk")
  eq(#ns.Progress.checkAchievements(db, now), 0)
end)

-- Runner -----------------------------------------------------------------------------------------------
function T.run(print)
  print = print or function() end
  local passed, failed, failures = 0, 0, {}
  for _, c in ipairs(cases) do
    local good, err = pcall(c.fn)
    if good then passed = passed + 1 else
      failed = failed + 1
      failures[#failures + 1] = c.name .. ": " .. tostring(err)
      print("|cffff5555FAIL|r " .. c.name .. ": " .. tostring(err))
    end
  end
  return passed, failed, failures
end

T.cases = cases
