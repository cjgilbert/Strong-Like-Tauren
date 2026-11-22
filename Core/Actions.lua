local ADDON, ns = ...
local C, U = ns.C, ns.U

-- Glue between the pure Scheduler and the game/UI: ns.Do facade, ns.dispatch, chat helpers.
ns.UI = ns.UI or {}
ns.UI.Tabs = ns.UI.Tabs or {}
ns.ctx = ns.ctx or { combat = false, encounter = false, loading = false, dead = false, cinematic = false,
                     inst = "none", taxi = false, resting = false, away = false, pausedSession = false }

function ns.now()
  return ns.Api.now()
end

-- Error logging --------------------------------------------------------------------------------------------
local function logError(err)
  if ns.DB and ns.db then pcall(ns.DB.logError, ns.db, ns.now(), err) end
  return err
end

-- Runs fn(...) under xpcall (Lua 5.1 xpcall takes no extra args, hence the closure). Returns fn's results.
function ns.guard(fn, ...)
  local n, args = select("#", ...), { ... }
  local res = { xpcall(function() return fn(unpack(args, 1, n)) end, logError) }
  if res[1] then return unpack(res, 2, table.maxn(res)) end
  return nil
end

-- Chat helpers ----------------------------------------------------------------------------------------------
local PREFIX = "|cffd4a852Strong Like Tauren:|r "

function ns.say(msg)
  msg = tostring(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
  elseif print then
    print(PREFIX .. msg)
  end
end

local function rand(n)
  local rng = ns.env and ns.env.rng
  if rng then return rng:int(1, n) end
  return math.random(n)
end

-- Random line of a kind (formatted with the extra args when it has % placeholders). kind "flavor" takes a key.
function ns.quip(kind, ...)
  local list = ns.D and ns.D.QUIPS and ns.D.QUIPS[kind]
  if not list then return "" end
  local line
  if kind == "flavor" then
    line = list[...]
    if not line then return "" end
  else
    if #list == 0 then return "" end
    line = list[rand(#list)]
  end
  if select("#", ...) > 0 and kind ~= "flavor" and line:find("%%") then
    local ok, out = pcall(string.format, line, ...)
    if ok then return out end
  end
  return line
end

function ns.sound(role)
  if not (ns.db and ns.db.settings.nudge.sound) then return end
  local names = C.SOUNDS[role]
  if not names then return end
  for _, n in ipairs(names) do
    if SOUNDKIT and SOUNDKIT[n] then
      ns.Api.playSound(n)
      return
    end
  end
end

-- The due-reminder sound, on the Master channel so it is heard even with game sound effects turned down.
-- force = play even when sounds are off (the Settings "Test" button).
function ns.nudgeSound(force)
  if not ns.db then return end
  if not (force or ns.db.settings.nudge.sound) then return end
  local names = C.NUDGE_SOUNDS[ns.db.settings.nudge.soundKind] or C.NUDGE_SOUNDS.alert
  for _, n in ipairs(names) do
    if SOUNDKIT and SOUNDKIT[n] then
      ns.Api.playSound(n, "Master")
      return
    end
  end
  ns.Api.playSound(C.NUDGE_FALLBACK, "Master")
end

function ns.UI.refreshAll()
  local UI = ns.UI
  if UI.Totem and UI.Totem.Refresh then ns.guard(UI.Totem.Refresh, UI.Totem) end
  if UI.Toast and UI.Toast.Refresh then ns.guard(UI.Toast.Refresh, UI.Toast) end
  if UI.Main and UI.Main.Refresh then ns.guard(UI.Main.Refresh, UI.Main) end
  if UI.MinimapButton and UI.MinimapButton.Refresh then ns.guard(UI.MinimapButton.Refresh, UI.MinimapButton) end
end

-- Dispatch ----------------------------------------------------------------------------------------------------
local function summary(a)
  return a
end

local H = {}

function H.toast(a)
  if ns.UI.Toast and ns.UI.Toast.Show then ns.UI.Toast:Show(a.w, a.f, a.moment) end
  ns.nudgeSound()
  if FlashClientIcon then pcall(FlashClientIcon) end -- taskbar flash when the game is in the background
end

function H.feat(a)
  local line
  if a.flavor and ns.D.QUIPS.flavor[a.flavor] then line = ns.D.QUIPS.flavor[a.flavor] else line = ns.quip("feat") end
  if line and line ~= "" then ns.say(line) end
end

function H.ask(a)
  if ns.UI.Prompts then ns.UI.Prompts:AskAway(a.dur) end
end

function H.credit(a)
  if ns.UI.Prompts then ns.UI.Prompts:Credit(a) end
end

function H.offer(a)
  if ns.UI.Prompts then ns.UI.Prompts:Offer(a.moment) end
end

function H.done(a)
  ns.sound("done")
  ns.say(ns.quip("done"))
  if ns.UI.Prompts then ns.UI.Prompts:Undo(a) end
end

function H.skip()
  ns.say(ns.quip("skip"))
end

function H.daily()
  ns.say(ns.L["Daily complete: Earthmother's Calling!"])
  if ns.UI.Toast then ns.UI.Toast:Message(ns.L["Daily complete"], ns.L["Earthmother's Calling"], C.ICON) end
end

function H.standing(a)
  ns.say(("You are now %s with the %s."):format(tostring(a.name), C.FACTION))
  ns.sound("achieve")
end

function H.achieve(a)
  if ns.UI.Toast then ns.UI.Toast:Achievement(a.a) end
  ns.sound("achieve")
end

function ns.dispatch(acts)
  if type(acts) ~= "table" then return end
  for _, a in ipairs(acts) do
    local h = H[a.t]
    if h then ns.guard(h, a) end
  end
  ns.UI.refreshAll()
end

-- ns.Do ----------------------------------------------------------------------------------------------------------
local Do = {}
ns.Do = Do

local function ready()
  return ns.db and ns.env and ns.ready
end

local function define(name, fn)
  Do[name] = function(...)
    if not ready() then return nil end
    return ns.guard(fn, ...)
  end
end

local S = ns.Scheduler

define("tick", function()
  ns.dispatch(S.tick(ns.db, ns.now(), ns.ctx, ns.env))
end)

define("login", function(isReload)
  ns.dispatch(S.login(ns.db, ns.now(), ns.env, isReload))
end)

define("moment", function(kind)
  ns.dispatch(S.moment(ns.db, kind, ns.now(), ns.ctx, ns.env))
end)

define("complete", function(itemId, idx, amount)
  ns.dispatch(S.complete(ns.db, itemId, idx, amount, ns.now(), ns.env))
end)

define("skip", function(itemId, idx)
  ns.dispatch(S.skip(ns.db, itemId, idx, ns.now(), ns.env))
end)

define("swap", function(itemId, idx)
  local slot, why = S.swap(ns.db, itemId, idx, ns.now(), ns.env)
  ns.UI.refreshAll()
  return slot ~= nil, why
end)

define("snooze", function(min)
  S.snooze(ns.db, min, ns.now())
  ns.say(ns.quip("snooze", min))
  ns.UI.refreshAll()
end)

define("snoozeInstance", function()
  S.snoozeInstance(ns.db)
  ns.UI.refreshAll()
end)

define("pause", function(sec)
  S.pause(ns.db, sec, ns.now())
  ns.say(ns.quip("paused"))
  ns.UI.refreshAll()
end)

define("pauseSession", function()
  ns.ctx.pausedSession = true
  ns.say(ns.quip("paused"))
  ns.UI.refreshAll()
end)

define("resume", function()
  S.resume(ns.db)
  ns.ctx.pausedSession = false
  ns.say(ns.L["Reminders resumed."])
  ns.UI.refreshAll()
end)

define("forceWalk", function()
  ns.dispatch(S.forceWalk(ns.db, ns.now(), ns.env))
end)

define("gotUp", function()
  local row = S.credit(ns.db, ns.now(), ns.env, "up")
  ns.say(ns.L["Counted that as a break."])
  ns.UI.refreshAll()
  return row
end)

define("pauseClock", function()
  if S.pauseClock(ns.db, ns.now()) then ns.say(ns.L["Seated clock paused."]) end
  ns.UI.refreshAll()
end)

-- auto = resumed by Events because input was seen after the grace period.
define("resumeClock", function(auto)
  if S.resumeClock(ns.db, ns.now()) then
    ns.say(auto and ns.L["Welcome back! Seated clock resumed."] or ns.L["Seated clock resumed."])
  end
  ns.UI.refreshAll()
end)

define("manualLog", function(x, amount)
  local acts, err = S.manualLog(ns.db, x, amount, ns.now(), ns.env)
  if not acts then return false, err end
  ns.dispatch(acts)
  return true
end)

define("undo", function(action)
  if type(action) ~= "table" then return false end
  local ok = S.undo(ns.db, action.row, action.undo)
  ns.UI.refreshAll()
  return ok
end)

define("undoCredit", function(rowId, prevAcc)
  S.undoCredit(ns.db, rowId, prevAcc)
  ns.UI.refreshAll()
end)

define("answerAway", function(yes)
  if yes then
    S.credit(ns.db, ns.now(), ns.env, "ask")
    ns.say(ns.quip("awayCredit"))
  end
  ns.UI.refreshAll()
end)

define("setRestDay", function(on)
  S.setRestDay(ns.db, on and true or false, ns.now())
  ns.UI.refreshAll()
end)

define("setSetting", function(path, value)
  local opt = C.OPTION_BY_PATH[path]
  if not opt then return nil end
  local v = C.validate(opt, value)
  U.setPath(ns.db.settings, path, v)
  ns.UI.refreshAll()
  return v
end)

define("setGroupPct", function(group, pct)
  local gp = ns.db.settings.groupPct
  if not C.CAPPED[group] then return nil end
  if pct == nil then
    gp[group] = nil
  else
    pct = tonumber(pct)
    if not pct or pct ~= pct then return nil end
    gp[group] = U.clamp(U.round(pct), 10, 300)
  end
  ns.UI.refreshAll()
  return gp[group]
end)

define("libraryChanged", function()
  ns.env.defs, ns.env.byId = ns.Library.build(ns.D.EXERCISES, ns.db.lib)
  ns.UI.refreshAll()
end)

define("deleteRow", function(rowId)
  local row = ns.History.undo(ns.db, rowId)
  if row then ns.Progress.removeRep(ns.db, row.r) end
  ns.UI.refreshAll()
  return row ~= nil
end)

define("ack", function()
  S.ack(ns.db)
end)
