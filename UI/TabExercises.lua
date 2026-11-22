local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local Kit = UI.Kit
local COL = Kit.COL

local Ex = { title = L["Exercises"] }
UI.Tabs.exercises = Ex

local ROW_H = 38
local rootFrame

local function prefText(p)
  p = p or 2
  return "[" .. ("*"):rep(p) .. ("-"):rep(3 - p) .. "]"
end

local function afterChange()
  if ns.Do and ns.Do.libraryChanged then ns.Do.libraryChanged() end
  if rootFrame then Ex.refresh(rootFrame) end
  if UI.Tabs.history and UI.Main then UI.Main:Refresh() end
end

local function baseOf(id)
  for _, b in ipairs(ns.D.EXERCISES) do if b.id == id then return b end end
end

----------------------------------------------------------------------------------------------------------------
-- Editor
----------------------------------------------------------------------------------------------------------------
local ED  -- editor frame (built lazily)
local E = { g = {}, flags = {} }  -- editing state

local function setMsg(text, good)
  if not ED then return end
  ED.msg:SetText(text or "")
  local c = good and COL.green or COL.red
  ED.msg:SetTextColor(c[1], c[2], c[3])
end

local function refreshEditor()
  ED.name:SetText(E.name or "")
  ED.pun:SetText(E.pun or "")
  ED.desc:SetText(E.desc or "")
  ED.std:SetText(tostring(E.std or ""))
  ED.lo:SetText(tostring(E.lo or ""))
  ED.hi:SetText(tostring(E.hi or ""))
  ED.rest:SetText(tostring(E.restMin or 0))
  ED.pct:SetText(E.pct and tostring(E.pct) or "")
  ED.pref:Refresh()
  ED.on:Refresh()
  if E.custom then
    ED.kind:Refresh()
    ED.int:Refresh()
    ED.walk:Refresh()
    for _, f in ipairs(ED.flags) do f:Refresh() end
    for _, r in ipairs(ED.groups) do
      r.check:Refresh()
      r.step:Refresh()
      r.step:SetEnabled(E.g[r.g] ~= nil)
    end
    ED.needs:SetText(L["Needs: "] .. (E.needs and ns.C.EQUIP_NAME[E.needs] or L["nothing"]))
  end
end

local function buildEditor()
  local f = Kit.panel(UIParent, "StrongLikeTaurenEditor", 480, 580, COL.panel)
  f:SetPoint("CENTER", 40, 0)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f.title = Kit.text(f, "", "GameFontNormalLarge", COL.gold, 420)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
  local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
  if ok and close then
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)
  end
  tinsert(UISpecialFrames, "StrongLikeTaurenEditor")

  local scroll, content = Kit.scroll(f, 460, 450)
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -44)
  local Y = 0
  local function addRow(label, ctrl, h)
    local fs = Kit.text(content, label, "GameFontHighlight", COL.text, 130)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -Y - 4)
    ctrl:SetPoint("TOPLEFT", content, "TOPLEFT", 135, -Y)
    Y = Y + (h or 28)
    return fs
  end

  f.name = Kit.edit(content, 280, 22); f.name:SetMaxLetters(40)
  addRow(L["Name"], f.name)
  f.pun = Kit.edit(content, 280, 22); f.pun:SetMaxLetters(40)
  addRow(L["Pun / nickname"], f.pun)
  f.desc = Kit.edit(content, 280, 22); f.desc:SetMaxLetters(160)
  addRow(L["Description"], f.desc)
  f.std = Kit.edit(content, 70, 22, true)
  f.stdLbl = addRow(L["Standard amount"], f.std)
  f.lo = Kit.edit(content, 70, 22, true)
  addRow(L["Minimum"], f.lo)
  f.hi = Kit.edit(content, 70, 22, true)
  addRow(L["Maximum"], f.hi)
  f.rest = Kit.edit(content, 70, 22, true)
  addRow(L["Min rest (minutes)"], f.rest)
  f.pref = Kit.segmented(content, { { 1, L["1 rare"] }, { 2, L["2 normal"] }, { 3, L["3 often"] } },
    function() return E.pref end, function(v) E.pref = v end, 270)
  addRow(L["Preference"], f.pref, 30)
  f.pct = Kit.edit(content, 70, 22, true)
  addRow(L["Tier % (optional)"], f.pct)
  local pctNote = Kit.text(content, L["Leave blank to follow your tier."], "GameFontHighlightSmall", COL.dim, 280)
  pctNote:SetPoint("TOPLEFT", content, "TOPLEFT", 135, -Y + 4)
  Y = Y + 14
  f.on = Kit.check(content, L["Enabled"], function() return E.on ~= false end, function(v) E.on = v end, 200)
  f.on:SetPoint("TOPLEFT", content, "TOPLEFT", 135, -Y)
  Y = Y + 28

  f.builtNote = Kit.text(content, L["Muscle groups, flags and equipment of built-in exercises can't be changed. Make a new exercise for that."],
    "GameFontHighlightSmall", COL.dim, 420)
  f.builtNote:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -Y)

  -- Custom-only section
  local box = CreateFrame("Frame", nil, content)
  box:SetSize(430, 470)
  box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -Y)
  f.custBox = box
  f.baseY = Y
  local y = 0
  f.kind = Kit.segmented(box, { { "r", L["Reps"] }, { "s", L["Seconds"] } },
    function() return E.kind end, function(v) E.kind = v end, 200)
  f.kind:SetPoint("TOPLEFT", box, "TOPLEFT", 135, -y)
  Kit.text(box, L["Counted in"], "GameFontHighlight", COL.text, 130):SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y - 4)
  y = y + 32
  f.int = Kit.segmented(box, { { "l", L["Light"] }, { "m", L["Medium"] }, { "v", L["Vigorous"] } },
    function() return E.int end, function(v) E.int = v end, 270)
  f.int:SetPoint("TOPLEFT", box, "TOPLEFT", 135, -y)
  Kit.text(box, L["Intensity"], "GameFontHighlight", COL.text, 130):SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y - 4)
  y = y + 32
  Kit.text(box, L["Muscle groups (weight 0.1 - 1.0)"], "GameFontNormal", COL.gold, 400):SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
  y = y + 20
  f.groups = {}
  for _, g in ipairs(ns.C.GROUPS) do
    local r = { g = g }
    r.check = Kit.check(box, ns.C.GROUP_NAME[g], function() return E.g[g] ~= nil end, function(v)
      if v then E.g[g] = E.g[g] or 1 else E.g[g] = nil end
      refreshEditor()
    end, 130)
    r.check:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
    r.step = Kit.stepper(box, "", function() return E.g[g] or 0.5 end, function(v) E.g[g] = v end,
      0.1, 1, 0.1, function(v) return ("%.1f"):format(v) end, 140)
    r.step:SetPoint("TOPLEFT", box, "TOPLEFT", 140, -y)
    f.groups[#f.groups + 1] = r
    y = y + 26
  end
  y = y + 6
  Kit.text(box, L["Flags"], "GameFontNormal", COL.gold, 400):SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
  y = y + 20
  f.flags = {}
  local FL = { { "jump", L["Jumping (noisy)"] }, { "floor", L["Needs the floor"] }, { "wrist", L["Loads the wrists"] }, { "seated", L["Can be done seated"] } }
  for i, fl in ipairs(FL) do
    local c = Kit.check(box, fl[2], function() return E.flags[fl[1]] end, function(v) E.flags[fl[1]] = v or nil end, 200)
    c:SetPoint("TOPLEFT", box, "TOPLEFT", ((i - 1) % 2) * 210, -y)
    f.flags[i] = c
    if i % 2 == 0 then y = y + 26 end
  end
  y = y + 6
  f.needs = Kit.button(box, "", 220, 24, function()
    local list = { false }
    for _, k in ipairs(ns.C.EQUIP) do list[#list + 1] = k end
    local idx = 1
    for i, k in ipairs(list) do if k == (E.needs or false) then idx = i end end
    idx = idx % #list + 1
    E.needs = list[idx] or nil
    refreshEditor()
  end)
  f.needs:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
  y = y + 30
  f.walk = Kit.check(box, L["Walkabout move (timed by your break length)"], function() return E.walk end,
    function(v) E.walk = v or nil end, 400)
  f.walk:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
  y = y + 30
  f.custH = y

  f.msg = Kit.text(f, "", "GameFontHighlightSmall", COL.red, 440)
  f.msg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 50)
  f.content = content

  f.save = Kit.button(f, L["Save"], 90, 26)
  f.save:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
  f.cancel = Kit.button(f, L["Cancel"], 90, 26, function() f:Hide() end)
  f.cancel:SetPoint("LEFT", f.save, "RIGHT", 8, 0)
  f.reset = Kit.button(f, L["Reset to default"], 130, 26)
  f.reset:SetPoint("LEFT", f.cancel, "RIGHT", 8, 0)
  f.delete = Kit.button(f, L["Delete"], 90, 26)
  f.delete:SetPoint("LEFT", f.cancel, "RIGHT", 8, 0)
  f:Hide()
  return f
end

local function numOf(box)
  local t = box:GetText()
  if t == nil or t == "" then return nil end
  return tonumber(t)
end

local function collect()
  E.name = ED.name:GetText()
  E.pun = ED.pun:GetText()
  E.desc = ED.desc:GetText()
  E.std, E.lo, E.hi = numOf(ED.std), numOf(ED.lo), numOf(ED.hi)
  E.restMin = numOf(ED.rest) or 0
  E.pct = numOf(ED.pct)
end

local function saveBuiltin()
  local base = baseOf(E.id)
  if not base then return false end
  local Lib = ns.Library
  local o = {}
  local name, pun = Lib.sanitize(E.name), Lib.sanitize(E.pun)
  if name and name ~= base.name then o.name = name end
  if pun and pun ~= base.pun then o.pun = pun end
  if E.std and E.std ~= base.std then o.std = E.std end
  if E.lo and E.lo ~= (base.lo or 1) then o.lo = E.lo end
  if E.hi and E.hi ~= (base.hi or base.std * 4) then o.hi = E.hi end
  local rest = math.floor(E.restMin * 60 + 0.5)
  if rest ~= (base.rest or 0) then o.rest = rest end
  if E.pref ~= (base.pref or 2) then o.pref = E.pref end
  if E.pct then o.pct = E.pct end
  if E.on == false then o.on = false end
  ns.db.lib.over[E.id] = next(o) and o or nil
  return true
end

local function saveCustom()
  local Lib = ns.Library
  local name = Lib.sanitize(E.name)
  if not name then return false, L["Give it a name."] end
  local id = E.id or Lib.newCustomId(ns.db.lib, name)
  local old = ns.db.lib.custom[id] or {}
  local def = {
    id = id, name = name, pun = E.pun, desc = E.desc, kind = E.kind, std = E.std, lo = E.lo, hi = E.hi,
    g = E.g, int = E.int, flags = E.flags, needs = E.needs, rest = math.floor(E.restMin * 60 + 0.5),
    walk = E.walk, pref = E.pref, tags = old.tags, icon = old.icon,
  }
  local v, err = Lib.validate(def)
  if not v then
    local why = { ["bad amount"] = L["Standard amount must be more than 0."], ["no muscle group"] = L["Pick at least one muscle group."] }
    return false, why[err] or tostring(err)
  end
  v.pct = E.pct and math.max(10, math.min(300, math.floor(E.pct))) or nil
  v.on = (E.on ~= false)
  ns.db.lib.custom[id] = v
  return true
end

local function openEditor(id)
  if not ED then ED = buildEditor() end
  local def = id and ns.env.byId[id]
  E = { id = id, custom = (not def) or (def.custom and true or false), g = {}, flags = {} }
  if def then
    E.name, E.pun, E.desc = def.name, def.pun, def.desc
    E.kind, E.std, E.lo, E.hi = def.kind, def.std, def.lo, def.hi
    E.restMin = math.floor((def.rest or 0) / 60 + 0.5)
    E.pref, E.pct, E.on = def.pref or 2, def.pct, def.on
    E.int, E.needs, E.walk = def.int or "m", def.needs, def.walk
    for k, w in pairs(def.g or {}) do E.g[k] = w end
    for k, v in pairs(def.flags or {}) do E.flags[k] = v end
    ED.title:SetText((E.custom and L["Edit custom exercise"] or L["Edit exercise"]) .. ": " .. (def.name or id))
  else
    E.name, E.pun, E.desc = "", "", ""
    E.kind, E.std, E.lo, E.hi = "r", 10, 1, 40
    E.restMin, E.pref, E.on, E.int = 30, 2, true, "m"
    E.g = { legs = 1 }
    ED.title:SetText(L["New exercise"])
  end
  ED.stdLbl:SetText(E.custom and L["Standard amount"] or L["Standard amount"])
  ED.custBox:SetShown(E.custom)
  ED.builtNote:SetShown(not E.custom)
  ED.content:SetHeight(ED.baseY + (E.custom and ED.custH or 30) + 10)
  ED.save:SetScript("OnClick", function()
    collect()
    local ok, err = true, nil
    if E.custom then ok, err = saveCustom() else ok = saveBuiltin() end
    if not ok then setMsg(err or L["Couldn't save."]); return end
    ED:Hide()
    afterChange()
  end)
  ED.reset:SetShown(not E.custom)
  ED.delete:SetShown(E.custom and E.id ~= nil)
  ED.reset:SetScript("OnClick", function()
    ns.db.lib.over[E.id] = nil
    ED:Hide()
    afterChange()
  end)
  ED.delete:SetScript("OnClick", function()
    local id2 = E.id
    Kit.confirm(L["Delete this custom exercise? Past log entries stay."], function()
      ns.db.lib.custom[id2] = nil
      ED:Hide()
      afterChange()
    end)
  end)
  setMsg("")
  refreshEditor()
  ED:Show()
end

----------------------------------------------------------------------------------------------------------------
-- List
----------------------------------------------------------------------------------------------------------------
local function makeRow(content, i)
  local r = CreateFrame("Frame", nil, content)
  r:SetSize(588, ROW_H)
  r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
  local bg = r:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(28, 28)
  r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
  r.name = Kit.text(r, "", "GameFontNormal", COL.text, 260)
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 38, -4)
  r.name:SetWordWrap(false)
  r.info = Kit.text(r, "", "GameFontHighlightSmall", COL.dim, 300)
  r.info:SetPoint("TOPLEFT", r, "TOPLEFT", 38, -21)
  r.info:SetWordWrap(false)
  r.on = Kit.check(r, L["On"], function() return r.def and r.def.on ~= false end, function(v)
    local d = r.def
    if not d then return end
    if d.custom then
      local c = ns.db.lib.custom[d.id]
      if c then c.on = v end
    else
      local o = ns.db.lib.over[d.id] or {}
      o.on = (not v) and false or nil
      ns.db.lib.over[d.id] = next(o) and o or nil
    end
    afterChange()
  end, 60)
  r.on:SetPoint("LEFT", r, "LEFT", 340, 0)
  r.pref = Kit.text(r, "", "GameFontHighlightSmall", COL.gold, 60)
  r.pref:SetPoint("LEFT", r, "LEFT", 410, 0)
  Kit.tip(r, L["Preference: more stars means picked more often."])
  r.edit = Kit.button(r, L["Edit"], 50, 22, function() if r.def then openEditor(r.def.id) end end)
  r.edit:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  return r
end

function Ex.build(parent)
  local root = CreateFrame("Frame", nil, parent)
  rootFrame = root
  local F = { rows = {} }
  root.F = F
  local x = 4
  local function btn(text, w, fn)
    local b = Kit.button(root, text, w, 24, fn)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, -2)
    x = x + w + 6
    return b
  end
  btn(L["New exercise"], 120, function() openEditor(nil) end)
  btn(L["Reset all tweaks"], 120, function()
    Kit.confirm(L["Reset every built-in exercise to its defaults? Your custom exercises are kept."], function()
      ns.db.lib.over = {}
      afterChange()
    end)
  end)
  btn(L["Share..."], 90, function() if UI.Share then UI.Share:Export() end end)
  btn(L["Import..."], 90, function() if UI.Share then UI.Share:Import() end end)
  local scroll, content = Kit.scroll(root, 616, 384)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -32)
  F.content = content
  return root
end

function Ex.refresh(root)
  local F = root.F
  local defs = ns.env.defs
  for i, d in ipairs(defs) do
    local r = F.rows[i]
    if not r then
      r = makeRow(F.content, i)
      F.rows[i] = r
    end
    r.def = d
    r.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.name:SetText(ns.Library.displayName(d) .. (d.custom and ("  (" .. L["custom"] .. ")") or ""))
    local info = Kit.amountStr(d, d.std) .. " - " .. (ns.C.GROUP_NAME[d.primary] or d.primary)
    if d.walk then info = info .. " - " .. L["Walkabout move"] end
    if d.pct then info = info .. " - " .. (L["tier %d%%"]):format(d.pct) end
    r.info:SetText(info)
    r.pref:SetText(prefText(d.pref))
    r.on:Refresh()
    r:Show()
  end
  for i = #defs + 1, #F.rows do F.rows[i]:Hide() end
  F.content:SetHeight(#defs * ROW_H + 6)
end
