local ADDON, ns = ...
local U, C = ns.U, ns.C

-- The pacing simulator: scripted play sessions driven through the real Scheduler on a fake clock.
-- /tauren sim <A-F|all> in game; luajit tools/run-tests.lua offline. Pure Lua.
local Sim = {}
ns.Sim = Sim

Sim.SCENARIOS = { "A", "B", "C", "D", "E", "F" }

local STEP = 15
local CAPPED = { "legs", "push", "pull", "core", "cardio" }

local function maxLoads(db)
  local rows, list = db.log.rows, {}
  for _, r in ipairs(rows) do
    if (r.o == "done" or r.o == "part") and r.g and r.l then list[#list + 1] = r end
  end
  table.sort(list, function(a, b) return a.t < b.t end)
  local max = {}
  for i, r in ipairs(list) do
    local sum = {}
    for j = i, 1, -1 do
      local q = list[j]
      if q.t <= r.t - 3600 then break end
      for g, w in pairs(q.g) do sum[g] = (sum[g] or 0) + q.l * w end
    end
    for g, v in pairs(sum) do
      if v > (max[g] or 0) then max[g] = v end
    end
  end
  local capped = 0
  for _, g in ipairs(CAPPED) do
    if (max[g] or 0) > capped then capped = max[g] end
  end
  return max, capped
end

local function fmt(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = (v % 1 == 0) and tostring(v) or ("%.1f"):format(v) end
  return table.concat(out, ",")
end

-- Does `got` (list of minutes) match `want` within tol minutes, same count?
local function matches(got, want, tol)
  if #got ~= #want then return false end
  for i = 1, #want do
    if math.abs(got[i] - want[i]) > tol then return false end
  end
  return true
end

local function range(from, to, step)
  local t = {}
  for v = from, to, step do t[#t + 1] = v end
  return t
end

-- Generic driver -----------------------------------------------------------------------------------------
-- spec: name, minutes, rage (start), ctx(min) -> ctx table, events = { {min, fn(S)} }, ignore (bool),
--       onAsk(S, act), finish(S, rep), expect(rep, check)
local function drive(key, spec)
  local db, env, T0 = ns.SelfTest.world(100 + key:byte(), ns.SelfTest.T0)
  db.body.rage.v = spec.rage or 0
  db.body.rage.lastFeatAt = 0
  local S = { db = db, env = env, T0 = T0, now = T0, key = key }
  local rep = { key = key, name = spec.name, popups = {}, toasts = {}, feats = {}, featFlavors = {}, walks = 0,
                due = 0, asks = 0, credits = 0, maxQueue = 0, maxWalk = 0, maxW = 0, maxF = 0, expired = 0 }
  S.rep = rep
  local events = {}
  for _, e in ipairs(spec.events or {}) do events[#events + 1] = { at = e[1] * 60, fn = e[2] } end
  table.sort(events, function(a, b) return a.at < b.at end)
  local nextEvent = 1

  local function minute(now) return (now - T0) / 60 end

  function S.handle(acts, now)
    for _, a in ipairs(acts) do
      if a.t == "toast" then
        local m = minute(now)
        rep.popups[#rep.popups + 1] = m
        rep.toasts[#rep.toasts + 1] = { min = m, w = a.w and { min = a.w.min, rooted = a.w.rooted } or nil,
          f = a.f and { bonus = a.f.bonus, merged = a.f.merged, flavor = a.f.flavor } or nil, moment = a.moment }
        if not spec.ignore then
          for _, it in ipairs({ a.w, a.f }) do
            if it then
              for i, sl in ipairs(it.slots) do
                if not sl.o then
                  local r = ns.Scheduler.complete(db, it.id, i, nil, now, env)
                  for _, ra in ipairs(r) do
                    if ra.t == "done" and it.k == "W" and ra.finished then rep.walks = rep.walks + 1 end
                  end
                end
              end
            end
          end
        end
      elseif a.t == "feat" then
        rep.feats[#rep.feats + 1] = minute(now)
        rep.featFlavors[#rep.featFlavors + 1] = a.flavor or "-"
      elseif a.t == "due" then
        rep.due = rep.due + 1
      elseif a.t == "expired" then
        rep.expired = rep.expired + 1
      elseif a.t == "ask" then
        rep.asks = rep.asks + 1
        if spec.onAsk then spec.onAsk(S, a, now) end
      elseif a.t == "credit" then
        rep.credits = rep.credits + 1
      end
    end
  end

  local function observe()
    local nW, nF = 0, 0
    for _, it in ipairs(db.queue.items) do
      if it.k == "W" then
        nW = nW + 1
        if it.min > rep.maxWalk then rep.maxWalk = it.min end
      else
        nF = nF + 1
      end
    end
    if #db.queue.items > rep.maxQueue then rep.maxQueue = #db.queue.items end
    if nW > rep.maxW then rep.maxW = nW end
    if nF > rep.maxF then rep.maxF = nF end
  end

  local steps = spec.minutes * 60 / STEP
  for k = 1, steps do
    local now = T0 + k * STEP
    S.now = now
    while events[nextEvent] and events[nextEvent].at <= now - T0 do
      S.handle(events[nextEvent].fn(S, now) or {}, now)
      nextEvent = nextEvent + 1
    end
    S.handle(ns.Scheduler.tick(db, now, spec.ctx(minute(now), T0), env), now)
    observe()
  end

  if spec.finish then spec.finish(S, rep) end
  rep.rage = db.body.rage.v
  rep.breaks = db.totals.credited
  rep.maxLoad, rep.maxCapped = maxLoads(db)
  rep.completedFeats = db.totals.feats

  rep.checks = {}
  local function check(label, cond, detail)
    rep.checks[#rep.checks + 1] = { ok = cond and true or false, msg = label .. (detail and (" (" .. detail .. ")") or "") }
  end
  spec.expect(rep, check)
  rep.pass = true
  for _, c in ipairs(rep.checks) do if not c.ok then rep.pass = false end end
  return rep
end

local function idle() return { inst = "none" } end

-- Scenarios ---------------------------------------------------------------------------------------------
local specs = {}

specs.A = {
  name = "Leveling, 3 h", minutes = 180, rage = 0,
  ctx = idle,
  events = (function()
    local ev = {}
    for m = 3, 180, 3 do ev[#ev + 1] = { m, function(S, now) ns.Scheduler.rageEvent(S.db, "quest", now) return {} end } end
    for _, m in ipairs({ 40, 100, 160 }) do
      ev[#ev + 1] = { m, function(S, now) ns.Scheduler.rageEvent(S.db, "level", now) return {} end }
    end
    return ev
  end)(),
  expect = function(rep, check)
    check("6 Walkabouts completed", rep.walks == 6, tostring(rep.walks))
    -- Rage now banks past 100, so after the ding Feat at 40 every cooldown end finds a full bar: 40/85/130/175.
    check("Feats earned near 40/85/130/175", matches(rep.feats, { 40, 85, 130, 175 }, 3), fmt(rep.feats))
    local flav = {}
    for i, f in ipairs(rep.featFlavors) do flav[i] = f or "-" end
    check("Feats flavored level, none, level, level", #flav == 4 and flav[1] == "level" and flav[2] == "-"
      and flav[3] == "level" and flav[4] == "level", table.concat(flav, ","))
    check("6 popups at 30,60..180", matches(rep.popups, range(30, 180, 30), 0.6), fmt(rep.popups))
    local withFeat, bonusOk = {}, true
    for _, t in ipairs(rep.toasts) do
      if t.f then
        withFeat[#withFeat + 1] = t.min
        local want = (t.f.flavor == "level") and 0.25 or 0
        if math.abs((t.f.bonus or 0) - want) > 1e-9 then bonusOk = false end
      end
    end
    check("Feats ride along with Walkabouts at 60/90/150/180", matches(withFeat, { 60, 90, 150, 180 }, 0.6), fmt(withFeat))
    check("level Feats carry +25%, others none", bonusOk)
    check("no capped group above 1.5 sets in any hour", rep.maxCapped <= 1.55, ("%.2f"):format(rep.maxCapped))
  end,
}

specs.B = {
  name = "Level 60, no events, 3 h", minutes = 180, rage = 0,
  ctx = idle,
  expect = function(rep, check)
    check("6 Walkabouts completed", rep.walks == 6, tostring(rep.walks))
    check("Feats earned at 90 and 180", matches(rep.feats, { 90, 180 }, 1), fmt(rep.feats))
    check("no capped group above 1.5 sets in any hour", rep.maxCapped <= 1.55, ("%.2f"):format(rep.maxCapped))
  end,
}

specs.C = {
  name = "Raid, 3 h", minutes = 180, rage = 0,
  ctx = function(m) return { inst = (m < 180) and "raid" or "none" } end,
  events = (function()
    local ev = {}
    for m = 20, 160, 20 do ev[#ev + 1] = { m, function(S, now) ns.Scheduler.rageEvent(S.db, "boss", now) return {} end } end
    for _, m in ipairs({ 60, 61, 130 }) do
      ev[#ev + 1] = { m, function(S, now) ns.Scheduler.rageEvent(S.db, "death", now) return {} end }
    end
    ev[#ev + 1] = { 180, function(S, now) return ns.Scheduler.moment(S.db, "leave", now, idle(), S.env) end }
    return ev
  end)(),
  expect = function(rep, check)
    check("one popup, on leaving", #rep.popups == 1 and math.abs(rep.popups[1] - 180) < 0.6, fmt(rep.popups))
    local t = rep.toasts[1]
    check("it holds a 5-minute Walkabout", t and t.w and t.w.min == 5, t and t.w and tostring(t.w.min))
    check("and one merged Feat at +25% (125%)", t and t.f and t.f.merged and math.abs((t.f.bonus or 0) - 0.25) < 1e-9,
      t and t.f and tostring(t.f.bonus))
    check("never more than one W and one F queued", rep.maxW <= 1 and rep.maxF <= 1)
  end,
}

specs.D = {
  name = "AFK-heavy, 2 h", minutes = 120, rage = 0,
  ctx = function(m, T0)
    if m >= 20 and m < 60 then return { inst = "none", away = true, awaySince = T0 + 20 * 60 } end
    if m >= 85 and m < 91 then return { inst = "none", away = true, awaySince = T0 + 85 * 60 } end
    return { inst = "none" }
  end,
  onAsk = function(S, act, now) ns.Scheduler.credit(S.db, now, S.env, "away") end,
  expect = function(rep, check)
    check("no Walkabout ever due", rep.due == 0 and rep.walks == 0, "due " .. rep.due)
    check("2 credited breaks", rep.breaks == 2, tostring(rep.breaks))
    check("2 prompts: one credit, one ask", rep.credits == 1 and rep.asks == 1, rep.credits .. " credit, " .. rep.asks .. " ask")
    check("no Feat", #rep.feats == 0, fmt(rep.feats))
    check("Rage between 70 and 95", rep.rage >= 70 and rep.rage <= 95, ("%.1f"):format(rep.rage))
  end,
}

specs.E = {
  name = "Never takes breaks, 4 h", minutes = 240, rage = 0, ignore = true,
  ctx = idle,
  expect = function(rep, check)
    check("popups at 30/50/90/150/210", matches(rep.popups, { 30, 50, 90, 150, 210 }, 0.6), fmt(rep.popups))
    check("queue never above 1 W + 1 F", rep.maxQueue <= 2 and rep.maxW <= 1 and rep.maxF <= 1, tostring(rep.maxQueue))
    check("Walkabout never over 5 min", rep.maxWalk <= 5, tostring(rep.maxWalk))
  end,
}

specs.F = {
  name = "Reload, then a 2-day gap", minutes = 35, rage = 100, ignore = true,
  ctx = idle,
  finish = function(S, rep)
    local db, env = S.db, S.env
    -- /reload: the SavedVariables table is handed back to DB.init
    local now = S.now
    db = ns.DB.init(db, now)
    S.db = db
    rep.reload = { acc = db.body.acc, items = #db.queue.items, hasW = ns.Queue.get(db.queue, "W") ~= nil,
                   hasF = ns.Queue.get(db.queue, "F") ~= nil }
    local rageBefore = db.body.rage.v
    local later = now + 2 * 86400
    S.now = later
    S.handle(ns.Scheduler.tick(db, later, idle(), env), later)
    local exp = 0
    for _, r in ipairs(db.log.rows) do if r.o == "exp" then exp = exp + 1 end end
    rep.gap = { acc = db.body.acc, hasW = ns.Queue.get(db.queue, "W") ~= nil, hasF = ns.Queue.get(db.queue, "F") ~= nil,
                exp = exp, rageBefore = rageBefore, rageAfter = db.body.rage.v }
  end,
  expect = function(rep, check)
    local r, g = rep.reload, rep.gap
    check("reload keeps the seated clock (~35 min)", math.abs(r.acc - 35 * 60) <= 30, ("%.0f s"):format(r.acc))
    check("reload keeps the Walkabout and the Feat", r.hasW and r.hasF and r.items == 2)
    check("after 2 days the seated clock is fresh", g.acc == 0, tostring(g.acc))
    check("the Walkabout is dropped", not g.hasW)
    check("the Feat expired, with an exp row", not g.hasF and g.exp >= 1 and rep.expired >= 1, tostring(g.exp))
    check("Rage unchanged across the gap", math.abs(g.rageAfter - g.rageBefore) < 1e-9,
      ("%.2f -> %.2f"):format(g.rageBefore, g.rageAfter))
  end,
}

Sim.specs = specs

local function summary(rep)
  local parts = {
    ("popups[%s]"):format(fmt(rep.popups)),
    ("walks %d"):format(rep.walks),
    ("feats[%s]"):format(fmt(rep.feats)),
    ("breaks %d"):format(rep.breaks),
    ("prompts ask %d/credit %d"):format(rep.asks, rep.credits),
    ("rage %.0f"):format(rep.rage),
    ("maxQ %d"):format(rep.maxQueue),
    ("maxWalk %dm"):format(rep.maxWalk),
  }
  local loads = {}
  for _, g in ipairs(CAPPED) do loads[#loads + 1] = ("%s %.2f"):format(g, rep.maxLoad[g] or 0) end
  parts[#parts + 1] = "load/h " .. table.concat(loads, " ")
  return ("%s %s: %s"):format(rep.key, rep.name, table.concat(parts, "; "))
end

function Sim.run(key)
  key = tostring(key):upper()
  local spec = specs[key]
  if not spec then return nil, "unknown scenario" end
  local ok, rep = pcall(drive, key, spec)
  if not ok then
    return { key = key, name = spec.name, pass = false, error = tostring(rep), checks = { { ok = false, msg = "error: " .. tostring(rep) } } }
  end
  rep.summary = summary(rep)
  return rep
end

function Sim.runAll(print)
  print = print or function() end
  local passed, failed = 0, 0
  for _, key in ipairs(Sim.SCENARIOS) do
    local rep = Sim.run(key)
    print(rep.summary or (key .. " " .. tostring(rep.error)))
    for _, c in ipairs(rep.checks) do
      print(("  %s %s"):format(c.ok and "PASS" or "FAIL", c.msg))
      if c.ok then passed = passed + 1 else failed = failed + 1 end
    end
  end
  return passed, failed
end
