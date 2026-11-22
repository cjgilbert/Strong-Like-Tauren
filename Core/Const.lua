local ADDON, ns = ...
local L = ns.L

-- Constants and the single settings schema (defaults + validation + what the Settings tab edits).
local C = {}
ns.C = C

C.SCHEMA = 1
C.VERSION = "0.1.2"
C.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
C.ICON = C.MEDIA .. "SLT_Icon"
C.LOGO = C.MEDIA .. "SLT_Logo"

-- Muscle groups. Only "capped" groups count toward the hourly/daily load caps.
C.GROUPS = { "legs", "push", "pull", "core", "cardio", "mobility", "walk" }
C.CAPPED = { legs = true, push = true, pull = true, core = true, cardio = true }
C.GROUP_NAME = {
  legs = L["Legs"], push = L["Push"], pull = L["Pull"], core = L["Core"],
  cardio = L["Cardio"], mobility = L["Mobility"], walk = L["Walking"],
}

-- Intensity tiers (multiplier for Feats of Strength).
C.TIERS = {
  { key = "critter", pct = 25,  name = L["Critter"], quip = L["Squeak."] },
  { key = "peon",    pct = 50,  name = L["Peon"],    quip = L["Work, work."] },
  { key = "grunt",   pct = 100, name = L["Grunt"],   quip = L["Zug zug."] },
  { key = "kodo",    pct = 150, name = L["Kodo"],    quip = L["The plains tremble."] },
  { key = "tauren",  pct = 200, name = L["Tauren"],  quip = L["Strong like Tauren!"] },
}

function C.tierName(pct)
  for _, t in ipairs(C.TIERS) do
    if t.pct == pct then return t.name end
  end
  return ("%s (%d%%)"):format(L["Custom"], pct)
end

-- Reputation with the Bloodhoof Athletic Club.
C.FACTION = L["Bloodhoof Athletic Club"]
C.STANDINGS = {
  { name = L["Hated"],      min = 0 },
  { name = L["Hostile"],    min = 500 },
  { name = L["Unfriendly"], min = 1500 },
  { name = L["Neutral"],    min = 3000 },
  { name = L["Friendly"],   min = 6000 },
  { name = L["Honored"],    min = 12000 },
  { name = L["Revered"],    min = 24000 },
  { name = L["Exalted"],    min = 45000 },
}
C.REP = { walk = 25, featSlot = 25, daily = 150, manual = 10, dayCap = 600 }
C.DAILY_GOAL = 3          -- completions for "[Daily] Earthmother's Calling"
C.STREAK_PLAY_MIN = 1200  -- a day only "counts" for the streak after 20 min of play

-- Equipment someone may or may not have.
C.EQUIP = { "chair", "wall", "stairs", "bar", "band", "dumbbells" }
C.EQUIP_NAME = {
  chair = L["Sturdy chair"], wall = L["Clear wall"], stairs = L["Stairs"],
  bar = L["Pull-up bar"], band = L["Resistance band"], dumbbells = L["Dumbbells"],
}

-- Rage sources. Weights live in settings.rage.w.
C.RAGE_KINDS = { "quest", "level", "death", "boss", "zone", "hearth" }
C.RAGE_NAME = {
  quest = L["Quest turned in"], level = L["Level up"], death = L["Death"],
  boss = L["Boss kill"], zone = L["New zone"], hearth = L["Hearthstone"],
}
C.RAGE_DEDUPE = { death = 30 }  -- seconds: repeats inside this window are ignored

-- Spells that count as "hearthing" (Hearthstone, Astral Recall).
C.HEARTH_SPELLS = { [8690] = true, [556] = true }

-- Sound candidates per role; the first SOUNDKIT name that exists is used.
C.SOUNDS = {
  toast   = { "IG_QUEST_LIST_OPEN", "IG_MAINMENU_OPEN" },
  done    = { "IG_QUEST_LIST_COMPLETE", "IG_CHARACTER_INFO_TAB" },
  tick    = { "IG_MAINMENU_OPTION_CHECKBOX_ON", "IG_CHARACTER_INFO_TAB" },
  finish  = { "READY_CHECK" },
  achieve = { "IG_QUEST_LIST_COMPLETE", "READY_CHECK" },
  click   = { "IG_MAINMENU_OPTION_CHECKBOX_ON" },
}

-- Settings schema: { path, kind, default, min, max, step } / { path, "enum", default, values }.
C.OPTIONS = {
  { "enabled",          "bool", true },
  { "tier",             "num",  100, 10, 300, 5 },
  { "walk.every",       "num",  30, 20, 60, 5 },
  { "walk.dose",        "num",  2, 1, 5, 1 },
  { "walk.max",         "num",  5, 1, 10, 1 },
  { "rage.full",        "num",  90, 60, 180, 15 },
  { "rage.cd",          "num",  45, 30, 120, 5 },
  { "rage.start",       "num",  40, 0, 100, 5 },
  { "rage.w.quest",     "num",  10, 0, 50, 1 },
  { "rage.w.level",     "num",  50, 0, 100, 5 },
  { "rage.w.death",     "num",  35, 0, 100, 5 },
  { "rage.w.boss",      "num",  30, 0, 100, 5 },
  { "rage.w.zone",      "num",  15, 0, 50, 1 },
  { "rage.w.hearth",    "num",  10, 0, 50, 1 },
  { "halfLife",         "num",  60, 40, 90, 10 },
  { "cap.hour",         "num",  1.5, 0.5, 3, 0.5 },
  { "cap.day",          "num",  6, 2, 12, 1 },
  { "feat.slots",       "num",  2, 1, 3, 1 },
  { "feat.expireH",     "num",  3, 1, 8, 1 },
  { "feat.delivery",    "enum", "walk", { "walk", "asap" } },
  { "nudge.gap",        "num",  10, 5, 30, 5 },
  { "nudge.sound",      "bool", true },
  { "nudge.center",     "bool", false },
  { "dungeon",          "enum", "hold", { "hold", "pulls" } },
  { "away.ask",         "num",  3, 1, 10, 1 },
  { "away.credit",      "num",  10, 5, 30, 1 },
  { "filters.quiet",    "bool", false },
  { "filters.noFloor",  "bool", false },
  { "filters.wrists",   "bool", false },
  { "filters.seatedOk", "bool", false },
  { "equip.chair",      "bool", true },
  { "equip.wall",       "bool", true },
  { "equip.stairs",     "bool", false },
  { "equip.bar",        "bool", false },
  { "equip.band",       "bool", false },
  { "equip.dumbbells",  "bool", false },
  { "dayStart",         "num",  4, 0, 8, 1 },
  { "totem.locked",     "bool", false },
  { "totem.scale",      "num",  1, 0.6, 1.6, 0.1 },
  { "totem.collapsed",  "bool", false },
  { "totem.hideIdle",   "bool", false },
  { "minimap.hide",     "bool", false },
  { "minimap.angle",    "num",  200, 0, 360, 1 },
  { "firstRun",         "bool", true },
}

local function snap(v, lo, hi, step)
  v = math.max(lo, math.min(hi, v))
  if step and step > 0 then
    v = lo + math.floor((v - lo) / step + 0.5) * step
    v = math.floor(v * 1000 + 0.5) / 1000  -- tidy float noise (e.g. 0.30000000004)
  end
  return math.max(lo, math.min(hi, v))
end

-- Returns a valid value for an option, falling back to its default.
function C.validate(opt, v)
  local kind, def = opt[2], opt[3]
  if kind == "bool" then
    if type(v) == "boolean" then return v end
    return def
  elseif kind == "num" then
    v = tonumber(v)
    if not v or v ~= v then return def end
    return snap(v, opt[4], opt[5], opt[6])
  elseif kind == "enum" then
    for _, allowed in ipairs(opt[4]) do if v == allowed then return v end end
    return def
  end
  return def
end

C.OPTION_BY_PATH = {}
for _, opt in ipairs(C.OPTIONS) do C.OPTION_BY_PATH[opt[1]] = opt end

-- Default settings table built from the schema.
function C.defaultSettings()
  local s = { groupPct = {}, totem = {}, minimap = {} }
  for _, opt in ipairs(C.OPTIONS) do ns.U.setPath(s, opt[1], opt[3]) end
  return s
end
