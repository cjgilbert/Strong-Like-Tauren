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

-- Rage banking / Double Feats ---------------------------------------------------------------------------
case("rage: banks past 100 up to 200 (passive and events) and not beyond", function()
  local R = ns.Rage.new(0)
  for _ = 1, 360 do ns.Rage.passive(R, 15, 90, true) end -- 90 minutes of 15 s ticks: exactly 100 despite float drift
  eq(R.v, 100)
  for _ = 1, 360 do ns.Rage.passive(R, 15, 90, true) end
  eq(R.v, 200, "second 90 minutes reaches exactly 200")
  ns.Rage.passive(R, 600, 90, true); eq(R.v, 200, "passive stops at 200")
  local R2 = ns.Rage.new(150)
  near(ns.Rage.event(R2, "boss", 100, { boss = 30 }, nil, true), 30); eq(R2.v, 180)
  ns.Rage.event(R2, "level", 100, { level = 50 }, nil, true); eq(R2.v, 200, "events stop at 200")
end)

case("rage: spend leaves the remainder banked", function()
  local R = ns.Rage.new(175)
  ns.Rage.spend(R, 100, 1); eq(R.v, 75, "size 1 spends 100")
  local R2 = ns.Rage.new(200)
  ns.Rage.spend(R2, 100, 2); eq(R2.v, 0, "size 2 spends 200")
  local R3 = ns.Rage.new(150)
  ns.Rage.spend(R3, 100, 2); eq(R3.v, 0, "never below 0")
  eq(R3.lastFeatAt, 100)
  local R4 = ns.Rage.new(100)
  ns.Rage.spend(R4, 100); eq(R4.v, 0, "default size is 1")
end)

case("rage: banking off clamps at 100, including an existing higher value", function()
  local R = ns.Rage.new(0)
  ns.Rage.passive(R, 200 * 60, 90, false); eq(R.v, 100)
  local R2 = ns.Rage.new(180)
  ns.Rage.passive(R2, 15, 90, false); eq(R2.v, 100, "existing 180 clamps down")
  local R3 = ns.Rage.new(180)
  ns.Rage.event(R3, "boss", 100, { boss = 30 }, nil, false); eq(R3.v, 100)
  local db, env, now = T.world()
  db.settings.rage.bank = false
  db.body.rage.v = 180; db.body.rage.lastFeatAt = now -- cooldown running
  local acts = ns.Scheduler.tick(db, now + 15, idle(), env)
  eq(db.body.rage.v, 100, "tick clamps")
  local cap = findAct(acts, "rageCapped")
  ok(cap and not cap.bank, "capped note at 100 with banking off")
end)

case("rage: banked Rage makes a Double Feat only at 200 with nothing pending", function()
  local db, env, now = T.world()
  db.body.rage.v = 150
  local acts = ns.Scheduler.tick(db, now, idle(), env)
  local F = ns.Queue.get(db.queue, "F")
  ok(F and not F.double and #F.slots == 2, "150 gives a normal Feat")
  ok(findAct(acts, "feat") and not findAct(acts, "enraged"), "no enraged action for a normal Feat")
  near(db.body.rage.v, 50, 0.1, "spent only 100")
  -- merge: the Feat is still pending, a new earn only adds +25% and spends 100
  local t2 = now + 45 * 60
  run(db, env, now + 15, t2 - 15)
  db.body.rage.v = 200
  acts = ns.Scheduler.tick(db, t2, idle(), env)
  F = ns.Queue.get(db.queue, "F")
  ok(F.merged and not F.double and #F.slots == 2, "pending Feat merges, no Double")
  eq(F.bonus, 0.25)
  near(db.body.rage.v, 100, 0.1, "merge spent only 100, rest stays banked")
  ok(not findAct(acts, "enraged"), "no enraged action on a merge")
  eq(db.prog.enraged, 0)
end)

case("rage: Double Feat has 2 x slots exercises on distinct muscle groups and fires enraged once", function()
  local db, env, now = T.world(7)
  db.body.rage.v = 200
  local acts = ns.Scheduler.tick(db, now, idle(), env)
  local F = ns.Queue.get(db.queue, "F")
  ok(F and F.double, "double flag")
  eq(#F.slots, 4)
  local prim = {}
  for _, sl in ipairs(F.slots) do
    local p = env.byId[sl.x].primary
    ok(not prim[p], "distinct primary " .. p); prim[p] = true
  end
  local e = findAct(acts, "enraged")
  ok(e and e.item == F, "enraged action for the Double Feat")
  eq(db.prog.enraged, 1)
  near(db.body.rage.v, 0, 0.1, "spent 200")
  local db2, env2, n2 = T.world(8)
  db2.settings.feat.slots = 3
  db2.body.rage.v = 200
  ns.Scheduler.tick(db2, n2, idle(), env2)
  ok(#ns.Queue.get(db2.queue, "F").slots <= 6, "capped at 6")
  local db3, env3, n3 = T.world(9)
  db3.settings.rage.bank = false
  db3.body.rage.v = 200
  ns.Scheduler.tick(db3, n3, idle(), env3)
  ok(not ns.Queue.get(db3.queue, "F").double, "banking off: never a Double")
end)

case("rage: rageCapped fires once when the bank is full during the cooldown", function()
  local db, env, now = T.world()
  db.body.rage.v = 100
  ns.Scheduler.tick(db, now, idle(), env) -- Feat earned, cooldown starts
  local n = 0
  db.body.rage.v = 150
  for t = now + 15, now + 600, 15 do
    for _, a in ipairs(ns.Scheduler.tick(db, t, idle(), env)) do if a.t == "rageCapped" then n = n + 1 end end
  end
  eq(n, 0, "not capped at 150")
  db.body.rage.v = 200
  for t = now + 615, now + 1200, 15 do
    for _, a in ipairs(ns.Scheduler.tick(db, t, idle(), env)) do
      if a.t == "rageCapped" then n = n + 1; ok(a.bank and a.left > 0) end
    end
  end
  eq(n, 1, "once at 200")
end)

case("rage: steady ~175 Rage per cycle eventually earns a 4-slot Double Feat, muscle caps intact", function()
  local db, env, now = T.world(11)
  db.body.rage.v = 0
  local cycle, doubles, normals = 45 * 60, 0, 0
  local function finishAll(t)
    for _, it in ipairs({ unpack(db.queue.items) }) do
      for i, sl in ipairs(it.slots) do
        if not sl.o then ns.Scheduler.complete(db, it.id, i, nil, t, env) end
      end
    end
  end
  local sizes = {}
  local floor = {} -- the "nothing fits" floor slot (a Feat always has one exercise) is the one documented cap exception
  for c = 0, 11 do
    local start = now + c * cycle
    db.body.rage.v = math.min(200, db.body.rage.v + 125) -- events; passive adds ~50 over the cycle
    for t = start, start + cycle - 15, 15 do
      db.nudge.ignored = 0
      for _, a in ipairs(ns.Scheduler.tick(db, t, idle(), env)) do
        if a.t == "feat" then
          for _, sl in ipairs(a.item.slots) do
            if sl.why == "everything else is resting" then floor[a.item.id .. "|" .. sl.x] = true end
          end
          if a.item.double then
            doubles = doubles + 1
            sizes[#sizes + 1] = #a.item.slots
            local prim = {}
            for _, sl in ipairs(a.item.slots) do
              local p = env.byId[sl.x].primary
              ok(not prim[p], "distinct primaries in the Double Feat")
              prim[p] = true
            end
          else normals = normals + 1 end
        end
      end
      finishAll(t)
    end
  end
  ok(normals >= 2, "normal Feats first (" .. normals .. ")")
  ok(doubles >= 1, "a Double Feat within a few cycles (" .. doubles .. ")")
  eq(sizes[1], 4, "the Double Feat has 4 slots")
  -- per-muscle caps over the whole run: any rolling hour <= 1.5 sets, any day <= 6
  local list, byDay = {}, {}
  for _, r in ipairs(db.log.rows) do
    if (r.o == "done" or r.o == "part") and r.g and r.l and not floor[tostring(r.q) .. "|" .. r.x] then
      list[#list + 1] = r
    end
  end
  table.sort(list, function(a, b) return a.t < b.t end)
  for i, r in ipairs(list) do
    local sum = {}
    for j = i, 1, -1 do
      local q = list[j]
      if q.t <= r.t - 3600 then break end
      for g, w in pairs(q.g) do sum[g] = (sum[g] or 0) + q.l * w end
    end
    for g, v in pairs(sum) do
      if C.CAPPED[g] then ok(v <= 1.55, ("hour cap %s %.2f"):format(g, v)) end
    end
    byDay[r.d] = byDay[r.d] or {}
    if r.s == "feat" then -- the Picker caps Feat load; Walkabouts (light marching) are timed, not capped
      for g, w in pairs(r.g) do byDay[r.d][g] = (byDay[r.d][g] or 0) + r.l * w end
    end
  end
  for d, gs in pairs(byDay) do
    for g, v in pairs(gs) do if C.CAPPED[g] then ok(v <= 6.05, ("day cap %s %s %.2f"):format(g, d, v)) end end
  end
end)

case("progress: Unbridled Rage fires on the first completed Double Feat only", function()
  local db, env, now = T.world(5)
  db.body.rage.v = 100
  ns.Scheduler.tick(db, now, idle(), env)
  local F = ns.Queue.get(db.queue, "F")
  local fired
  for i = 1, #F.slots do
    for _, a in ipairs(ns.Scheduler.complete(db, F.id, i, nil, now + 60, env)) do
      if a.t == "achieve" and a.a.id == "double_1" then fired = true end
    end
  end
  ok(not fired and not db.prog.ach.double_1, "a normal Feat does not count")
  local t2 = now + 45 * 60
  db.body.rage.v = 200
  ns.Scheduler.tick(db, t2, idle(), env)
  F = ns.Queue.get(db.queue, "F")
  ok(F and F.double)
  for i = 1, #F.slots do
    for _, a in ipairs(ns.Scheduler.complete(db, F.id, i, (i == 1) and 1 or nil, t2 + 60, env)) do
      if a.t == "achieve" and a.a.id == "double_1" then fired = true end
    end
  end
  ok(fired and db.prog.ach.double_1, "fires on the first Double Feat (a partial still counts)")
  eq(db.prog.doubles, 1)
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

case("scheduler: unsnooze clears both snooze kinds and the next tick delivers", function()
  local S = ns.Scheduler
  local db, env, now = T.world()
  run(db, env, now, now + 30 * 60)
  local t = now + 30 * 60
  ok(not S.unsnooze(db, t, idle()), "unsnooze is a no-op when nothing is snoozed")
  db.nudge.ignored = 3
  db.nudge.lastAt = t - 120
  S.snooze(db, 10, t)
  ok(S.unsnooze(db, t + 5, idle()), "unsnooze returns true while snoozed")
  ok(not S.snoozed(db, t + 5, idle()) and db.nudge.snoozeUntil == 0, "timed snooze cleared")
  ok(db.nudge.snoozeEnd == true and db.nudge.ignored == 0, "snoozeEnd set, ignored reset")
  local acts = run(db, env, t + 15, t + 15)
  ok(findAct(acts, "toast"), "next tick delivers despite the limiter")
  -- until I leave
  local db2, env2 = T.world()
  run(db2, env2, now, now + 30 * 60)
  db2.nudge.lastAt = t - 120
  S.snoozeInstance(db2)
  local inst = { combat = false, inst = "party" }
  ok(S.snoozed(db2, t, inst), "snoozed inside the instance")
  ok(S.unsnooze(db2, t, inst), "unsnooze ends the instance snooze")
  ok(db2.nudge.snoozeInst == nil and db2.nudge.snoozeEnd == true, "snoozeInst cleared, snoozeEnd set")
  ok(not S.snoozed(db2, t, inst), "no longer snoozed")
end)

-- New work, reminders and the nudge log ---------------------------------------------------------------------
local function toastTimes(acts, t0)
  local out = {}
  for _, a in ipairs(acts) do if a.t == "toast" then out[#out + 1] = (a.at - t0) / 60 end end
  return out
end

case("scheduler: a Feat alone is delivered right away with default settings", function()
  local db, env, now = T.world()
  eq(db.settings.feat.delivery, "asap", "default")
  db.body.rage.v = 100; db.body.rage.lastFeatAt = 0
  local acts = ns.Scheduler.tick(db, now + 15, idle(), env)
  local t = findAct(acts, "toast")
  ok(t and t.f and not t.w, "Feat toast on the very tick it was earned")
  ok(not db.nudge.fresh, "fresh cleared by delivery")
  -- "walk" keeps the old wait: nothing is deliverable (and nothing shows) until 30 minutes have passed
  local db2, env2 = T.world()
  db2.settings.feat.delivery = "walk"
  db2.body.rage.v = 100; db2.body.rage.lastFeatAt = 0
  acts = ns.Scheduler.tick(db2, now + 15, idle(), env2)
  ok(ns.Queue.get(db2.queue, "F") and not findAct(acts, "toast"), "walk: Feat held back")
  ok(not db2.nudge.fresh, "fresh cleared when nothing was deliverable")
  local w, f = ns.Scheduler.deliverable(db2, now + 15 + 1800)
  ok(f and not w, "walk: deliverable after 30 min")
end)

case("scheduler: a new Walkabout is reminded even right after another reminder; re-nudges keep the backoff", function()
  local db, env, now = T.world()
  local due = now + 30 * 60
  db.nudge.lastAt = due - 180 -- last reminder 3 minutes before the Walkabout appears
  local times = {}
  for t = now, now + 4 * 3600, 15 do
    db.body.rage.v = 0 -- keep Feats out of this test
    for _, a in ipairs(ns.Scheduler.tick(db, t, idle(), env)) do
      if a.t == "toast" then times[#times + 1] = (t - now) / 60 end
    end
  end
  eq(times[1], 30, "fresh Walkabout reminded at once despite the limiter")
  eq(times[2] - times[1], 20, "then 20 min")
  eq(times[3] - times[2], 40, "then 40 min")
  eq(times[4] - times[3], 60, "then 60 min")
  eq(times[5] - times[4], 60, "and it stays at 60")
end)

case("scheduler: new work while the game is busy waits, then one reminder at the first safe tick", function()
  local db, env, now = T.world()
  db.body.rage.v = 100; db.body.rage.lastFeatAt = 0
  local acts = run(db, env, now + 15, now + 15 + 120, { inst = "none", combat = true })
  ok(findAct(acts, "feat") and not findAct(acts, "toast"), "Feat earned in combat, no toast")
  ok(db.nudge.fresh, "new-work flag kept while blocked")
  local t0 = now + 15 + 135
  acts = run(db, env, t0, t0 + 300, idle())
  eq(#toastTimes(acts, t0), 1, "exactly one toast after combat")
  eq(toastTimes(acts, t0)[1], 0, "at the first safe tick")
  ok(not db.nudge.fresh, "flag cleared")
end)

case("db: migration 2 turns a stored 'walk' Feat delivery into 'asap' once", function()
  local db = ns.DB.init({ v = 1, settings = { feat = { delivery = "walk" } } }, T.T0)
  eq(db.v, C.SCHEMA); eq(db.settings.feat.delivery, "asap", "migrated")
  ns.DB.MIGRATIONS[2](db)
  eq(db.settings.feat.delivery, "asap", "running it again changes nothing")
  db.settings.feat.delivery = "walk" -- chosen on purpose after the migration
  local db2 = ns.DB.init(db, T.T0)
  eq(db2.settings.feat.delivery, "walk", "later choices are respected")
  local db3 = ns.DB.init({ v = 1, settings = {} }, T.T0)
  eq(db3.settings.feat.delivery, "asap")
end)

case("scheduler: the nudge log records shown and blocked reasons without repeating a blocked one, max 20", function()
  local S = ns.Scheduler
  local db, env, now = T.world()
  run(db, env, now, now + 30 * 60 - 15, { inst = "none", combat = true }) -- nothing due yet
  local acts = run(db, env, now + 30 * 60, now + 30 * 60 + 90, { inst = "none", combat = true })
  local log = db.nudge.log
  eq(#log, 1, "six blocked ticks, one entry"); eq(log[1].r, "combat"); ok(type(log[1].t) == "number")
  run(db, env, now + 30 * 60 + 105, now + 30 * 60 + 105, idle())
  eq(#log, 2); eq(log[2].r, "shown")
  run(db, env, now + 30 * 60 + 120, now + 30 * 60 + 300, idle())
  eq(#log, 3, "limiter logged once"); eq(log[3].r, "limiter")
  -- flip between two reasons far more than 20 times
  for i = 1, 60 do
    S.tick(db, now + 31 * 60 + i * 15, (i % 2 == 0) and idle() or { inst = "none", combat = true }, env)
  end
  eq(#db.nudge.log, 20, "capped at 20")
  for i = 2, 20 do ok(db.nudge.log[i].r ~= db.nudge.log[i - 1].r or db.nudge.log[i].r == "shown", "no repeated blocked reason") end
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

-- Counted per side ---------------------------------------------------------------------------------------
case("library: sided exercises read 'each leg' / 'each side', others and timed ones do not", function()
  local L = ns.Library
  local _, byId = L.build(ns.D.EXERCISES, {})
  eq(byId.lunge.side, "leg"); eq(byId.lunge.std, 10)
  for _, id in ipairs({ "climbers", "twist", "lowjacks" }) do eq(byId[id].side, "side", id) end
  eq(byId.climbers.std, 10); eq(byId.twist.std, 10); eq(byId.lowjacks.std, 12)
  eq(L.amountText(byId.lunge, 10, "x"), "x10 each leg")
  eq(L.amountText(byId.climbers, 8), "8 each side")
  eq(L.amountText(byId.squat, 15, "x"), "x15"); eq(L.amountText(byId.squat, 15), "15")
  eq(L.amountText(byId.plank, 30), "0:30")
  eq(L.sideText(byId.squat), nil)
  eq(L.sideText({ kind = "s", side = "side" }), nil, "seconds are never sided")
  -- built-in overrides cannot change the side
  local _, b2 = L.build(ns.D.EXERCISES, { over = { lunge = { side = "side", std = 12 }, squat = { side = "leg" } } })
  eq(b2.lunge.side, "leg"); eq(b2.lunge.std, 12); eq(b2.squat.side, nil)
  -- custom exercises
  eq(L.validate({ id = "cx1", kind = "r", std = 10, g = { legs = 1 }, side = "side" }).side, "side")
  eq(L.validate({ id = "cx1", kind = "r", std = 10, g = { legs = 1 }, side = "leg" }).side, "leg")
  eq(L.validate({ id = "cx1", kind = "s", std = 10, g = { legs = 1 }, side = "side" }).side, nil, "not for seconds")
  eq(L.validate({ id = "cx1", kind = "r", std = 10, g = { legs = 1 } }).side, nil)
end)

case("codec: the per-side field round-trips and old strings stay not sided", function()
  local def = { id = "csided1", name = "Side kicks", kind = "r", std = 10, g = { legs = 1 }, side = "side" }
  local back = assert(ns.Codec.decode(ns.Codec.encode({ def })))
  eq(back[1].side, "side")
  def.side = "leg"
  eq(assert(ns.Codec.decode(ns.Codec.encode({ def })))[1].side, "leg")
  def.side = nil
  local str = ns.Codec.encode({ def })
  ok(not str:find("sd=", 1, true), "no key when not sided")
  eq(assert(ns.Codec.decode(str))[1].side, nil)
  -- a string from an older version (no sd key) and one with an unknown value
  local body = "SLT1!id=cold1,n=Old,k=r,s=10,g=legs:10,i=m"
  eq(assert(ns.Codec.decode(body .. "!" .. ns.Codec.checksum(body)))[1].side, nil)
  body = "SLT1!id=cold1,n=Old,k=r,s=10,g=legs:10,i=m,sd=zzz,future=1"
  eq(assert(ns.Codec.decode(body .. "!" .. ns.Codec.checksum(body)))[1].side, nil, "unknown value = not sided")
end)

case("db: migration 3 halves climbers, twists and step jacks everywhere, leaves lunges alone", function()
  local day1, day2 = "2026-11-20", "2026-11-21"
  local function row(id, d, x, a, o)
    return { id = id, t = T.T0, d = d, x = x, k = "r", a = a, l = 1, g = { core = 1 }, o = o or "done", s = "feat", p = 100, c = 1 }
  end
  local old = {
    v = 2,
    log = { seq = 7, ver = 0, rows = {
      row(1, day1, "climbers", 21), row(2, day1, "climbers", 20), row(3, day2, "twist", 20), row(4, day2, "lunge", 15),
      row(5, day2, "lowjacks", 1, "part"), row(6, day2, "climbers", 20, "skip"), row(7, day2, "squat", 15),
    } },
    days = {
      [day1] = { ex = { climbers = { a = 41, n = 2 } }, g = {} },
      [day2] = { ex = { twist = { a = 20, n = 1 }, lunge = { a = 15, n = 1 }, lowjacks = { a = 1, n = 1 },
                        squat = { a = 15, n = 1 } }, g = {} },
    },
    totals = { ex = { climbers = 41 + 30, twist = 20, lunge = 15, lowjacks = 1, squat = 15 }, g = {} },
    queue = { seq = 2, items = { { id = 1, k = "F", slots = {
      { x = "climbers", a = 20, l = 1, u = 20, p = 100 }, { x = "lunge", a = 10, l = 1, u = 10, p = 100 },
      { x = "twist", a = 7, l = 0.7, u = 10, p = 100, o = "done", done = 7 } } } } },
    lib = { over = { climbers = { std = 30, lo = 6, hi = 120 }, lunge = { std = 12 }, lowjacks = { pct = 80 } }, custom = {} },
  }
  local db = ns.DB.init(old, T.T0)
  eq(db.v, C.SCHEMA)
  local r = db.log.rows
  eq(r[1].a, 11, "21 -> 11 (rounds half up)"); eq(r[2].a, 10); eq(r[3].a, 10); eq(r[4].a, 15, "lunge untouched")
  eq(r[5].a, 1, "never below 1"); eq(r[6].a, 10, "skipped rows too"); eq(r[7].a, 15, "squat untouched")
  eq(db.totals.ex.climbers, 36, "21 from the kept rows + half of the 30 that older rows contributed")
  eq(db.days[day1].ex.climbers.a, 21, "day total equals the sum of its rows"); eq(db.days[day1].ex.climbers.n, 2)
  eq(db.days[day2].ex.twist.a, 10); eq(db.totals.ex.twist, 10)
  eq(db.days[day2].ex.lowjacks.a, 1); eq(db.totals.ex.lowjacks, 1)
  eq(db.days[day2].ex.lunge.a, 15); eq(db.totals.ex.lunge, 15); eq(db.totals.ex.squat, 15)
  local sl = db.queue.items[1].slots
  eq(sl[1].a, 10); near(sl[1].u, 10); eq(sl[1].l, 1, "load unchanged")
  eq(sl[2].a, 10); eq(sl[2].u, 10, "lunge slot untouched")
  eq(sl[3].a, 4, "7 -> 4"); eq(sl[3].done, 4); near(sl[3].l, 0.7, 1e-9)
  local o = db.lib.over
  eq(o.climbers.std, 15); eq(o.climbers.lo, 3); eq(o.climbers.hi, 60)
  eq(o.lunge.std, 12, "lunge override untouched"); eq(o.lowjacks.std, nil); eq(o.lowjacks.pct, 80)
  -- totals are exactly what the kept rows add up to when nothing was pruned
  local sum = 0
  for _, rw in ipairs(r) do if rw.x == "twist" and ns.History.DONE[rw.o] then sum = sum + rw.a end end
  eq(sum, db.totals.ex.twist)
  -- a database already at the new version is not converted again
  local again = ns.DB.init(db, T.T0)
  eq(again.log.rows[1].a, 11); eq(again.totals.ex.climbers, 36)
  -- and a fresh account needs no conversion
  eq(ns.DB.init(nil, T.T0).v, C.SCHEMA)
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
