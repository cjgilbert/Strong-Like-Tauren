local ADDON, ns = ...

-- Startup: SavedVariables on ADDON_LOADED, everything else on PLAYER_LOGIN.
ns.UI = ns.UI or {}
ns.ready = false

local function onAddonLoaded()
  local t = ns.now()
  local db, note = ns.DB.init(StrongLikeTaurenDB, t)
  ns.db = db
  StrongLikeTaurenDB = db
  ns.dbNote = note
  if note then ns.DB.logError(db, t, "DB init: " .. tostring(note)) end
end

local function onLogin()
  if not ns.db then onAddonLoaded() end
  local t = ns.now()
  local seed = t + math.floor((GetTime and GetTime() or 0) * 1000)
  local rng = ns.U.rng(seed)
  local cdb, idx = ns.DB.initChar(ns.db, StrongLikeTaurenCharDB, ns.Api.player(), rng)
  StrongLikeTaurenCharDB = cdb
  ns.cdb = cdb
  local defs, byId = ns.Library.build(ns.D.EXERCISES, ns.db.lib)
  ns.env = { defs = defs, byId = byId, rng = rng, char = idx }
  ns.History.prune(ns.db, t)
  ns.ready = true
  ns.Do.login(true) -- 10+ min since the last logout: fresh stretch, before any UI shows the clock

  local UI = ns.UI
  if UI.Totem and UI.Totem.Init then ns.guard(UI.Totem.Init, UI.Totem) end
  if UI.MinimapButton and UI.MinimapButton.Init then ns.guard(UI.MinimapButton.Init, UI.MinimapButton) end
  if UI.Options and UI.Options.Register then ns.guard(UI.Options.Register, UI.Options) end
  ns.Events.start()

  if ns.db.settings.firstRun and UI.FirstRun and UI.FirstRun.Show then
    ns.guard(UI.FirstRun.Show, UI.FirstRun)
  end
  ns.say(ns.quip("hello"))
  if ns.dbNote then ns.say("Note: saved data was reset or is from a newer version (" .. ns.dbNote .. ").") end
  UI.refreshAll()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      f:UnregisterEvent("ADDON_LOADED")
      ns.guard(onAddonLoaded)
    end
  elseif event == "PLAYER_LOGIN" then
    f:UnregisterEvent("PLAYER_LOGIN")
    ns.guard(onLogin)
  end
end)

-- Addon compartment (the minimap addon menu) --------------------------------------------------------------------------
function StrongLikeTauren_OnCompartmentClick(addonName, button)
  if not ns.ready then return end
  if button == "RightButton" then
    if ns.UI.MinimapButton then ns.UI.MinimapButton:TogglePause() end
  elseif ns.UI.Main and ns.UI.Main.Toggle then
    ns.UI.Main:Toggle()
  end
end

function StrongLikeTauren_OnCompartmentEnter(addonName, menuButtonFrame)
  if ns.UI.MinimapButton and menuButtonFrame then
    ns.guard(ns.UI.MinimapButton.ShowTooltip, ns.UI.MinimapButton, menuButtonFrame, "ANCHOR_LEFT")
  end
end

function StrongLikeTauren_OnCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end
