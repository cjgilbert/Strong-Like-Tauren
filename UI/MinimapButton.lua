local ADDON, ns = ...
local C, U = ns.C, ns.U

-- Custom minimap button (no LibDBIcon): draggable around the edge; left toggles the window, right pauses.
ns.UI = ns.UI or {}
local M = {}
ns.UI.MinimapButton = M

local btn
local dragging = false

-- Shared by the button and the addon compartment entry.
function M:ShowTooltip(owner, anchor)
  if not owner then return end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
  GameTooltip:AddLine("Strong Like Tauren", 0.83, 0.66, 0.32)
  if ns.db and ns.env then
    local st = ns.Scheduler.status(ns.db, ns.now(), ns.ctx)
    GameTooltip:AddDoubleLine("Seated", U.fmtClock(st.seated), 0.95, 0.9, 0.8, 1, 1, 1)
    local rage = st.restDay and "Rest day"
      or ((st.rage >= 100 and st.featCooldown > 0) and ("Feat in " .. U.fmtDuration(st.featCooldown))
      or tostring(math.floor(st.rage)))
    GameTooltip:AddDoubleLine("Rage", rage, 0.95, 0.9, 0.8, 1, 1, 1)
    local nxt
    if st.W then nxt = "Walkabout waiting" else nxt = U.fmtDuration(st.dueIn) end
    GameTooltip:AddDoubleLine("Next break", nxt, 0.95, 0.9, 0.8, 1, 1, 1)
  else
    GameTooltip:AddLine("Loading...", 1, 1, 1)
  end
  GameTooltip:AddLine("Left-click: open window", 0.7, 0.64, 0.52)
  GameTooltip:AddLine("Right-click: pause / resume reminders", 0.7, 0.64, 0.52)
  GameTooltip:Show()
end

function M:Toggle()
  if ns.UI.Main and ns.UI.Main.Toggle then ns.UI.Main:Toggle() end
end

function M:TogglePause()
  if not ns.db then return end
  local N = ns.db.nudge
  local paused = ns.now() < (N.pauseUntil or 0) or ns.ctx.pausedSession
  if paused then ns.Do.resume() else ns.Do.pauseSession() end
end

local function place()
  if not btn then return end
  local s = ns.db and ns.db.settings.minimap
  local angle = math.rad((s and s.angle) or 200)
  local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
  local x, y = math.cos(angle), math.sin(angle)
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape == "SQUARE" then
    x = math.max(-w, math.min(w, x * w * 1.4142))
    y = math.max(-h, math.min(h, y * h * 1.4142))
  else
    x, y = x * w, y * h
  end
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function dragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not (mx and cx) then return end
  cx, cy = cx / scale, cy / scale
  local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
  ns.db.settings.minimap.angle = angle
  place()
end

function M:Refresh()
  if not btn then return end
  if ns.db and ns.db.settings.minimap.hide then btn:Hide() else btn:Show() end
  place()
end

function M:Init()
  if btn then return end
  btn = CreateFrame("Button", "StrongLikeTaurenMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetMovable(true)

  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 6, -5)
  icon:SetTexture(C.ICON)
  btn.icon = icon
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  btn:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then M:TogglePause() else M:Toggle() end
  end)
  btn:SetScript("OnEnter", function(self)
    if not dragging then M:ShowTooltip(self, "ANCHOR_LEFT") end
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnDragStart", function(self)
    dragging = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function() ns.guard(dragUpdate) end)
  end)
  btn:SetScript("OnDragStop", function(self)
    dragging = false
    self:SetScript("OnUpdate", nil)
    if ns.db then ns.Do.setSetting("minimap.angle", ns.db.settings.minimap.angle) end
  end)
  self:Refresh()
end
