local ADDON, ns = ...

-- The only file that queries game state. Every call is pcall-wrapped and secret-checked; nil = unknown.
local Api = {}
ns.Api = Api

local function isSecret(v)
  if issecretvalue then
    local ok, s = pcall(issecretvalue, v)
    if ok and s then return true end
  end
  return false
end

-- Returns v, or nil if it is a secret value.
function Api.safe(v)
  if isSecret(v) then return nil end
  return v
end

-- pcall a game function; returns its first result (nil on error or secret).
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok then return nil end
  return Api.safe(v)
end

local lastNow = 0
function Api.now()
  local t = call(GetServerTime) or (time and time()) or 0
  if type(t) ~= "number" then t = lastNow end
  if t < lastNow then t = lastNow end
  lastNow = t
  return t
end

function Api.isForever()
  return true
end

function Api.inCombat()
  local v = call(InCombatLockdown)
  if v == nil then v = call(UnitAffectingCombat, "player") end
  return v and true or false
end

function Api.instanceType()
  if not IsInInstance then return "none" end
  local ok, inInst, t = pcall(IsInInstance)
  if not ok or isSecret(inInst) or isSecret(t) then return nil end
  if not inInst then return "none" end
  if t == "party" or t == "raid" or t == "pvp" or t == "arena" or t == "scenario" then return t end
  return "none"
end

function Api.onTaxi()
  return call(UnitOnTaxi, "player") and true or false
end

function Api.resting()
  return call(IsResting) and true or false
end

-- nil when unknown (secret during chat lockdown).
function Api.afk()
  local v = call(UnitIsAFK, "player")
  if v == nil then return nil end
  return v and true or false
end

function Api.dead()
  local a = call(UnitIsDeadOrGhost, "player")
  return a and true or false
end

-- Cutscene or movie playing? true/false when the client can tell, nil when it cannot.
function Api.inCinematic()
  local known = false
  local yes = false
  local function check(fn)
    if type(fn) ~= "function" then return end
    local ok, v = pcall(fn)
    if not ok or isSecret(v) then return end
    known = true
    if v then yes = true end
  end
  check(InCinematic)
  check(IsInCinematicScene)
  for _, name in ipairs({ "MovieFrame", "CinematicFrame" }) do
    local f = rawget(_G, name)
    if type(f) == "table" and type(f.IsShown) == "function" then
      local ok, v = pcall(f.IsShown, f)
      if ok and not isSecret(v) then
        known = true
        if v then yes = true end
      end
    end
  end
  if not known then return nil end
  return yes
end

-- Boss fight in progress? nil when unknown.
function Api.encounterInProgress()
  if type(IsEncounterInProgress) ~= "function" then return nil end
  local v = call(IsEncounterInProgress)
  if v == nil then return nil end
  return v and true or false
end

function Api.mapId()
  if not C_Map or not C_Map.GetBestMapForUnit then return nil end
  local v = call(C_Map.GetBestMapForUnit, "player")
  if type(v) ~= "number" then return nil end
  return v
end

function Api.zoneName()
  return call(GetZoneText) or call(GetRealZoneText)
end

function Api.cursor()
  if not GetCursorPosition then return nil end
  local ok, x, y = pcall(GetCursorPosition)
  if not ok or isSecret(x) or isSecret(y) then return nil end
  return x, y
end

function Api.player()
  local name = call(UnitName, "player")
  local _, class = nil, nil
  if UnitClass then
    local ok, a, b = pcall(UnitClass, "player")
    if ok and not isSecret(b) then class = b end
  end
  local guid = call(UnitGUID, "player")
  if type(name) ~= "string" then name = nil end
  if type(guid) ~= "string" then guid = nil end
  return { name = name, class = class, guid = guid }
end

function Api.playSound(name, channel)
  if not (PlaySound and SOUNDKIT and name) then return false end
  local id = SOUNDKIT[name]
  if not id then return false end
  return pcall(PlaySound, id, channel) and true or false
end

-- Diagnostics for /tauren debug: { {name, value, secret} }.
function Api.probe()
  local out = {}
  local function add(name, fn, ...)
    local args = { ... }
    local ok, v = pcall(function() return fn(unpack(args)) end)
    local secret = ok and isSecret(v)
    out[#out + 1] = { name = name, value = (not ok) and ("error") or (secret and "<secret>" or tostring(v)),
                      secret = secret and true or false }
  end
  if GetServerTime then add("GetServerTime", GetServerTime) end
  if InCombatLockdown then add("InCombatLockdown", InCombatLockdown) end
  if IsInInstance then add("IsInInstance", IsInInstance) end
  if UnitOnTaxi then add("UnitOnTaxi", UnitOnTaxi, "player") end
  if IsResting then add("IsResting", IsResting) end
  if UnitIsAFK then add("UnitIsAFK", UnitIsAFK, "player") end
  if UnitIsDeadOrGhost then add("UnitIsDeadOrGhost", UnitIsDeadOrGhost, "player") end
  if C_Map and C_Map.GetBestMapForUnit then add("GetBestMapForUnit", C_Map.GetBestMapForUnit, "player") end
  if GetZoneText then add("GetZoneText", GetZoneText) end
  if UnitName then add("UnitName", UnitName, "player") end
  if GetCursorPosition then add("GetCursorPosition", GetCursorPosition) end
  out[#out + 1] = { name = "issecretvalue", value = issecretvalue and "present" or "absent", secret = false }
  return out
end
