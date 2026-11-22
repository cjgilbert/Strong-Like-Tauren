local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local Kit = UI.Kit
local COL = Kit.COL

-- Export / import of exercise lists as share strings (see Logic\Codec.lua).
local Share = {}
UI.Share = Share

local OVERRIDE_FIELDS = { "std", "pct", "pref", "lo", "hi", "rest", "name", "pun" }

local function makeWindow(name, title, h)
  local f = Kit.panel(UIParent, name, 540, h, COL.panel)
  f:SetPoint("CENTER", 0, 20)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  local t = Kit.text(f, title, "GameFontNormalLarge", COL.gold, 480)
  t:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
  local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
  if ok and close then
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)
  end
  tinsert(UISpecialFrames, name)
  f:Hide()
  return f
end

----------------------------------------------------------------------------------------------------------------
-- Export
----------------------------------------------------------------------------------------------------------------
local exportWin

function Share:Export()
  if not exportWin then
    local f = makeWindow("StrongLikeTaurenExport", L["Share exercises"], 330)
    f.help = Kit.text(f, "", "GameFontHighlight", COL.text, 500)
    f.help:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -42)
    local holder, edit = Kit.multiEdit(f, 508, 190, true)
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -80)
    f.edit = edit
    local done = Kit.button(f, L["Close"], 90, 26, function() f:Hide() end)
    done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    f.count = Kit.text(f, "", "GameFontHighlightSmall", COL.dim, 380)
    f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 20)
    exportWin = f
  end
  local defs = {}
  for _, d in ipairs(ns.env.defs) do
    if d.custom then
      defs[#defs + 1] = d
    elseif ns.db.lib.over[d.id] and next(ns.db.lib.over[d.id]) then
      defs[#defs + 1] = d
    end
  end
  local text = ""
  if #defs > 0 then
    text = ns.Codec.encode(defs)
    exportWin.help:SetText(L["Press Ctrl+C to copy, then paste it to a friend. They use Import... on the Exercises tab."])
    exportWin.count:SetText((L["%d exercises included (custom ones and tweaked built-ins)."]):format(#defs))
  else
    exportWin.help:SetText(L["You have no custom exercises or tweaks to share yet."])
    exportWin.count:SetText("")
  end
  exportWin:Show()
  exportWin.edit:SetLocked(text)
  exportWin.edit:SetFocus()
  exportWin.edit:HighlightText()
end

----------------------------------------------------------------------------------------------------------------
-- Import
----------------------------------------------------------------------------------------------------------------
local importWin
local MAXR = 60

local function statusOf(d)
  if ns.env.byId[d.id] and ns.env.byId[d.id].builtin then return "tweak", L["Built-in tweak"] end
  if ns.db.lib.custom[d.id] then return "update", L["Update"] end
  return "add", L["Add"]
end

local function readText(win)
  local list, extra = ns.Codec.decode(win.edit:GetText())
  win.recs = {}
  for i = 1, MAXR do win.rows[i]:Hide() end
  if not list then
    win.msg:SetText(extra or L["That didn't work."])
    win.msg:SetTextColor(COL.red[1], COL.red[2], COL.red[3])
    win.apply:Hide()
    return
  end
  for i, d in ipairs(list) do
    if i > MAXR then break end
    local kind, label = statusOf(d)
    local r = win.rows[i]
    win.recs[i] = { def = d, kind = kind, on = true }
    r.label:SetText(ns.Library.displayName(d))
    r.status:SetText(label)
    r.cb:Refresh()
    r:Show()
  end
  win.content:SetHeight(#list * 24 + 6)
  local n = #list
  local msg = (L["Found %d exercises. Untick any you don't want."]):format(n)
  if type(extra) == "number" and extra > 0 then
    msg = msg .. " " .. (L["%d records could not be read and were skipped."]):format(extra)
  end
  win.msg:SetText(msg)
  win.msg:SetTextColor(COL.green[1], COL.green[2], COL.green[3])
  win.apply:Show()
end

local function applyImport(win)
  local added = 0
  for _, rec in ipairs(win.recs or {}) do
    if rec.on then
      local d = rec.def
      if rec.kind == "tweak" then
        local o = {}
        for _, k in ipairs(OVERRIDE_FIELDS) do if d[k] ~= nil then o[k] = d[k] end end
        if d.on == false then o.on = false end
        ns.db.lib.over[d.id] = next(o) and o or nil
      else
        local v = ns.U.copy(d)
        v.on = (d.on ~= false)
        ns.db.lib.custom[d.id] = v
      end
      added = added + 1
    end
  end
  if ns.Do and ns.Do.libraryChanged then ns.Do.libraryChanged() end
  if UI.Main then UI.Main:Refresh() end
  Kit.say((L["Imported %d exercises."]):format(added))
  win:Hide()
end

function Share:Import()
  if not importWin then
    local f = makeWindow("StrongLikeTaurenImport", L["Import exercises"], 470)
    local help = Kit.text(f, L["Paste a share string below, then press Read."], "GameFontHighlight", COL.text, 500)
    help:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -42)
    local holder, edit = Kit.multiEdit(f, 508, 90, false)
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -66)
    f.edit = edit
    local read = Kit.button(f, L["Read"], 90, 24, function() readText(f) end)
    read:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -164)
    f.msg = Kit.text(f, "", "GameFontHighlightSmall", COL.dim, 400)
    f.msg:SetPoint("LEFT", read, "RIGHT", 10, 0)
    local scroll, content = Kit.scroll(f, 508, 190)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -196)
    f.content = content
    f.rows = {}
    for i = 1, MAXR do
      local r = CreateFrame("Frame", nil, content)
      r:SetSize(480, 24)
      r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * 24)
      r.cb = Kit.check(r, "", function() return f.recs and f.recs[i] and f.recs[i].on end,
        function(v) if f.recs and f.recs[i] then f.recs[i].on = v end end, 30)
      r.cb:SetPoint("LEFT", r, "LEFT", 0, 0)
      r.label = Kit.text(r, "", "GameFontHighlight", COL.text, 300)
      r.label:SetPoint("LEFT", r, "LEFT", 34, 0)
      r.label:SetWordWrap(false)
      r.status = Kit.text(r, "", "GameFontNormal", COL.gold, 120)
      r.status:SetPoint("LEFT", r, "LEFT", 340, 0)
      r:Hide()
      f.rows[i] = r
    end
    f.apply = Kit.button(f, L["Import checked"], 140, 26, function() applyImport(f) end)
    f.apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    f.apply:Hide()
    local cancel = Kit.button(f, L["Cancel"], 90, 26, function() f:Hide() end)
    cancel:SetPoint("RIGHT", f.apply, "LEFT", -8, 0)
    importWin = f
  end
  local f = importWin
  f.edit:SetText("")
  f.recs = {}
  for i = 1, MAXR do f.rows[i]:Hide() end
  f.msg:SetText("")
  f.apply:Hide()
  f:Show()
  f.edit:SetFocus()
end
