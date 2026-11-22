local ADDON, ns = ...
local C, U = ns.C, ns.U

-- /tauren and /slt
local Cmd = {}
ns.Commands = Cmd

local say = function(m) ns.say(m) end
local handlers = {}

local function findExercise(query)
  if not (ns.env and query and query ~= "") then return nil end
  local q = query:lower()
  local byId = ns.env.byId[query] or ns.env.byId[q]
  if byId then return byId end
  for _, d in ipairs(ns.env.defs) do
    if (d.name and d.name:lower() == q) or (d.pun and d.pun:lower() == q) then return d end
  end
  for _, d in ipairs(ns.env.defs) do
    if (d.name and d.name:lower():find(q, 1, true)) or (d.pun and d.pun:lower():find(q, 1, true))
        or d.id:lower():find(q, 1, true) then
      return d
    end
  end
end

function handlers.now() ns.Do.forceWalk() end
function handlers.up() ns.Do.gotUp() end

function handlers.log(arg)
  local num, name = arg:match("^(%d+%.?%d*)%s+(.+)$")
  if not num then name, num = arg:match("^(.-)%s+(%d+%.?%d*)$") end
  if not num or not name or name == "" then say("Usage: /tauren log <amount> <exercise>") return end
  local d = findExercise(U.trim(name))
  if not d then say(("No exercise matches '%s'."):format(name)) return end
  local ok, err = ns.Do.manualLog(d.id, tonumber(num))
  if ok then say(("Logged %s %s."):format(num, d.pun or d.name)) else say("Could not log that (" .. tostring(err) .. ").") end
end

function handlers.snooze(arg)
  local m = tonumber(arg) or 10
  ns.Do.snooze(U.clamp(m, 1, 240))
end

function handlers.pause(arg)
  local m = tonumber(arg)
  if m and m > 0 then ns.Do.pause(m * 60) else ns.Do.pauseSession() end
end

function handlers.resume() ns.Do.resume() end

function handlers.tier(arg)
  arg = (arg or ""):lower()
  local pct = tonumber(arg)
  if not pct then
    for _, t in ipairs(C.TIERS) do
      if t.key == arg then pct = t.pct end
    end
  end
  if not pct then
    say("Usage: /tauren tier <critter|peon|grunt|kodo|tauren|NN>")
    return
  end
  local v = ns.Do.setSetting("tier", pct)
  say(("Tier set to %s (%s%%)."):format(C.tierName(v), tostring(v)))
end

function handlers.rest(arg)
  arg = (arg or ""):lower()
  if arg == "on" then ns.Do.setRestDay(true) say("Rest day on. No Rage, no Feats today.")
  elseif arg == "off" then ns.Do.setRestDay(false) say("Rest day off.")
  else say("Usage: /tauren rest on|off") end
end

function handlers.stats()
  local db = ns.db
  local key = U.dayKey(ns.now(), db.settings.dayStart)
  local d = db.days[key]
  if d then
    say(("Today: Walkabouts %d/%d done, Feats %d done, longest sit %s."):format(
      d.w.done or 0, d.w.due or 0, d.f.done or 0, U.fmtDuration(d.seatMax or 0)))
  else
    say("Today: nothing logged yet.")
  end
  local st = ns.Progress.standing(db.prog.rep)
  say(("Standing: %s (%d rep), streak %d (best %d), %d Walkabouts, %d Feats."):format(
    C.STANDINGS[st].name, db.prog.rep, db.prog.streak.cur or 0, db.prog.streak.best or 0,
    db.totals.walks or 0, db.totals.feats or 0))
end

function handlers.selftest()
  if not (ns.SelfTest and ns.SelfTest.run) then say("Self-test not loaded.") return end
  local ok, passed, failed = pcall(ns.SelfTest.run, say)
  if not ok then say("Self-test crashed: " .. tostring(passed)) return end
  say(("Self-test: %d passed, %d failed."):format(passed or 0, failed or 0))
end

function handlers.sim(arg)
  if not (ns.Sim and ns.Sim.runAll) then say("Simulator not loaded.") return end
  arg = (arg or ""):upper()
  local ok, err
  if arg == "" or arg == "ALL" then ok, err = pcall(ns.Sim.runAll, say)
  else ok, err = pcall(ns.Sim.run, arg, say) end
  if not ok then say("Sim error: " .. tostring(err)) end
end

function handlers.debug()
  local ctx = ns.ctx
  local parts = {}
  for _, k in ipairs(U.sortedKeys(ctx)) do parts[#parts + 1] = k .. "=" .. tostring(ctx[k]) end
  say("ctx: " .. table.concat(parts, " "))
  for _, p in ipairs(ns.Api.probe()) do
    say(("  %s = %s%s"):format(p.name, tostring(p.value), p.secret and " (secret)" or ""))
  end
  if ns.db then
    local st = ns.Scheduler.status(ns.db, ns.now(), ctx)
    say(("seated %s, rage %.0f, rooted %d, gate may=%s"):format(U.fmtClock(st.seated), st.rage, st.rooted,
      tostring(ns.Scheduler.gate(ns.db, ns.now(), ctx).may)))
    local g = ns.Scheduler.gate(ns.db, ns.now(), ctx)
    local last = ns.db.nudge.lastAt or 0
    local ago = last > 0 and ("%d min ago"):format(math.floor((ns.now() - last) / 60)) or "never"
    say(("gate: may=%s why=%s; last reminder %s; limiter wait %d min"):format(tostring(g.may and true or false),
      tostring(g.why), ago, math.floor(ns.Scheduler.nudgeWait(ns.db) / 60)))
  end
end

function handlers.bug()
  local errs = ns.db and ns.db.errors or {}
  if #errs == 0 then say("No errors recorded.") return end
  for i, e in ipairs(errs) do
    say(("%d. [%s] %s"):format(i, U.date("%H:%M:%S", e.t), e.msg))
  end
end

function handlers.resetui()
  if ns.UI.Totem then ns.UI.Totem:ResetPosition() ns.UI.Totem:Show() end
  ns.Do.setSetting("minimap.angle", 200)
  ns.Do.setSetting("minimap.hide", false)
  say("UI positions reset.")
end

function handlers.help()
  say("/tauren  - toggle the window")
  say("now | up | log <n> <exercise> | snooze <min> | pause [min] | resume")
  say("tier <critter|peon|grunt|kodo|tauren|NN> | rest on|off | stats")
  say("selftest | sim <A-F|all> | debug | bug | resetui | help")
end

function Cmd.run(msg)
  if not ns.ready then say("Not ready yet.") return end
  msg = U.trim(msg or "")
  if msg == "" then
    if ns.UI.Main and ns.UI.Main.Toggle then ns.UI.Main:Toggle() else say("Main window not available.") end
    return
  end
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  local h = handlers[cmd:lower()]
  if not h then say(("Unknown command '%s'. Try /tauren help."):format(cmd)) return end
  ns.guard(h, rest)
end

SLASH_STRONGLIKETAUREN1 = "/tauren"
SLASH_STRONGLIKETAUREN2 = "/slt"
SlashCmdList["STRONGLIKETAUREN"] = function(msg) ns.guard(Cmd.run, msg) end
