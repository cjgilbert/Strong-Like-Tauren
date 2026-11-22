local ADDON, ns = ...
local U, C = ns.U, ns.C

-- Effective exercise library = built-ins + per-exercise overrides + custom exercises.
local Library = {}
ns.Library = Library

local FLAG_KEYS = { "jump", "floor", "wrist", "seated" }
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Cuts a UTF-8 string to at most maxBytes without splitting a character.
local function utf8cut(s, maxBytes)
  if #s <= maxBytes then return s end
  local out, n = {}, 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if n + #ch > maxBytes then break end
    out[#out + 1] = ch
    n = n + #ch
  end
  return table.concat(out)
end

-- Strips WoW escape sequences ("|") and control characters, trims, caps length. Returns nil when empty.
function Library.sanitize(s, maxBytes)
  if type(s) ~= "string" then return nil end
  s = s:gsub("|", ""):gsub("[%c]", " ")
  s = U.trim(s)
  s = utf8cut(s, maxBytes or 40)
  if s == "" then return nil end
  return s
end
local sanitize = Library.sanitize

-- Muscle group with the highest weight (ties resolved in C.GROUPS order).
function Library.primary(def)
  local best, bestW = nil, -1
  for _, g in ipairs(C.GROUPS) do
    local w = def.g and def.g[g]
    if w and w > bestW then best, bestW = g, w end
  end
  return best or "mobility"
end

function Library.isStanding(def)
  return not (def and def.flags and def.flags.seated)
end

-- Validates and normalizes a definition (custom exercises and imports). Returns def, or nil + reason.
function Library.validate(def)
  if type(def) ~= "table" then return nil, "not a table" end
  local id = type(def.id) == "string" and def.id:match("^[%w_%-]+$") and def.id:sub(1, 32)
  if not id then return nil, "bad id" end
  local out = { id = id }
  out.name = sanitize(def.name) or id
  out.pun = sanitize(def.pun)
  out.desc = sanitize(def.desc, 160)
  out.kind = (def.kind == "s") and "s" or "r"
  local maxAmount = out.kind == "s" and 3600 or 1000
  local std = tonumber(def.std)
  if not std or std ~= std or std <= 0 then return nil, "bad amount" end
  out.std = U.clamp(U.round(std), 1, maxAmount)
  out.lo = U.clamp(U.round(tonumber(def.lo) or 1), 1, out.std)
  out.hi = U.clamp(U.round(tonumber(def.hi) or out.std * 4), out.std, maxAmount)
  out.g = {}
  local any = false
  if type(def.g) == "table" then
    for _, g in ipairs(C.GROUPS) do
      local w = tonumber(def.g[g])
      if w and w == w and w > 0 then out.g[g] = U.clamp(w, 0.05, 1); any = true end
    end
  end
  if not any then return nil, "no muscle group" end
  out.int = (def.int == "l" or def.int == "v") and def.int or "m"
  out.flags = {}
  if type(def.flags) == "table" then
    for _, f in ipairs(FLAG_KEYS) do if def.flags[f] then out.flags[f] = true end end
  end
  out.needs = (type(def.needs) == "string" and C.EQUIP_NAME[def.needs]) and def.needs or nil
  out.rest = U.clamp(U.round(tonumber(def.rest) or 1800), 0, 6 * 3600)
  out.walk = def.walk and true or nil
  out.tags = {}
  if type(def.tags) == "table" then
    for _, k in ipairs(C.RAGE_KINDS) do if def.tags[k] then out.tags[k] = true end end
  end
  out.icon = (type(def.icon) == "string" and def.icon:match("^Interface[\\/]")) and def.icon or DEFAULT_ICON
  out.pref = U.clamp(math.floor(tonumber(def.pref) or 2), 1, 3)
  if def.on == false then out.on = false end
  return out
end

-- Applies a stored override onto a (copied) built-in definition, field by field with type/range checks.
local function applyOverride(d, o)
  if type(o) ~= "table" then return end
  if o.on == false then d.on = false end
  local maxAmount = d.kind == "s" and 3600 or 1000
  if tonumber(o.std) then d.std = U.clamp(U.round(o.std), 1, maxAmount) end
  if tonumber(o.lo) then d.lo = U.clamp(U.round(o.lo), 1, d.std) end
  if tonumber(o.hi) then d.hi = U.clamp(U.round(o.hi), d.std, maxAmount) end
  if d.lo > d.std then d.lo = d.std end
  if d.hi < d.std then d.hi = d.std end
  if tonumber(o.pct) then d.pct = U.clamp(U.round(o.pct), 10, 300) end
  if tonumber(o.pref) then d.pref = U.clamp(math.floor(o.pref), 1, 3) end
  if tonumber(o.rest) then d.rest = U.clamp(U.round(o.rest), 0, 6 * 3600) end
  d.name = sanitize(o.name) or d.name
  d.pun = sanitize(o.pun) or d.pun
end

-- Returns the effective list (built-ins first, then custom by name) and an id -> def map.
function Library.build(builtins, lib)
  lib = type(lib) == "table" and lib or {}
  local over = type(lib.over) == "table" and lib.over or {}
  local defs, byId = {}, {}
  for _, b in ipairs(builtins) do
    local d = U.copy(b)
    d.flags = d.flags or {}
    d.tags = d.tags or {}
    d.pref = d.pref or 2
    d.lo = d.lo or 1
    d.hi = d.hi or d.std * 4
    d.on = true
    d.builtin = true
    applyOverride(d, over[d.id])
    d.primary = Library.primary(d)
    defs[#defs + 1] = d
    byId[d.id] = d
  end
  local customs = {}
  if type(lib.custom) == "table" then
    for _, c in pairs(lib.custom) do
      local d = Library.validate(c)
      if d and not byId[d.id] then
        d.on = (c.on ~= false)
        d.custom = true
        d.primary = Library.primary(d)
        if tonumber(c.pct) then d.pct = U.clamp(U.round(c.pct), 10, 300) end
        customs[#customs + 1] = d
      end
    end
  end
  table.sort(customs, function(a, b) return (a.name or a.id) < (b.name or b.id) end)
  for _, d in ipairs(customs) do
    defs[#defs + 1] = d
    byId[d.id] = d
  end
  return defs, byId
end

-- Tier percentage for this exercise: per-exercise override, then per-group, then the global tier.
function Library.effectivePct(def, settings)
  if def.pct then return def.pct end
  local gp = settings.groupPct and settings.groupPct[def.primary]
  if gp then return gp end
  return settings.tier or 100
end

-- Whether the player's filters and equipment allow this exercise.
function Library.allowed(def, s)
  if def.on == false then return false end
  local f, filters = def.flags or {}, s.filters or {}
  if filters.quiet and f.jump then return false end
  if filters.noFloor and f.floor then return false end
  if filters.wrists and f.wrist then return false end
  if def.needs and not (s.equip and s.equip[def.needs]) then return false end
  return true
end

function Library.displayName(def)
  if not def then return "?" end
  if def.pun and def.pun ~= def.name then return def.pun .. " (" .. def.name .. ")" end
  return def.name
end

-- Formats an amount with its unit: "15 Squats", "0:30".
function Library.amountText(def, amount)
  if not def then return tostring(amount) end
  if def.kind == "s" then return U.fmtClock(amount) end
  return tostring(amount)
end

-- New id for a custom exercise.
function Library.newCustomId(lib, name)
  lib.seq = (lib.seq or 0) + 1
  local slug = (type(name) == "string" and name or "custom"):lower():gsub("[^%w]+", ""):sub(1, 16)
  if slug == "" then slug = "custom" end
  return "c" .. slug .. lib.seq
end
