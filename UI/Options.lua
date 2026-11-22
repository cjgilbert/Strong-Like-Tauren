local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local Kit = UI.Kit
local COL = Kit.COL

-- Esc > Options > AddOns page.
local Options = {}
UI.Options = Options

local panel, category
local pending = false

local function build()
  local f = CreateFrame("Frame", "StrongLikeTaurenOptionsPanel", UIParent)
  f.name = "Strong Like Tauren"
  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(ns.C.LOGO)
  logo:SetSize(64, 64)
  logo:SetPoint("TOPLEFT", 16, -16)
  local title = Kit.text(f, "Strong Like Tauren", "GameFontNormalHuge", COL.gold)
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
  local desc = Kit.text(f, L["A workout buddy that breaks up your sitting and turns questing into bonus sets."],
    "GameFontHighlight", COL.text, 520)
  desc:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
  local open = Kit.button(f, L["Open Strong Like Tauren"], 220, 28, function()
    if UI.Main then UI.Main:Show() end
  end)
  open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
  f.controls = {}
  local en = Kit.check(f, L["Enabled"], function() return ns.db and ns.db.settings.enabled end,
    function(v) ns.Do.setSetting("enabled", v) end, 260)
  en:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -16)
  local snd = Kit.check(f, L["Sounds"], function() return ns.db and ns.db.settings.nudge.sound end,
    function(v) ns.Do.setSetting("nudge.sound", v) end, 260)
  snd:SetPoint("TOPLEFT", en, "BOTTOMLEFT", 0, -4)
  f:SetScript("OnShow", function()
    if ns.db then en:Refresh(); snd:Refresh() end
  end)
  f.OnCommit = function() end
  f.OnDefault = function() end
  f.OnRefresh = function() end
  return f
end

function Options:Register()
  if panel then return end
  panel = build()
  if Settings and Settings.RegisterCanvasLayoutCategory then
    pcall(function()
      category = Settings.RegisterCanvasLayoutCategory(panel, "Strong Like Tauren")
      Settings.RegisterAddOnCategory(category)
    end)
  end
  if not category and InterfaceOptions_AddCategory then
    pcall(InterfaceOptions_AddCategory, panel)
  end
end

local function doOpen()
  if not panel then Options:Register() end
  if Settings and Settings.OpenToCategory and category then
    local id = category.GetID and category:GetID() or category.ID
    local ok = pcall(Settings.OpenToCategory, id)
    if ok then return end
  end
  if InterfaceOptionsFrame_OpenToCategory then
    pcall(InterfaceOptionsFrame_OpenToCategory, panel)
    pcall(InterfaceOptionsFrame_OpenToCategory, panel)
  end
end

function Options:Open()
  if InCombatLockdown and InCombatLockdown() then
    if not pending then
      pending = true
      Kit.say(L["The options panel will open when combat ends."])
      local ev = CreateFrame("Frame")
      ev:RegisterEvent("PLAYER_REGEN_ENABLED")
      ev:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        pending = false
        doOpen()
      end)
    end
    return
  end
  doOpen()
end
