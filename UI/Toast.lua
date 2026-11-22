local ADDON, ns = ...
local C, U = ns.C, ns.U

-- Compact non-modal reminder (Prompts-sized, auto-closes after 10 s) near the Totem. Never takes keyboard focus.
-- Also the center-text and message variants.
ns.UI = ns.UI or {}
local Ts = {}
ns.UI.Toast = Ts

local WIDTH, AUTOHIDE = 320, 10 -- same size as the Prompts frames; closes itself after 10 s
local frame, msgFrame, centerFrame
local cur = { w = nil, f = nil }
local anim = { t = 1 }

local function anchorTo(f, gap)
  f:ClearAllPoints()
  local tot = ns.UI.Totem and ns.UI.Totem.frame
  if tot and tot:IsShown() then
    f:SetPoint("TOPRIGHT", tot, "BOTTOMRIGHT", 0, -(gap or 6))
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
end

-- "Kodo Squats 15" / "Mulgore Stroll 2:00": the full name (pun, else real name) and the amount.
local function slotText(sl)
  local def = ns.env and ns.env.byId[sl.x]
  local name = def and (def.pun or def.name) or sl.x
  local amt = ((def and def.kind == "s") or sl.walk) and U.fmtClock(sl.a) or tostring(sl.a)
  return name .. " " .. amt
end

-- The toast only remembers which items it was about (by id); what it lists always comes from the live queue.
local function liveItems()
  local Q = ns.db and ns.db.queue
  if not Q then return nil, nil end
  return cur.w and ns.Queue.byId(Q, cur.w) or nil, cur.f and ns.Queue.byId(Q, cur.f) or nil
end

local function pending(w, f)
  local out = {}
  for _, it in ipairs({ w or false, f or false }) do -- not {w, f}: ipairs would stop at a nil Walkabout
    if it then
      for _, sl in ipairs(it.slots) do
        if not sl.o then out[#out + 1] = slotText(sl) end
      end
    end
  end
  return out
end

local function firstTimed()
  local w, f = liveItems()
  for _, it in ipairs({ w or false, f or false }) do
    if it then
      for idx, sl in ipairs(it.slots) do
        local def = ns.env and ns.env.byId[sl.x]
        if not sl.o and ((def and def.kind == "s") or sl.walk) then return it.id, idx end
      end
    end
  end
end

local function build()
  local th = ns.UI.Theme
  frame = th.Panel(UIParent, "StrongLikeTaurenToast", WIDTH, 84)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:Hide()
  frame.title = th.Text(frame, "GameFontNormal", "", th.C.gold)
  frame.title:SetPoint("TOPLEFT", 12, -10)
  frame.title:SetWidth(WIDTH - 24 - 18) -- top-right corner is reserved for the close X
  frame.title:SetHeight(16)
  frame.title:SetJustifyV("TOP")
  frame.text = th.Text(frame, "GameFontHighlight", "", th.C.text)
  frame.text:SetWidth(WIDTH - 24 - 18)
  frame.text:SetWordWrap(true) -- wraps instead of truncating; the height comes from GetStringHeight
  frame.text:SetJustifyV("TOP")
  frame.close = th.CloseButton(frame, function()
    ns.Do.ack()
    Ts:Hide() -- items stay queued in the Totem
  end)
  frame.go = th.Button(frame, "Let's go", 120, 22, function()
    ns.Do.ack()
    local id, idx = firstTimed()
    Ts:Hide()
    ns.Do.setSetting("totem.collapsed", false)
    if ns.UI.Totem then ns.UI.Totem:Show() end
    if id and ns.UI.Countdown then ns.UI.Countdown:Start(id, idx) end
  end)
  frame.go:SetPoint("BOTTOMLEFT", 12, 10)
  frame.snooze = th.Button(frame, "Snooze 10", 120, 22, function()
    ns.Do.ack()
    ns.Do.snooze(10)
    Ts:Hide()
  end)
  frame.snooze:SetPoint("BOTTOMRIGHT", -12, 10)

  frame:SetScript("OnUpdate", function(self, el)
    if anim.t < 1 then
      anim.t = math.min(1, anim.t + el / 0.25)
      self:SetAlpha(anim.t)
    end
    -- Timing out is not a skip and not an acknowledgement: everything stays in the Totem.
    if self.expires and GetTime() >= self.expires then Ts:Hide() end
  end)
end

local function center(text)
  if not centerFrame then
    centerFrame = CreateFrame("Frame", "StrongLikeTaurenCenterText", UIParent)
    centerFrame:SetSize(600, 40)
    centerFrame:SetPoint("TOP", UIParent, "TOP", 0, -180)
    centerFrame:SetFrameStrata("HIGH")
    local fs = centerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetAllPoints()
    local font, _, flags = fs:GetFont()
    if font then pcall(fs.SetFont, fs, font, 26, flags) end
    fs:SetTextColor(0.83, 0.66, 0.32)
    centerFrame.fs = fs
    centerFrame:SetScript("OnUpdate", function(self, el)
      self.age = (self.age or 0) + el
      if self.age >= 4 then self:Hide() elseif self.age > 3 then self:SetAlpha(4 - self.age) end
    end)
    centerFrame:Hide()
  end
  centerFrame.fs:SetText(text)
  centerFrame.age = 0
  centerFrame:SetAlpha(1)
  centerFrame:Show()
end

local function titleFor(w, f)
  if w and f then return "Walkabout & Feat of Strength!" end
  if f then return "Feat of Strength!" end
  return "Walkabout time!"
end

-- Re-renders the one-line list from the live queue; returns how many slots are still pending.
local function render()
  local ls = pending(liveItems())
  frame.text:SetText(table.concat(ls, " \194\183 "))
  frame.text:ClearAllPoints()
  frame.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -28)
  frame:SetHeight(math.max(84, 28 + math.max(14, frame.text:GetStringHeight() or 0) + 8 + 22 + 10))
  return #ls
end

-- Called from ns.UI.refreshAll: follows the queue, and hides once nothing it listed is pending.
function Ts:Refresh()
  if not (frame and frame:IsShown()) then return end
  if render() == 0 then self:Hide() end
end

function Ts:Show(w, f, moment)
  if not (ns.db and ns.env) then return end
  if not frame then build() end
  cur.w, cur.f = w and w.id, f and f.id
  local title = titleFor(w, f)
  frame.title:SetText(title)
  render()
  anchorTo(frame)
  frame.expires = GetTime() + AUTOHIDE
  anim.t = 0
  frame:SetAlpha(0)
  frame:Show()
  if ns.db.settings.nudge.center then center(title) end
end

function Ts:Hide()
  if frame then
    frame:Hide()
    frame.expires = nil
  end
end

function Ts:Message(title, text, icon)
  local th = ns.UI.Theme
  if not msgFrame then
    msgFrame = th.Panel(UIParent, "StrongLikeTaurenMessage", 280, 56)
    msgFrame:SetFrameStrata("HIGH")
    msgFrame:SetClampedToScreen(true)
    msgFrame.icon = msgFrame:CreateTexture(nil, "ARTWORK")
    msgFrame.icon:SetSize(36, 36)
    msgFrame.icon:SetPoint("LEFT", 10, 0)
    msgFrame.title = th.Text(msgFrame, "GameFontNormal", "", th.C.gold)
    msgFrame.title:SetPoint("TOPLEFT", msgFrame.icon, "TOPRIGHT", 8, -2)
    msgFrame.title:SetWidth(220)
    msgFrame.title:SetWordWrap(false)
    msgFrame.text = th.Text(msgFrame, "GameFontHighlightSmall", "", th.C.text)
    msgFrame.text:SetPoint("TOPLEFT", msgFrame.title, "BOTTOMLEFT", 0, -3)
    msgFrame.text:SetWidth(220)
    msgFrame.text:SetHeight(24)
    msgFrame.text:SetJustifyV("TOP")
    msgFrame:SetScript("OnUpdate", function(self, el)
      self.age = (self.age or 0) + el
      if self.age >= 6 then self:Hide() end
    end)
    msgFrame:Hide()
  end
  msgFrame.icon:SetTexture(icon or C.ICON)
  msgFrame.title:SetText(title or "")
  msgFrame.text:SetText(text or "")
  msgFrame.age = 0
  msgFrame:ClearAllPoints()
  if frame and frame:IsShown() then
    msgFrame:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -6)
  else
    anchorTo(msgFrame)
  end
  msgFrame:Show()
end

function Ts:Achievement(a)
  if not a then return end
  self:Message(ns.L["Achievement: "] .. tostring(a.name), a.desc, C.ICON)
end
