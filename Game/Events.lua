local ADDON, ns = ...
local C, Api = ns.C, ns.Api

-- Keeps ns.ctx current, detects transitions ("moments"), feeds Rage events and drives the 15 s ticker.
local E = {}
ns.Events = E

local ctx = ns.ctx
local AWAY_IDLE = 180
local primed = false
local lastCx, lastCy
local combatToken = 0

local function now() return ns.now() end

local function moment(kind)
  if ns.Do and ns.Do.moment then ns.Do.moment(kind) end
end

local PAUSE_GRACE = 5 -- seconds after pausing during which input is ignored (clicking Pause is itself input)

-- Input while the seated clock is paused resumes it, once the grace period is over.
local function inputWhilePaused(t)
  local p = ns.db and ns.ready and ns.db.body.paused
  if p and t - p > PAUSE_GRACE then ns.Do.resumeClock(true) end
end

local function noteInput()
  local t = now()
  ctx.lastInput = t
  inputWhilePaused(t)
  if ctx.away and primed then E.tick() end -- coming back: process the return right away
end

-- True when the cursor moved since the last poll.
local function cursorMoved()
  local cx, cy = Api.cursor()
  if cx and (cx ~= lastCx or cy ~= lastCy) then
    local moved = lastCx ~= nil
    lastCx, lastCy = cx, cy
    return moved
  end
  return false
end

-- Runs every second, but does work only while the seated clock is paused (cursor movement resumes it).
function E.pausePoll()
  if not (ns.ready and ns.db and ns.db.body.paused) then return end
  local t = now()
  if cursorMoved() then
    ctx.lastInput = t
    inputWhilePaused(t)
  end
end

local function rage(kind)
  if not (ns.db and ns.ready) then return end
  ns.Scheduler.rageEvent(ns.db, kind, now())
  if ns.UI and ns.UI.refreshAll then ns.UI.refreshAll() end
end

-- Refreshes the polled parts of ctx and fires transition moments.
function E.poll()
  local t = now()
  local prevTaxi, prevResting, prevInst, prevAway = ctx.taxi, ctx.resting, ctx.inst, ctx.away

  ctx.combat = Api.inCombat()
  local inst = Api.instanceType()
  if inst then ctx.inst = inst end
  ctx.taxi = Api.onTaxi()
  ctx.resting = Api.resting()
  ctx.dead = Api.dead()

  -- cursor movement counts as input
  if cursorMoved() then
    ctx.lastInput = t
    inputWhilePaused(t)
  end
  ctx.lastInput = ctx.lastInput or t

  local afk = Api.afk()
  local idle = (not ctx.taxi) and (not ctx.loading) and (t - ctx.lastInput >= AWAY_IDLE)
  ctx.away = (afk == true) or idle
  if ctx.away then
    if not prevAway then ctx.awaySince = ctx.lastInput end
  else
    ctx.awaySince = nil
  end

  if primed then
    if ctx.taxi and not prevTaxi then ctx.pendingMoment = "taxi" end
    if ctx.resting and not prevResting then ctx.pendingMoment = ctx.pendingMoment or "rest" end
    if prevInst ~= "none" and ctx.inst == "none" then ctx.pendingMoment = "leave" end
  end
  return prevAway
end

function E.tick()
  if not (ns.ready and ns.db) then return end
  local prevAway = E.poll()
  ns.Do.tick()
  if prevAway and not ctx.away then moment("return") end
  local m = ctx.pendingMoment
  if m then
    ctx.pendingMoment = nil
    moment(m)
  end
end

-- Handlers -------------------------------------------------------------------------------------------------------
local H = {}

function H.PLAYER_ENTERING_WORLD(initial, reloading)
  local t = now()
  ctx.settleUntil = t + 5
  ctx.lastInput = t
  E.poll()
  if ns.cdb and (initial or reloading) then
    local id = Api.mapId()
    if id then ns.cdb.zones[id] = ns.cdb.zones[id] or t end
  end
  primed = true
  if (initial or reloading) and ns.ready and ns.db then ns.Do.login(reloading and true or false) end
  if initial or reloading then
    if C_Timer and C_Timer.After then
      C_Timer.After(10, function() ns.guard(moment, "login") end)
    end
  end
  if ns.UI and ns.UI.refreshAll then ns.UI.refreshAll() end
end

function H.PLAYER_REGEN_DISABLED()
  ctx.combat = true
  combatToken = combatToken + 1
end

function H.PLAYER_REGEN_ENABLED()
  ctx.combat = false
  if ctx.inst == "none" then
    ctx.settleUntil = now() + 15
    combatToken = combatToken + 1
    local token = combatToken
    if C_Timer and C_Timer.After then
      C_Timer.After(15.5, function()
        if token == combatToken and not ctx.combat then ns.guard(moment, "combat") end
      end)
    end
  end
end

function H.ENCOUNTER_START() ctx.encounter = true end

function H.ENCOUNTER_END(_, _, _, _, success)
  ctx.encounter = false
  if Api.safe(success) == 1 then rage("boss") end
end

function H.LOADING_SCREEN_ENABLED() ctx.loading = true end

function H.LOADING_SCREEN_DISABLED()
  ctx.loading = false
  ctx.settleUntil = now() + 5
  ctx.lastInput = now()
end

function H.CINEMATIC_START() ctx.cinematic = true end
function H.CINEMATIC_STOP() ctx.cinematic = false end
function H.PLAY_MOVIE() ctx.cinematic = true end
function H.STOP_MOVIE() ctx.cinematic = false end

function H.PLAYER_DEAD()
  ctx.dead = true
  rage("death")
end

function H.PLAYER_ALIVE() ctx.dead = Api.dead() end
function H.PLAYER_UNGHOST() ctx.dead = Api.dead() end

function H.QUEST_TURNED_IN() rage("quest") end
function H.PLAYER_LEVEL_UP() rage("level") end

function H.ZONE_CHANGED_NEW_AREA()
  E.poll()
  if ctx.taxi or not ns.cdb then return end
  local id = Api.mapId()
  if not id or ns.cdb.zones[id] then return end
  ns.cdb.zones[id] = now()
  rage("zone")
end

function H.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellId)
  if Api.safe(unit) ~= "player" then return end
  spellId = Api.safe(spellId)
  if type(spellId) == "number" and C.HEARTH_SPELLS[spellId] then rage("hearth") end
end

function H.UNIT_SPELLCAST_START(unit)
  if Api.safe(unit) == "player" then
    ctx.lastInput = now()
    inputWhilePaused(ctx.lastInput)
  end
end

local function pollNow()
  E.poll()
  local m = ctx.pendingMoment
  if m and ns.ready then
    ctx.pendingMoment = nil
    moment(m)
  end
end

function H.PLAYER_UPDATE_RESTING() pollNow() end
function H.PLAYER_FLAGS_CHANGED() pollNow() end
function H.PLAYER_CONTROL_LOST() pollNow() end
function H.PLAYER_CONTROL_GAINED() pollNow() end

function H.GLOBAL_MOUSE_DOWN() noteInput() end
function H.PLAYER_STARTED_MOVING() noteInput() end
function H.MODIFIER_STATE_CHANGED() noteInput() end
function H.PLAYER_TARGET_CHANGED() noteInput() end

function H.PLAYER_LOGOUT()
  if ns.db then ns.db.body.lastTick = now() end
end

-- Start ------------------------------------------------------------------------------------------------------------
function E.start()
  if E.started then return end
  E.started = true
  ctx.lastInput = now()
  E.frame = CreateFrame("Frame", "StrongLikeTaurenEvents")
  for ev in pairs(H) do
    pcall(E.frame.RegisterEvent, E.frame, ev) -- unknown events must not error
  end
  E.frame:SetScript("OnEvent", function(_, event, ...)
    local h = H[event]
    if h then ns.guard(h, ...) end
  end)
  E.poll()
  primed = true
  E.ticker = C_Timer.NewTicker(15, function() ns.guard(E.tick) end)
  E.pauseTicker = C_Timer.NewTicker(1, function() ns.guard(E.pausePoll) end)
end
