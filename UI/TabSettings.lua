local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local Kit = UI.Kit
local COL = Kit.COL
local C, U = ns.C, ns.U

local Settings = { title = L["Settings"] }
UI.Tabs.settings = Settings

local function get(path) return U.getPath(ns.db.settings, path) end

local function fmtMin(v) return ("%d min"):format(v) end
local function fmtPct(v) return ("%d%%"):format(v) end
local function fmtInt(v) return ("%d"):format(v) end

-- Builders shared with FirstRun (exposed on Kit). `list` collects controls so they can be refreshed together.
function Kit.settingCheck(parent, list, label, path, w)
  local c
  c = Kit.check(parent, label, function() return get(path) end, function(v)
    ns.Do.setSetting(path, v)
    for _, x in ipairs(list) do x:Refresh() end
  end, w or 500)
  list[#list + 1] = c
  return c
end

function Kit.settingStep(parent, list, label, path, fmt, w)
  local opt = C.OPTION_BY_PATH[path]
  local c = Kit.stepper(parent, label, function() return get(path) end, function(v)
    ns.Do.setSetting(path, v)
    for _, x in ipairs(list) do x:Refresh() end
  end, opt[4], opt[5], opt[6], fmt, w or 420)
  list[#list + 1] = c
  return c
end

function Kit.settingSeg(parent, list, options, path, w)
  local c = Kit.segmented(parent, options, function() return get(path) end, function(v)
    ns.Do.setSetting(path, v)
    for _, x in ipairs(list) do x:Refresh() end
  end, w or 540)
  list[#list + 1] = c
  return c
end

function Kit.tierOptions()
  local o = {}
  for _, t in ipairs(C.TIERS) do o[#o + 1] = { t.pct, t.name } end
  return o
end

function Settings.build(parent)
  local root = CreateFrame("Frame", nil, parent)
  local scroll, content = Kit.scroll(root, 616, 418)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  local flow = Kit.flow(content, 588)
  local list = {}
  root.list = list
  local function refreshAll() for _, x in ipairs(list) do x:Refresh() end end

  local function check(label, path) flow:add(Kit.settingCheck(content, list, label, path), 24) end
  local function step(label, path, fmt) flow:add(Kit.settingStep(content, list, label, path, fmt), 24) end
  local function seg(options, path) flow:add(Kit.settingSeg(content, list, options, path), 26) end

  -- Intensity
  flow:header(L["Intensity"])
  flow:note(L["Scales every Feat of Strength. Walkabouts are timed by your break length instead."])
  seg(Kit.tierOptions(), "tier")
  step(L["Custom tier"], "tier", fmtPct)
  local tierNote = flow:note("")
  list[#list + 1] = { Refresh = function() tierNote:SetText(L["Current tier: "] .. C.tierName(get("tier"))) end }
  flow:note(L["Per-muscle-group intensity. Tick \"Use tier\" to follow the setting above."])
  for _, g in ipairs(C.GROUPS) do
    if C.CAPPED[g] then
      local st
      st = Kit.stepper(content, C.GROUP_NAME[g], function()
        return (ns.db.settings.groupPct and ns.db.settings.groupPct[g]) or get("tier")
      end, function(v) ns.Do.setGroupPct(g, v) end, 10, 300, 5, fmtPct, 400)
      flow:add(st, 24)
      local cb = Kit.check(content, L["Use tier"], function()
        return not (ns.db.settings.groupPct and ns.db.settings.groupPct[g])
      end, function(v)
        if v then ns.Do.setGroupPct(g, nil) else ns.Do.setGroupPct(g, get("tier")) end
        refreshAll()
      end, 120)
      cb:SetPoint("LEFT", st, "RIGHT", 10, 0)
      list[#list + 1] = {
        Refresh = function()
          st:Refresh()
          cb:Refresh()
          st:SetEnabled((ns.db.settings.groupPct and ns.db.settings.groupPct[g] ~= nil) and true or false)
        end,
      }
    end
  end

  -- Breaks
  flow:header(L["Breaks (Walkabouts)"])
  step(L["Break every (sitting minutes)"], "walk.every", fmtMin)
  flow:note(L["Break length: how long each Walkabout lasts. Research suggests 2 to 5 minutes."])
  seg({ { 1, L["Minimum 1"] }, { 2, L["Recommended 2"] }, { 5, L["Max benefit 5"] } }, "walk.dose")
  step(L["Break length"], "walk.dose", fmtMin)
  step(L["Longest break (after long sessions)"], "walk.max", fmtMin)

  -- Feats
  flow:header(L["Feats of Strength"])
  step(L["Minutes of play to fill Rage"], "rage.full", fmtMin)
  step(L["Minimum gap between Feats"], "rage.cd", fmtMin)
  step(L["Exercises per Feat"], "feat.slots", fmtInt)
  do
    local bankChk = Kit.settingCheck(content, list, L["Bank extra Rage (Double Feats)"], "rage.bank")
    flow:add(bankChk, 24)
    pcall(UI.Theme.Tooltip, bankChk, { L["Bank extra Rage (Double Feats)"],
      L["Rage keeps building past a full bar, up to 200. At 200 your next Feat is a Double Feat with twice the exercises."] })
  end
  step(L["Feat expires after (hours)"], "feat.expireH", fmtInt)
  seg({ { "walk", L["With the next Walkabout"] }, { "asap", L["Right away"] } }, "feat.delivery")

  -- Rage sources
  flow:header(L["Rage sources"])
  flow:note(L["How much Rage each event adds. 0 turns a source off."])
  step(L["Starting Rage"], "rage.start", fmtInt)
  for _, k in ipairs(C.RAGE_KINDS) do step(C.RAGE_NAME[k], "rage.w." .. k, fmtInt) end

  -- Recovery
  flow:header(L["Recovery"])
  flow:note(L["How quickly a muscle group recovers (half-life, in minutes)."])
  seg({ { 40, L["Troll Regeneration 40"] }, { 60, L["Standard 60"] }, { 90, L["Ancient 90"] } }, "halfLife")

  -- Caps
  flow:header(L["Caps"])
  step(L["Max sets per muscle group per hour"], "cap.hour", function(v) return ("%.1f"):format(v) end)
  step(L["Max sets per muscle group per day"], "cap.day", fmtInt)

  -- Filters & equipment
  flow:header(L["Filters & equipment"])
  check(L["Quiet: no jumping exercises"], "filters.quiet")
  check(L["No floor exercises"], "filters.noFloor")
  check(L["Easy on the wrists"], "filters.wrists")
  check(L["Seated breaks count (accessibility option)"], "filters.seatedOk")
  flow:note(L["For anyone who can't stand or walk: seated stretches and moves will count as a Walkabout."], 28)
  flow:note(L["Equipment I have:"], 0, "GameFontNormal", COL.text)
  for _, k in ipairs(C.EQUIP) do check(C.EQUIP_NAME[k], "equip." .. k) end

  -- Dungeons
  flow:header(L["Dungeons"])
  seg({ { "hold", L["Hold until I leave"] }, { "pulls", L["Nudge between pulls"] } }, "dungeon")

  -- Notifications
  flow:header(L["Notifications"])
  step(L["Minimum gap between nudges"], "nudge.gap", fmtMin)
  check(L["Play sounds"], "nudge.sound")
  seg({ { "alert", L["Alert"] }, { "horn", L["Horn"] }, { "chime", L["Chime"] }, { "menu", L["Menu"] } }, "nudge.soundKind")
  flow:add(Kit.button(content, L["Test"], 100, 24, function()
    ns.nudgeSound(true)
    if UI.Toast and UI.Toast.Sample then UI.Toast:Sample() end
  end), 26)
  check(L["Also show nudges in the centre of the screen"], "nudge.center")

  -- Away
  flow:header(L["Away"])
  step(L["Ask about away time after"], "away.ask", fmtMin)
  step(L["Count away time as a break after"], "away.credit", fmtMin)

  -- Totem
  flow:header(L["Totem"])
  check(L["Lock position"], "totem.locked")
  check(L["Hide when nothing is due"], "totem.hideIdle")
  step(L["Scale"], "totem.scale", function(v) return ("%.1fx"):format(v) end)
  local rb = Kit.button(content, L["Reset position"], 140, 24, function()
    if UI.Totem and UI.Totem.ResetPosition then UI.Totem:ResetPosition() end
  end)
  flow:add(rb, 24)

  -- Minimap
  flow:header(L["Minimap"])
  check(L["Hide the minimap button"], "minimap.hide")

  -- General
  flow:header(L["General"])
  check(L["Enabled"], "enabled")
  step(L["Day starts at (hour)"], "dayStart", function(v) return ("%d:00"):format(v) end)
  flow:finish()
  return root
end

function Settings.refresh(root)
  for _, x in ipairs(root.list) do x:Refresh() end
end
