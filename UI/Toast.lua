local ADDON, ns = ...
local C, U = ns.C, ns.U

-- Due reminder: centered in the upper-middle of the screen, auto-closes after 10 s (paused while the mouse is over it),
-- a click on the body or Escape dismisses it. Never takes keyboard focus. Also the center-text and message variants.
ns.UI = ns.UI or {}
local Ts = {}
ns.UI.Toast = Ts

local WIDTH, AUTOHIDE = 400, 10
local PAD, ICON = 14, 44
local TEXTW = WIDTH - PAD - ICON - 10 - PAD
local frame, msgFrame, centerFrame
local cur = { w = nil, f = nil, sample = false }
local ENRAGED_COL = { 1.0, 0.35, 0.08 } -- red-orange: the Double Feat glow, subtitle and center text
local ENRAGED_SUB = "Rage overflowed to 200 \226\128\148 twice the exercises this time."
local anim = { t = 1, glow = 0 }

-- Used by the Message toast: under the Totem when it is up.
local function anchorTo(f, gap)
  f:ClearAllPoints()
  local tot = ns.UI.Totem and ns.UI.Totem.frame
  if tot and tot:IsShown() then
    f:SetPoint("TOPRIGHT", tot, "BOTTOMRIGHT", 0, -(gap or 6))
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
end

-- "Kodo Squats (Squats) x15" / "Mulgore Stroll (Walk) 2:00": pun name, the real name in brackets when it differs, then the
-- amount. Wraps in the toast, never truncated.
local function slotText(sl)
  local def = ns.env and ns.env.byId[sl.x]
  local name = def and (def.pun or def.name) or sl.x
  if def and def.pun and def.name and def.pun ~= def.name then name = name .. " (" .. def.name .. ")" end
  local amt = sl.walk and U.fmtClock(sl.a) or ns.Library.amountText(def, sl.a, "x")
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

-- Exactly one pending exercise that is not timed: returns its item id and slot index, else nil.
local function singleUntimed()
  local w, f = liveItems()
  local found, n = nil, 0
  for _, it in ipairs({ w or false, f or false }) do
    if it then
      for idx, sl in ipairs(it.slots) do
        if not sl.o then
          n = n + 1
          local def = ns.env and ns.env.byId[sl.x]
          found = { it.id, idx, ((def and def.kind == "s") or sl.walk) and true or false }
        end
      end
    end
  end
  if n == 1 and not found[3] then return found[1], found[2] end
end

-- Dismissing is never a skip: everything stays queued in the Totem.
local function dismiss()
  ns.Do.ack()
  Ts:Hide()
end

local function build()
  local th = ns.UI.Theme
  frame = th.Panel(UIParent, "StrongLikeTaurenToast", WIDTH, 120)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:Hide()
  -- soft gold glow that pulses a few times when the reminder appears
  frame.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  frame.glow:SetTexture(th.WHITE)
  frame.glow:SetVertexColor(th.C.gold[1], th.C.gold[2], th.C.gold[3], 1)
  frame.glow:SetAllPoints(frame)
  frame.glow:SetAlpha(0)
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(ICON, ICON)
  frame.icon:SetPoint("TOPLEFT", PAD, -PAD)
  frame.icon:SetTexture(C.ICON)
  local okT, title = pcall(th.Text, frame, "GameFontNormalHuge", "", th.C.gold)
  frame.title = okT and title or th.Text(frame, "GameFontNormalLarge", "", th.C.gold)
  frame.titleFont = okT and "GameFontNormalHuge" or "GameFontNormalLarge"
  frame.title:SetPoint("TOPLEFT", PAD + ICON + 10, -PAD)
  frame.title:SetWidth(TEXTW - 14) -- top-right corner is reserved for the close X
  frame.title:SetHeight(26)
  frame.title:SetJustifyV("TOP")
  -- one-line (wrapping) subtitle, shown above the exercise list for a Double Feat only
  frame.sub = th.Text(frame, "GameFontNormalSmall", "", ENRAGED_COL)
  frame.sub:SetWidth(TEXTW)
  frame.sub:SetWordWrap(true)
  frame.sub:SetJustifyV("TOP")
  frame.sub:Hide()
  frame.text = th.Text(frame, "GameFontHighlight", "", th.C.text)
  frame.text:SetWidth(TEXTW)
  frame.text:SetWordWrap(true) -- wraps instead of truncating; the height comes from GetStringHeight
  frame.text:SetJustifyV("TOP")
  frame.close = th.CloseButton(frame, dismiss)
  frame.go = th.Button(frame, "Let's go", 150, 24, function()
    ns.Do.ack()
    if not cur.sample then
      local oid, oidx = singleUntimed()
      if oid then -- a lone untimed exercise: "Done" completes it right here
        Ts:Hide()
        ns.Do.complete(oid, oidx, nil)
        return
      end
    end
    local id, idx = firstTimed()
    Ts:Hide()
    ns.Do.setSetting("totem.collapsed", false)
    if ns.UI.Totem then ns.UI.Totem:Show() end
    if id and ns.UI.Countdown then ns.UI.Countdown:Start(id, idx) end
  end)
  frame.go:SetPoint("BOTTOMLEFT", PAD, 12)
  frame.snooze = th.Button(frame, "Snooze 10", 150, 24, function()
    ns.Do.ack()
    ns.Do.snooze(10)
    Ts:Hide()
  end)
  frame.snooze:SetPoint("BOTTOMRIGHT", -PAD, 12)
  th.Tooltip(frame.snooze, { "Snooze 10", "Hides all pending exercises for 10 minutes." })
  th.Tooltip(frame.go, function()
    if frame.go:GetText() == "Done" then return { "Done", "Mark this exercise as finished." } end
    return { "Let's go", "Opens the Totem, and starts the countdown for a timed exercise." }
  end)

  -- a click anywhere on the body dismisses it (the buttons swallow their own clicks)
  frame:SetScript("OnMouseUp", function() dismiss() end)
  -- Escape closes it like any other window; that is a dismissal too
  frame:SetScript("OnHide", function(self)
    self.expires = nil
    if not self.closing then ns.Do.ack() end
  end)
  tinsert(UISpecialFrames, "StrongLikeTaurenToast")

  -- attention animation: a few glow pulses (AnimationGroup, guarded) plus a quick fade/scale-in (OnUpdate)
  pcall(function()
    local ag = frame.glow:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0)
    a1:SetToAlpha(0.28)
    a1:SetDuration(0.4)
    a1:SetSmoothing("IN_OUT")
    ag:SetLooping("BOUNCE")
    frame.glowAnim = ag
  end)

  frame:SetScript("OnUpdate", function(self, el)
    if anim.t < 1 then
      anim.t = math.min(1, anim.t + el / 0.25)
      self:SetAlpha(anim.t)
      pcall(self.SetScale, self, 0.9 + 0.1 * anim.t)
    end
    if anim.glow > 0 then
      anim.glow = anim.glow - el
      if anim.glow <= 0 then
        if self.glowAnim then pcall(self.glowAnim.Stop, self.glowAnim) end
        self.glow:SetAlpha(0)
      end
    end
    if not self.expires then return end
    -- the countdown waits while the mouse is over the reminder
    if self:IsMouseOver() then self.expires = self.expires + el end
    -- Timing out is not a skip and not an acknowledgement: everything stays in the Totem.
    if GetTime() >= self.expires then Ts:Hide() end
  end)
end

local function center(text, r, g, b)
  if not centerFrame then
    centerFrame = CreateFrame("Frame", "StrongLikeTaurenCenterText", UIParent)
    centerFrame:SetSize(600, 40)
    centerFrame:SetPoint("TOP", UIParent, "TOP", 0, -130)
    centerFrame:SetFrameStrata("HIGH")
    local fs = centerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetAllPoints()
    local font, _, flags = fs:GetFont()
    if font then pcall(fs.SetFont, fs, font, 26, flags) end
    centerFrame.fs = fs
    centerFrame:SetScript("OnUpdate", function(self, el)
      self.age = (self.age or 0) + el
      if self.age >= 4 then self:Hide() elseif self.age > 3 then self:SetAlpha(4 - self.age) end
    end)
    centerFrame:Hide()
  end
  centerFrame.color = { r or 0.83, g or 0.66, b or 0.32 }
  centerFrame.fs:SetTextColor(centerFrame.color[1], centerFrame.color[2], centerFrame.color[3])
  centerFrame.fs:SetText(text)
  centerFrame.age = 0
  centerFrame:SetAlpha(1)
  centerFrame:Show()
end

local function titleFor(w, f)
  local dbl = f and f.double
  if w and f then return dbl and "Walkabout & ENRAGED Double Feat!" or "Walkabout & Feat of Strength!" end
  if f then return dbl and "ENRAGED! Double Feat of Strength" or "Feat of Strength!" end
  return "Walkabout time!"
end

-- Re-renders the list from the live queue (or the Settings sample); returns how many lines are still pending.
local function render()
  local ls = cur.sample and { "Kodo Squats (Squats) x15", "Mulgore Stroll 2:00" } or pending(liveItems())
  frame.text:SetText(table.concat(ls, " \194\183 "))
  frame.go:SetText((not cur.sample and singleUntimed()) and "Done" or "Let's go")
  -- Double Feat: a subtitle line sits above the list (wraps, never truncated) and pushes it down
  local _, F = liveItems()
  local subH = 0
  frame.sub:ClearAllPoints()
  if not cur.sample and F and F.double then
    frame.sub:SetText(ENRAGED_SUB)
    frame.sub:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + ICON + 10, -(PAD + 30))
    frame.sub:Show()
    subH = math.max(12, frame.sub:GetStringHeight() or 0) + 4
  else
    frame.sub:SetText("")
    frame.sub:Hide()
  end
  frame.text:ClearAllPoints()
  frame.text:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + ICON + 10, -(PAD + 30 + subH))
  frame:SetHeight(math.max(110, PAD + 30 + subH + math.max(14, frame.text:GetStringHeight() or 0) + 10 + 24 + 12))
  return #ls
end

-- Called from ns.UI.refreshAll: follows the queue, and hides once nothing it listed is pending.
function Ts:Refresh()
  if not (frame and frame:IsShown()) then return end
  if ns.db and ns.Scheduler.snoozed(ns.db, ns.now(), ns.ctx or {}) then self:Hide() return end
  if render() == 0 then self:Hide() end
end

local function present(title, enraged)
  local th = ns.UI.Theme
  frame:ClearAllPoints()
  frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
  frame.title:SetText(title)
  frame.expires = GetTime() + AUTOHIDE
  anim.t = 0
  anim.glow = enraged and 4.5 or 2.5 -- a few more pulses for ENRAGED
  local gc = enraged and ENRAGED_COL or th.C.gold
  frame.glowKind = enraged and "enraged" or "gold"
  frame.glow:SetVertexColor(gc[1], gc[2], gc[3], 1)
  pcall(frame.title.SetFontObject, frame.title, enraged and "GameFontNormalLarge" or frame.titleFont)
  frame.title:SetTextColor(enraged and 1 or th.C.gold[1], enraged and 0.55 or th.C.gold[2], enraged and 0.2 or th.C.gold[3])
  frame:SetAlpha(0)
  pcall(frame.SetScale, frame, 0.9)
  frame:Show()
  if frame.glowAnim then
    pcall(frame.glowAnim.Stop, frame.glowAnim)
    pcall(frame.glowAnim.Play, frame.glowAnim)
  end
end

function Ts:Show(w, f, moment)
  if not (ns.db and ns.env) then return end
  if not frame then build() end
  cur.w, cur.f, cur.sample = w and w.id, f and f.id, false
  local title = titleFor(w, f)
  render()
  local dbl = f and f.double and true or false
  present(title, dbl)
  if ns.db.settings.nudge.center then
    if dbl then center(title, ENRAGED_COL[1], ENRAGED_COL[2], ENRAGED_COL[3]) else center(title) end
  end
end

-- Big center-screen text (also used by the ENRAGED! moment, which shows it regardless of the center-text setting).
function Ts:Center(text, r, g, b)
  center(text, r, g, b)
end

-- The ENRAGED! color, for the chat/center callers.
Ts.ENRAGED_COL = ENRAGED_COL

-- Settings "Test": a sample reminder that does not depend on the queue.
function Ts:Sample()
  if not (ns.db and ns.env) then return end
  if not frame then build() end
  cur.w, cur.f, cur.sample = nil, nil, true
  render()
  present("Walkabout time!")
end

function Ts:Hide()
  if frame then
    frame.closing = true
    frame:Hide()
    frame.closing = nil
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
    msgFrame:SetPoint("TOP", frame, "BOTTOM", 0, -6)
  else
    anchorTo(msgFrame)
  end
  msgFrame:Show()
end

function Ts:Achievement(a)
  if not a then return end
  self:Message(ns.L["Achievement: "] .. tostring(a.name), a.desc, C.ICON)
end
