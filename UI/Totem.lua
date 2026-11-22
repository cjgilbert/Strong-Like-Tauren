local ADDON, ns = ...
local C, U = ns.C, ns.U

-- The Totem: always-on tracker with the seated clock, Rage bar and the pending Walkabout / Feat slots.
ns.UI = ns.UI or {}
local Tm = {}
ns.UI.Totem = Tm
local T -- Theme, resolved lazily so load order inside UI never matters

local WIDTH, HEADER_H, ROW_H, MAX_ROWS = 300, 56, 58, 6
local rows = {}
local frame, snoozeMenu
local snoozedNow = false
local hidden = false
local dirty = false
local entries = {}
local acc = 0
local forceLayout = false -- a collapse/expand click is applied even in combat (these frames are not protected)
local PAUSE_ICON, PLAY_ICON = "Interface\\TimeManager\\PauseButton", "Interface\\TimeManager\\PlayButton"
local UP_ICON = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local BTN = 14 -- header icon buttons: fixed size so the header never shifts
local HOLD_H = 14 -- fixed status line at the bottom, reserved only while reminders are on hold
local holdReserved = false
local HOLD_WHY = {
  combat = "in combat", encounter = "boss fight", loading = "loading", dead = "dead", cinematic = "cutscene",
  settling = "just a moment", instance = "instance", away = "away",
}

local function theme()
  T = T or ns.UI.Theme
  return T
end

local function settings()
  return ns.db and ns.db.settings
end

-- Position -----------------------------------------------------------------------------------------------------------
local function applyPosition()
  local t = settings() and settings().totem or {}
  frame:ClearAllPoints()
  if t.point and t.x and t.y then
    frame:SetPoint(t.point, UIParent, t.point, t.x, t.y)
  else
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -240)
  end
end

local function savePosition()
  local s = settings()
  if not s then return end
  local point, _, _, x, y = frame:GetPoint(1)
  if point then
    s.totem.point, s.totem.x, s.totem.y = point, x, y
  end
end

function Tm:ResetPosition()
  local s = settings()
  if s then
    s.totem.point, s.totem.x, s.totem.y = nil, nil, nil
    s.totem.locked = false
  end
  if frame then
    applyPosition()
    savePosition()
  end
end

-- Snooze menu ----------------------------------------------------------------------------------------------------------
local function buildSnoozeMenu()
  local th = theme()
  snoozeMenu = th.Panel(UIParent, "StrongLikeTaurenSnoozeMenu", 110, 100)
  snoozeMenu:SetFrameStrata("DIALOG")
  snoozeMenu:Hide()
  snoozeMenu.btns = {}
  local function add(i, label, fn)
    local b = th.Button(snoozeMenu, label, 98, 20, function()
      snoozeMenu:Hide()
      fn()
    end)
    b:SetPoint("TOP", 0, -6 - (i - 1) * 22)
    snoozeMenu.btns[i] = b
    return b
  end
  add(1, "5 min", function() ns.Do.snooze(5) end)
  add(2, "10 min", function() ns.Do.snooze(10) end)
  add(3, "20 min", function() ns.Do.snooze(20) end)
  add(4, "Until I leave", function() ns.Do.snoozeInstance() end)
  snoozeMenu.leaveAt = 0
  snoozeMenu:SetScript("OnUpdate", function(self, el)
    local over = self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver())
    if over then self.idle = 0 else
      self.idle = (self.idle or 0) + el
      if self.idle > 0.6 then self:Hide() end
    end
  end)
end

local function openSnoozeMenu(anchor)
  if not snoozeMenu then buildSnoozeMenu() end
  if snoozeMenu:IsShown() and snoozeMenu.anchor == anchor then snoozeMenu:Hide() return end
  local inInst = ns.ctx and ns.ctx.inst and ns.ctx.inst ~= "none"
  snoozeMenu.btns[4]:SetShown(inInst and true or false)
  snoozeMenu:SetHeight(inInst and 106 or 84)
  snoozeMenu.anchor = anchor
  snoozeMenu.idle = 0
  snoozeMenu:ClearAllPoints()
  snoozeMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  snoozeMenu:Show()
end

-- Rows -------------------------------------------------------------------------------------------------------------------
local SWAP_WHY = {
  limit = "No more swaps for that one.",
  none = "Nothing else fits right now.",
  resolved = "Already done.",
  gone = "That one is gone.",
}

local amountText, itemLabel

local function buildRow(i)
  local th = theme()
  local r = CreateFrame("Frame", nil, frame)
  r:SetSize(WIDTH - 12, ROW_H - 4)
  r:EnableMouse(true)
  th.solid(r, { 0.24, 0.15, 0.09, 0.9 }, "BACKGROUND", -7)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(28, 28)
  r.icon:SetPoint("TOPLEFT", 4, -3)
  r.name = th.Text(r, "GameFontNormalSmall", "", th.C.text)
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 5, -1)
  r.name:SetPoint("RIGHT", r, "RIGHT", -5, 0)
  r.name:SetHeight(14)
  r.name:SetWordWrap(false)
  -- Line 2: "real name · amount" (dimmer). Fixed one-line height; the full text is always in the tooltip.
  -- The buttons sit in the bottom strip (BOTTOMLEFT, 18 high), below both text lines, so they never overlap the text.
  r.kind = th.Text(r, "GameFontNormalSmall", "", th.C.dim)
  r.kind:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
  r.kind:SetPoint("RIGHT", r, "RIGHT", -5, 0)
  r.kind:SetHeight(12)
  r.kind:SetWordWrap(false)

  local function act(fn)
    return function(_, mouse)
      if not r.itemId then return end
      fn(mouse)
    end
  end
  r.done = th.Button(r, "Done", 50, 18, act(function(mouse)
    if mouse == "RightButton" then
      if ns.UI.Prompts then ns.UI.Prompts:Partial(r.itemId, r.idx) end
    else
      ns.Do.complete(r.itemId, r.idx, nil)
    end
  end))
  r.start = th.Button(r, "Start", 50, 18, act(function()
    if ns.UI.Countdown then ns.UI.Countdown:Start(r.itemId, r.idx) end
  end))
  r.snooze = th.Button(r, "Snooze", 56, 18, act(function() openSnoozeMenu(r.snooze) end))
  r.swap = th.Button(r, "Swap", 46, 18, act(function()
    local ok, why = ns.Do.swap(r.itemId, r.idx)
    if ok == false and why then ns.say(SWAP_WHY[why] or tostring(why)) end
  end))
  r.skip = th.Button(r, "Skip", 44, 18, act(function() ns.Do.skip(r.itemId, r.idx) end))
  r.btnList = { r.done, r.start, r.snooze, r.swap, r.skip }
  th.Tooltip(r.done, { "Done", "Left-click: finished it all.", "Right-click: log a partial amount." })
  th.Tooltip(r, function()
    local d = r.def
    if not d then return nil end
    local lines = { d.pun or d.name }
    if d.pun and d.pun ~= d.name then lines[#lines + 1] = d.name end
    lines[#lines + 1] = itemLabel(r.item) .. " \194\183 " .. amountText(d, r.slot)
    if d.desc then lines[#lines + 1] = d.desc end
    if r.slot and r.slot.why then lines[#lines + 1] = r.slot.why end
    return lines
  end)
  r:Hide()
  return r
end

function itemLabel(item)
  if item and item.k == "W" then return "Walkabout" end
  return (item and item.double) and "Double Feat" or "Feat of Strength"
end

function amountText(def, slot)
  if def and def.kind == "s" or slot.walk then return U.fmtClock(slot.a) end
  return "x" .. tostring(slot.a)
end

local function layoutRow(r, i, e)
  local th = theme()
  r.itemId, r.idx, r.slot, r.item = e.item.id, e.idx, e.slot, e.item
  local def = ns.env and ns.env.byId[e.slot.x]
  r.def = def
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -HEADER_H - (i - 1) * ROW_H)
  r.icon:SetTexture(def and def.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  r.name:SetText(def and (def.pun or def.name) or e.slot.x)
  local real = def and def.pun and def.pun ~= def.name and def.name or nil
  local amt = amountText(def, e.slot)
  r.kind:SetText(real and (real .. " \194\183 " .. amt) or (itemLabel(e.item) .. " \194\183 " .. amt))
  local timed = (def and def.kind == "s") or e.slot.walk
  local x = 4
  for _, b in ipairs(r.btnList) do
    if b == r.start and not timed then
      b:Hide()
    else
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 3)
      b:Show()
      x = x + b:GetWidth() + 3
    end
  end
  r:Show()
end

-- Header ---------------------------------------------------------------------------------------------------------------------
local function repProgress()
  local rep = ns.db.prog.rep
  local st = ns.Progress.standing(rep)
  local cur, nxt = C.STANDINGS[st], C.STANDINGS[st + 1]
  local function n(v) return (tostring(math.floor(v)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
  if not nxt then return 1, ("%s: %s %s"):format(C.FACTION, cur.name, n(rep)) end
  return (rep - cur.min) / math.max(1, nxt.min - cur.min),
    ("%s: %s %s / %s"):format(C.FACTION, cur.name, n(rep), n(nxt.min))
end

-- Text for the "reminders on hold" line, or nil when nothing is pending or the gate is open / snoozed / switched off.
local function holdText()
  if not (ns.db and ns.ready and #entries > 0) then return nil end
  local g = ns.Scheduler.gate(ns.db, ns.now(), ns.ctx or {})
  if g.may or not g.why or g.why == "snoozed" or g.why == "off" then return nil end
  if g.why == "paused" then return "Reminders paused" end
  return "Reminder waits: " .. (HOLD_WHY[g.why] or g.why)
end

function Tm:UpdateHeader()
  if not (frame and ns.db and ns.env) then return end
  local th = theme()
  local t = ns.now()
  local st = ns.Scheduler.status(ns.db, t, ns.ctx)
  local every = math.max(1, st.every)
  local seated = st.seated
  local frac = math.min(1, seated / every)
  frame.seat:SetValue(frac)
  local txt = U.fmtClock(seated)
  if st.paused then
    -- Paused: neutral color and the word itself, never color alone.
    frame.seat:SetBarColor(th.C.dim)
    txt = "Paused " .. txt
  else
    frame.seat:SetBarColor(frac < 0.75 and th.C.green or (frac < 1 and th.C.amber or th.C.red))
    if ns.ctx and ns.ctx.away then txt = txt .. " (away)" end
    if st.rooted > 0 and seated >= every then txt = ("Rooted x%d   %s"):format(st.rooted, txt) else txt = "Seated " .. txt end
  end
  frame.seat.text:SetText(txt)
  if frame.pause then
    frame.pause.icon:SetTexture(st.paused and PLAY_ICON or PAUSE_ICON)
  end

  -- Rage bar: the 0-100 fill, plus a lighter overflow segment from the left for banked Rage (100-200). The text always
  -- says it too (never color alone). Fixed sizes: only the segment's width changes.
  local bank = ns.db.settings.rage.bank
  frame.rage:SetValue(math.min(1, st.rage / 100))
  local over = bank and math.max(0, math.min(1, (st.rage - 100) / 100)) or 0
  frame.rage.over:SetWidth(math.max(0.001, (frame.rage:GetWidth() or 0) * over))
  frame.rage.over:SetShown(over > 0)
  local rtxt
  local rg = math.floor(st.rage)
  if st.restDay then rtxt = "Rest day"
  elseif st.rage >= 100 and st.featCooldown > 0 then
    if bank and st.rage >= C.RAGE_BANK then rtxt = "Double Feat in " .. U.fmtDuration(st.featCooldown)
    elseif bank then rtxt = "Feat in " .. U.fmtDuration(st.featCooldown) .. " \194\183 Rage " .. rg
    else rtxt = "Feat in " .. U.fmtDuration(st.featCooldown) end
  else rtxt = "Rage " .. rg end
  frame.rage.text:SetText(rtxt)

  -- The rep bar shows reputation only: fixed color, never an exercise or buff label.
  local p, repText = repProgress()
  frame.rep:SetValue(p)
  frame.rep:SetBarColor(th.C.gold)
  frame.rep.text:SetText(repText)

  local hold = holdText()
  frame.hold:SetText(hold or "")
  frame.hold:SetShown(hold ~= nil and holdReserved)
end

-- Refresh -------------------------------------------------------------------------------------------------------------------------
local function collect()
  entries = {}
  if not (ns.db and ns.db.queue) then return end
  snoozedNow = ns.Scheduler.snoozed(ns.db, ns.now(), ns.ctx or {})
  if snoozedNow then return end -- a snooze hides the work completely
  for _, it in ipairs(ns.Queue.list(ns.db.queue)) do
    for idx, sl in ipairs(it.slots) do
      if not sl.o and #entries < MAX_ROWS then entries[#entries + 1] = { item = it, idx = idx, slot = sl } end
    end
  end
end

function Tm:Refresh()
  if not frame then return end
  if not (ns.db and ns.ready) then frame:Hide() return end
  local s = ns.db.settings
  frame:SetScale(s.totem.scale or 1)
  frame.lock:SetAlpha(s.totem.locked and 1 or 0.35)
  collect()
  self:UpdateHeader()
  local collapsed = s.totem.collapsed
  frame.collapse:SetText(collapsed and "+" or "-")
  if InCombatLockdown and InCombatLockdown() and not forceLayout then
    dirty = true
    return
  end
  forceLayout = false
  dirty = false
  for i = 1, MAX_ROWS do
    local r = rows[i]
    if not r then r = buildRow(i); rows[i] = r end
    if not collapsed and entries[i] then layoutRow(r, i, entries[i]) else r:Hide() r.itemId = nil end
  end
  local n = collapsed and 0 or #entries
  holdReserved = holdText() ~= nil
  frame:SetHeight(HEADER_H + n * ROW_H + (n > 0 and 4 or 0) + (holdReserved and HOLD_H or 0))
  self:UpdateHeader()
  if hidden or (s.totem.hideIdle and #entries == 0) then frame:Hide() else frame:Show() end
end

function Tm:Show()
  hidden = false
  self:Refresh()
end

function Tm:Hide()
  hidden = true
  if frame then frame:Hide() end
end

-- Init ----------------------------------------------------------------------------------------------------------------------------
function Tm:Init()
  if frame then return end
  local th = theme()
  frame = th.Panel(UIParent, "StrongLikeTaurenTotem", WIDTH, HEADER_H)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:Hide()
  Tm.frame = frame

  frame:SetScript("OnDragStart", function(self)
    if ns.db and not ns.db.settings.totem.locked then self:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetSize(34, 34)
  icon:SetPoint("TOPLEFT", 8, -8)
  icon:SetTexture(C.ICON)
  frame.icon = icon

  -- The seated bar is narrowed by two fixed 14 px icon buttons (Pause, I got up) sitting right of it.
  frame.seat = th.Bar(frame, WIDTH - 46 - 30 - 2 * (BTN + 2), 14, th.C.green)
  frame.seat:SetPoint("TOPLEFT", 48, -8)
  frame.pause = th.IconButton(frame, PAUSE_ICON, BTN, nil, function()
    if ns.db and ns.db.body.paused then ns.Do.resumeClock() else ns.Do.pauseClock() end
  end)
  frame.pause:SetPoint("TOPLEFT", frame.seat, "TOPRIGHT", 2, 0)
  th.Tooltip(frame.pause, function()
    if ns.db and ns.db.body.paused then return { "Resume seated clock", "Pick up where the clock stopped." } end
    return { "Pause seated clock \226\128\148 I'm getting up for a bit",
             "Stops the clock, Rage and reminders. Resumes when you click again, or when you move after 5 seconds." }
  end)
  frame.gotUp = th.IconButton(frame, UP_ICON, BTN, { "I already got up \226\128\148 reset the seated clock",
                                                      "Counts as a break and starts the clock from 0:00." },
    function() ns.Do.gotUp() end)
  frame.gotUp:SetPoint("TOPLEFT", frame.pause, "TOPRIGHT", 2, 0)
  frame.rage = th.Bar(frame, WIDTH - 46 - 30, 12, th.C.rage)
  frame.rage:SetPoint("TOPLEFT", 48, -24)
  frame.rage.over = frame.rage:CreateTexture(nil, "ARTWORK", nil, 2)
  frame.rage.over:SetTexture(th.WHITE)
  frame.rage.over:SetVertexColor(1, 0.55, 0.2, 0.9) -- lighter orange over the red fill
  frame.rage.over:SetPoint("TOPLEFT", frame.rage, "TOPLEFT", 0, 0)
  frame.rage.over:SetPoint("BOTTOMLEFT", frame.rage, "BOTTOMLEFT", 0, 0)
  frame.rage.over:SetWidth(0.001)
  frame.rage.over:Hide()
  frame.rep = th.Bar(frame, WIDTH - 46 - 30, 12, th.C.gold)
  frame.rep:SetPoint("TOPLEFT", 48, -38)

  -- Status line shown while reminders are on hold; fixed height, one line, short strings (never truncated).
  frame.hold = th.Text(frame, "GameFontNormalSmall", "", th.C.amber)
  frame.hold:SetHeight(12)
  frame.hold:SetWordWrap(false)
  frame.hold:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 4)
  frame.hold:Hide()

  frame.collapse = th.Button(frame, "-", 18, 18, function()
    forceLayout = true
    ns.Do.setSetting("totem.collapsed", not ns.db.settings.totem.collapsed)
    forceLayout = false
  end)
  frame.collapse:SetPoint("TOPRIGHT", -6, -7)
  th.Tooltip(frame.collapse, function()
    if ns.db and ns.db.settings.totem.collapsed then return { "Expand", "Show the pending Walkabout and Feats." } end
    return { "Collapse", "Show only the header." }
  end)

  frame.lock = th.Button(frame, "L", 18, 18, function()
    ns.Do.setSetting("totem.locked", not ns.db.settings.totem.locked)
  end)
  frame.lock:SetPoint("TOPRIGHT", -6, -27)
  th.Tooltip(frame.lock, { "Lock position", "Locked Totems cannot be dragged." })

  th.Tooltip(frame.rep, function()
    local p, name = repProgress()
    return { "Bloodhoof Athletic Club", name .. " (" .. ns.db.prog.rep .. " rep)" }
  end)

  applyPosition()

  -- throttled clock updates; relayout after combat
  frame:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc >= 1 then
      acc = 0
      if ns.ready and ns.db and ns.Scheduler.snoozed(ns.db, ns.now(), ns.ctx or {}) ~= snoozedNow then
        ns.guard(Tm.Refresh, Tm) -- a snooze began or ended
      elseif ns.ready and ns.db and (holdText() ~= nil) ~= holdReserved then
        ns.guard(Tm.Refresh, Tm) -- reminders went on hold or came off hold (re-layout waits for combat to end)
      end
      if frame:IsShown() then Tm:UpdateHeader() end
    end
  end)
  frame:SetScript("OnShow", function() Tm:UpdateHeader() end)
  local ev = CreateFrame("Frame")
  pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
  ev:SetScript("OnEvent", function()
    if dirty then ns.guard(Tm.Refresh, Tm) end
  end)
  Tm.eventFrame = ev
  self:Refresh()
end
