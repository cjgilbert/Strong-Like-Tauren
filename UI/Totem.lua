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
local entries = {}
local acc = 0
local RAGE_W = WIDTH - 46 - 30 -- width of the Rage / rep bars (fixed; never read back from the frame)
local PAUSE_ICON, PLAY_ICON = "Interface\\TimeManager\\PauseButton", "Interface\\TimeManager\\PlayButton"
local UP_ICON = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local BTN = 14 -- header icon buttons: fixed size so the header never shifts
local HOLD_H = 14 -- fixed status line at the bottom, reserved only while reminders are on hold
local holdReserved = false
local SNOOZE_H = 22 -- snoozed-with-work line (text + "Do now" button), same bottom slot as the hold line
local snoozeReserved = false
local PAUSE_H = 22 -- paused line (text + "Resume" button), same bottom slot as the snoozed line
local pauseReserved = false
local SKIP_W = 62 -- row buttons: Done 50, Start 50, Snooze 56, Swap 46, Skip... 62 + 3 px gaps stay inside WIDTH - 12
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

-- Small pop-up menus (snooze, skip) -------------------------------------------------------------------------------------
-- entries = { {label, fn}, ... }; header (optional) is a dim line above the buttons. Closes when the mouse leaves.
local skipMenu
local MENU_HEAD = 16
local function buildMenu(name, w, header, entries)
  local th = theme()
  local m = th.Panel(UIParent, name, w + 12, 12)
  m:SetFrameStrata("DIALOG")
  m:Hide()
  m.btns = {}
  m.top = header and MENU_HEAD or 0
  if header then
    m.head = th.Text(m, "GameFontNormalSmall", header, th.C.dim)
    m.head:SetPoint("TOPLEFT", 8, -6)
  end
  for i, e in ipairs(entries) do
    local b = th.Button(m, e[1], w, 20, function()
      m:Hide()
      e[2](m)
    end)
    b:SetPoint("TOP", 0, -6 - m.top - (i - 1) * 22)
    m.btns[i] = b
  end
  m:SetHeight(12 + m.top + #entries * 22 - 2)
  m:SetScript("OnUpdate", function(self, el)
    local over = self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver())
    if over then self.idle = 0 else
      self.idle = (self.idle or 0) + el
      if self.idle > 0.6 then self:Hide() end
    end
  end)
  return m
end

local function openMenu(m, anchor, shownCount)
  if m:IsShown() and m.anchor == anchor then m:Hide() return end
  if snoozeMenu and snoozeMenu ~= m then snoozeMenu:Hide() end
  if skipMenu and skipMenu ~= m then skipMenu:Hide() end
  m:SetHeight(12 + m.top + (shownCount or #m.btns) * 22 - 2)
  m.anchor = anchor
  m.idle = 0
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  m:Show()
end

-- Snooze hides everything (it is global), so the menu says so.
local function openSnoozeMenu(anchor)
  if not snoozeMenu then
    snoozeMenu = buildMenu("StrongLikeTaurenSnoozeMenu", 98, "Hide all for:", {
      { "5 min", function() ns.Do.snooze(5) end },
      { "10 min", function() ns.Do.snooze(10) end },
      { "20 min", function() ns.Do.snooze(20) end },
      { "Until I leave", function() ns.Do.snoozeInstance() end },
    })
  end
  local inInst = ns.ctx and ns.ctx.inst and ns.ctx.inst ~= "none"
  snoozeMenu.btns[4]:SetShown(inInst and true or false)
  openMenu(snoozeMenu, anchor, inInst and 4 or 3)
end

-- Skip is a tiny menu so "I did some..." (partial logging) is one visible click away.
local function openSkipMenu(anchor, row)
  if not skipMenu then
    skipMenu = buildMenu("StrongLikeTaurenSkipMenu", 100, nil, {
      { "Skip", function(m)
        if m.itemId then ns.Do.skip(m.itemId, m.idx) end
      end },
      { "I did some...", function(m)
        if m.itemId and ns.UI.Prompts then ns.UI.Prompts:Partial(m.itemId, m.idx) end
      end },
    })
  end
  skipMenu.itemId, skipMenu.idx = row.itemId, row.idx
  openMenu(skipMenu, anchor)
end

-- Rows -------------------------------------------------------------------------------------------------------------------
local SWAP_WHY = {
  limit = "No more swaps for that one.",
  none = "Nothing else fits right now.",
  resolved = "Already done.",
  gone = "That one is gone.",
}

local amountText, itemLabel, pendingEntries

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
  -- "Skip..." opens a tiny menu (Skip / I did some...). A separate "Some" button does not fit the fixed row width.
  r.skip = th.Button(r, "Skip...", SKIP_W, 18, act(function() openSkipMenu(r.skip, r) end))
  -- fixed widths, so layout never reads frame geometry (safe in combat)
  r.done._w, r.start._w, r.snooze._w, r.swap._w, r.skip._w = 50, 50, 56, 46, SKIP_W
  r.btnList = { r.done, r.start, r.snooze, r.swap, r.skip }
  th.Tooltip(r.done, { "Done", "Left-click: finished it all.", "Right-click: log a partial amount." })
  th.Tooltip(r.snooze, { "Snooze all", "Hides all pending exercises for a while. They come back with a reminder." })
  th.Tooltip(r.skip, { "Skip or log some", "Skip this one, or log that you did only part of it." })
  th.Tooltip(r, function()
    local d = r.def
    if not d then return nil end
    local lines = { d.pun or d.name }
    if d.pun and d.pun ~= d.name then lines[#lines + 1] = d.name end
    lines[#lines + 1] = itemLabel(r.item) .. " \194\183 " .. amountText(d, r.slot)
    if d.desc then lines[#lines + 1] = d.desc end
    if r.slot and r.slot.why then lines[#lines + 1] = r.slot.why end
    local it = r.item
    if it and it.k == "F" and it.exp then
      local left = it.exp - ns.now()
      if left > 0 then lines[#lines + 1] = "Expires in " .. U.fmtDuration(left) end
    end
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
  return ns.Library.amountText(def, slot.a, "x")
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
      x = x + b._w + 3
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
  local total = ("%s (%s rep total)"):format(cur.name, n(rep))
  if not nxt then return 1, ("%s: %s"):format(C.FACTION, cur.name), total end
  return (rep - cur.min) / math.max(1, nxt.min - cur.min),
    ("%s: %s %s / %s"):format(C.FACTION, cur.name, n(rep - cur.min), n(nxt.min - cur.min)), total
end

-- Text for the "reminders on hold" line, or nil when nothing is pending or the gate is open / snoozed / switched off.
local function holdText()
  if not (ns.db and ns.ready and #entries > 0) then return nil end
  local g = ns.Scheduler.gate(ns.db, ns.now(), ns.ctx or {})
  if g.may or not g.why or g.why == "snoozed" or g.why == "off" then return nil end
  if g.why == "paused" then return nil end -- shown by pauseInfo (own line with a Resume button)
  return "Reminder waits: " .. (HOLD_WHY[g.why] or g.why)
end

-- The gate says "paused" for three different things; tell them apart. Returns text, kind ("reminders"|"clock") or nil.
-- Reminder pause (minimap right-click, /tauren pause) wins over the seated-clock pause (Totem pause icon).
local function pauseInfo()
  if not (ns.db and ns.ready and #entries > 0) then return nil end
  local t = ns.now()
  local g = ns.Scheduler.gate(ns.db, t, ns.ctx or {})
  if g.may or g.why ~= "paused" then return nil end
  local left = (ns.db.nudge.pauseUntil or 0) - t
  if left > 0 then return "Reminders paused \194\183 " .. U.fmtDuration(left) .. " left", "reminders" end
  if ns.ctx and ns.ctx.pausedSession then return "Reminders paused \194\183 until reload", "reminders" end
  if ns.db.body.paused then return "Clock paused \194\183 getting up", "clock" end
  return "Reminders paused", "reminders"
end

-- Pending rows, ignoring any snooze. Under "with the next Walkabout" a lone Feat stays out of the Totem until it is
-- deliverable (so work never shows without its reminder).
function pendingEntries()
  local list = {}
  if not (ns.db and ns.db.queue) then return list end
  local _, dF = ns.Scheduler.deliverable(ns.db, ns.now())
  for _, it in ipairs(ns.Queue.list(ns.db.queue)) do
    if it.k ~= "F" or it == dF then
      for idx, sl in ipairs(it.slots) do
        if not sl.o and #list < MAX_ROWS then list[#list + 1] = { item = it, idx = idx, slot = sl } end
      end
    end
  end
  return list
end

-- Text for the snoozed line, or nil unless a snooze is hiding pending work.
local function snoozeText()
  if not (ns.db and ns.ready) then return nil end
  local t = ns.now()
  if not ns.Scheduler.snoozed(ns.db, t, ns.ctx or {}) or #pendingEntries() == 0 then return nil end
  local left = (ns.db.nudge.snoozeUntil or 0) - t
  if left > 0 then return "Snoozed \194\183 " .. U.fmtDuration(left) .. " left" end
  return "Snoozed until you leave"
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
  frame.rage.over:SetWidth(math.max(0.001, RAGE_W * over))
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
  local sn = snoozeReserved and snoozeText() or nil
  frame.snoozed:SetText(sn or "")
  frame.snoozed:SetShown(sn ~= nil)
  frame.doNow:SetShown(sn ~= nil)
  local pt, pk = nil, nil
  if pauseReserved then pt, pk = pauseInfo() end
  frame.paused:SetText(pt or "")
  frame.paused:SetShown(pt ~= nil)
  frame.resume.kind = pk
  frame.resume:SetShown(pt ~= nil)
end

-- Refresh -------------------------------------------------------------------------------------------------------------------------
local function collect()
  entries = {}
  if not (ns.db and ns.db.queue) then return end
  snoozedNow = ns.Scheduler.snoozed(ns.db, ns.now(), ns.ctx or {})
  if snoozedNow then return end -- a snooze hides the work completely
  entries = pendingEntries()
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
  for i = 1, MAX_ROWS do
    local r = rows[i]
    if not r then r = buildRow(i); rows[i] = r end
    if not collapsed and entries[i] then layoutRow(r, i, entries[i]) else r:Hide() r.itemId = nil end
  end
  local n = collapsed and 0 or #entries
  holdReserved = holdText() ~= nil
  snoozeReserved = snoozeText() ~= nil
  pauseReserved = pauseInfo() ~= nil
  frame:SetHeight(HEADER_H + n * ROW_H + (n > 0 and 4 or 0) + (holdReserved and HOLD_H or 0)
    + (snoozeReserved and SNOOZE_H or 0) + (pauseReserved and PAUSE_H or 0))
  self:UpdateHeader()
  if hidden or (s.totem.hideIdle and #entries == 0 and not snoozeReserved) then frame:Hide() else frame:Show() end
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
  frame.rage = th.Bar(frame, RAGE_W, 12, th.C.rage)
  frame.rage:SetPoint("TOPLEFT", 48, -24)
  frame.rage.over = frame.rage:CreateTexture(nil, "ARTWORK", nil, 2)
  frame.rage.over:SetTexture(th.WHITE)
  frame.rage.over:SetVertexColor(1, 0.55, 0.2, 0.9) -- lighter orange over the red fill
  frame.rage.over:SetPoint("TOPLEFT", frame.rage, "TOPLEFT", 0, 0)
  frame.rage.over:SetPoint("BOTTOMLEFT", frame.rage, "BOTTOMLEFT", 0, 0)
  frame.rage.over:SetWidth(0.001)
  frame.rage.over:Hide()
  frame.rep = th.Bar(frame, RAGE_W, 12, th.C.gold)
  frame.rep:SetPoint("TOPLEFT", 48, -38)

  -- Status line shown while reminders are on hold; fixed height, one line, short strings (never truncated).
  frame.hold = th.Text(frame, "GameFontNormalSmall", "", th.C.amber)
  frame.hold:SetHeight(12)
  frame.hold:SetWordWrap(false)
  frame.hold:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 4)
  frame.hold:Hide()

  -- Snoozed line: status text on the left, a fixed-size "Do now" button on the right (only while a snooze hides work).
  frame.snoozed = th.Text(frame, "GameFontNormalSmall", "", th.C.amber)
  frame.snoozed:SetHeight(12)
  frame.snoozed:SetWordWrap(false)
  frame.snoozed:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 6)
  frame.snoozed:Hide()
  frame.doNow = th.Button(frame, "Do now", 56, 18, function() ns.Do.unsnooze() end)
  frame.doNow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 3)
  frame.doNow:Hide()
  th.Tooltip(frame.doNow, { "Do now", "Bring back snoozed exercises now" })

  -- Paused line: which pause it is on the left, a fixed-size "Resume" button on the right (same slot as the snoozed line).
  frame.paused = th.Text(frame, "GameFontNormalSmall", "", th.C.amber)
  frame.paused:SetHeight(12)
  frame.paused:SetWordWrap(false)
  frame.paused:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 6)
  frame.paused:Hide()
  frame.resume = th.Button(frame, "Resume", 56, 18, function()
    if frame.resume.kind == "clock" then ns.Do.resumeClock() else ns.Do.resume() end
  end)
  frame.resume:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 3)
  frame.resume:Hide()
  th.Tooltip(frame.resume, function()
    if frame.resume.kind == "clock" then return { "Resume", "Restart the seated clock where it stopped." } end
    return { "Resume", "Turn reminders back on now." }
  end)

  frame.collapse = th.Button(frame, "-", 18, 18, function()
    ns.Do.setSetting("totem.collapsed", not ns.db.settings.totem.collapsed)
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

  frame.seat:EnableMouse(true)
  th.Tooltip(frame.seat, function()
    if not (ns.db and ns.ready) then return nil end
    local st = ns.Scheduler.status(ns.db, ns.now(), ns.ctx)
    local s = ns.db.settings
    local lines = { "Seated clock",
      ("%s of sitting. A Walkabout comes due at %d min."):format(U.fmtClock(st.seated), s.walk.every) }
    if st.rooted > 0 then
      lines[#lines + 1] = ("Rooted x%d: your Walkabout grows by a minute every 15 min overdue (max %d min). Never owed.")
        :format(st.rooted, s.walk.max)
    end
    if st.paused then lines[#lines + 1] = "Paused while you're up." end
    return lines
  end)
  frame.rage:EnableMouse(true)
  th.Tooltip(frame.rage, function()
    if not (ns.db and ns.ready) then return nil end
    local st = ns.Scheduler.status(ns.db, ns.now(), ns.ctx)
    local s = ns.db.settings
    local lines = { "Rage",
      ("Fills from play (+100 per %d min) and from quests, dings, deaths, bosses, new zones and Hearthstone. At 100 you earn a Feat of Strength, at most one every %d min.")
        :format(s.rage.full, s.rage.cd) }
    if s.rage.bank then
      lines[#lines + 1] = "Rage over 100 is banked up to 200; at 200 your next Feat is a Double Feat."
    end
    if st.rage >= 100 and st.featCooldown > 0 then
      lines[#lines + 1] = "Next Feat in " .. U.fmtDuration(st.featCooldown)
    end
    return lines
  end)
  th.Tooltip(frame.rep, function()
    local _, _, total = repProgress()
    return { "Bloodhoof Athletic Club", total }
  end)

  applyPosition()

  -- throttled clock updates
  frame:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc >= 1 then
      acc = 0
      if ns.ready and ns.db and ns.Scheduler.snoozed(ns.db, ns.now(), ns.ctx or {}) ~= snoozedNow then
        if snoozedNow then
          ns.guard(ns.Do.tick) -- a snooze ended: run one scheduler tick so the reminder shows as the rows reappear
          ns.guard(Tm.Refresh, Tm)
        else
          ns.guard(Tm.Refresh, Tm) -- a snooze began
        end
      elseif ns.ready and ns.db and ((holdText() ~= nil) ~= holdReserved or (snoozeText() ~= nil) ~= snoozeReserved
          or (pauseInfo() ~= nil) ~= pauseReserved) then
        ns.guard(Tm.Refresh, Tm) -- reminders went on hold or came off hold
      end
      if frame:IsShown() then Tm:UpdateHeader() end
    end
  end)
  frame:SetScript("OnShow", function() Tm:UpdateHeader() end)
  self:Refresh()
end
