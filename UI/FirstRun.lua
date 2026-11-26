local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local Kit = UI.Kit
local COL = Kit.COL
local C = ns.C

-- One-time welcome panel: pitch, disclaimer and a few starter settings (applied immediately via ns.Do).
local FirstRun = {}
UI.FirstRun = FirstRun

local frame

local function build()
  local f = Kit.panel(UIParent, "StrongLikeTaurenFirstRun", 560, 580, COL.panel)
  f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(C.LOGO)
  logo:SetSize(64, 64)
  logo:SetPoint("TOPLEFT", 16, -14)
  local title = Kit.text(f, L["Welcome to Strong Like Tauren"], "GameFontNormalHuge", COL.gold, 440)
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -8)

  local scroll, content = Kit.scroll(f, 540, 460)
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -86)
  local flow = Kit.flow(content, 500)
  local list = {}
  f.list = list

  for _, p in ipairs(ns.D.HEALTH.pitch) do flow:note(p, 0, "GameFontHighlight", COL.text) end
  flow:note(ns.D.HEALTH.disclaimer, 0, "GameFontHighlightSmall", COL.amber)

  flow:header(L["How hard should it be?"])
  flow:add(Kit.settingSeg(content, list, Kit.tierOptions(), "tier", 500), 26)
  flow:note(L["Not sure? Peon is gentle, Grunt is the standard. You can change this any time in Settings."])

  flow:header(L["Break length"])
  flow:add(Kit.settingSeg(content, list, { { 1, L["Minimum 1"] }, { 2, L["Recommended 2"] }, { 5, L["Max benefit 5"] } }, "walk.dose", 500), 26)
  flow:note(L["You can pick any length from 1 to 5 minutes later in Settings."])

  flow:header(L["Keep it comfortable"])
  flow:add(Kit.settingCheck(content, list, L["Quiet: no jumping exercises"], "filters.quiet", 480), 24)
  flow:add(Kit.settingCheck(content, list, L["No floor exercises"], "filters.noFloor", 480), 24)
  flow:add(Kit.settingCheck(content, list, L["Easy on the wrists"], "filters.wrists", 480), 24)

  flow:header(L["Equipment I have"])
  for _, k in ipairs(C.EQUIP) do
    flow:add(Kit.settingCheck(content, list, C.EQUIP_NAME[k], "equip." .. k, 480), 24)
  end
  flow:header(L["How it works"])
  flow:note(L["Reminders appear in a small window at the top of your screen when an exercise is due."], 0, "GameFontHighlight", COL.text)
  flow:note(L["The Totem tracker lists what is due. Click Done when you have done it, Snooze to put it off, or Skip to let it go."], 0, "GameFontHighlight", COL.text)
  flow:note(L["Nothing pops up while you are in combat. Reminders wait until it is safe."], 0, "GameFontHighlight", COL.text)
  f.sampleBtn = Kit.button(content, L["Show me a sample reminder"], 240, 26, function()
    if UI.Toast and UI.Toast.Sample then pcall(UI.Toast.Sample, UI.Toast) end
    if UI.Totem and UI.Totem.Show then pcall(UI.Totem.Show, UI.Totem) end
  end)
  flow:add(f.sampleBtn, 28)
  flow:finish()

  local go = Kit.button(f, L["Let's go"], 160, 30, function()
    ns.Do.setSetting("firstRun", false)
    f:Hide()
    if ns.UI.refreshAll then pcall(ns.UI.refreshAll) end
  end)
  go:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
  f:SetScript("OnShow", function() for _, x in ipairs(list) do x:Refresh() end end)
  f:Hide()
  return f
end

function FirstRun:Show()
  if not frame then frame = build() end
  frame:Show()
end
