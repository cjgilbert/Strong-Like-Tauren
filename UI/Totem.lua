local ADDON, ns = ...
local C, U = ns.C, ns.U

-- The Totem: always-on tracker with the seated clock, Rage bar and the pending Walkabout / Feat slots.
ns.UI = ns.UI or {}
local Tm = {}
ns.UI.Totem = Tm
local T -- Theme, resolved lazily so load order inside UI never matters

local WIDTH, HEADER_H, ROW_H, MAX_ROWS = 300, 56, 52, 6
local rows = {}
local frame, snoozeMenu
local hidden = false
local dirty = false
local entries = {}
local acc = 0

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
  r.name:SetPoint("RIGHT", r, "RIGHT", -52, 0)
  r.name:SetHeight(14)
  r.name:SetWordWrap(false)
  r.kind = th.Text(r, "GameFontNormalSmall", "", th.C.dim)
  r.kind:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
  r.amount = th.Text(r, "GameFontNormal", "", th.C.gold)
  r.amount:SetPoint("TOPRIGHT", r, "TOPRIGHT", -5, -5)
  r.amount:SetJustifyH("RIGHT")

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
    local lines = { (d.pun and d.pun ~= d.name) and (d.pun .. " - " .. d.name) or d.name }
    if d.desc then lines[#lines + 1] = d.desc end
    if r.slot and r.slot.why then lines[#lines + 1] = r.slot.why end
    return lines
  end)
  r:Hide()
  return r
end

local function amountText(def, slot)
  if def and def.kind == "s" or slot.walk then return U.fmtClock(slot.a) end
  return "x" .. tostring(slot.a)
end

local function layoutRow(r, i, e)
  local th = theme()
  r.itemId, r.idx, r.slot = e.item.id, e.idx, e.slot
  local def = ns.env and ns.env.byId[e.slot.x]
  r.def = def
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -HEADER_H - (i - 1) * ROW_H)
  r.icon:SetTexture(def and def.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  local name = def and ((def.pun and def.pun ~= def.name) and (def.pun .. " - " .. def.name) or def.name) or e.slot.x
  r.name:SetText(name)
  r.kind:SetText(e.item.k == "W" and "Walkabout" or "Feat of Strength")
  r.amount:SetText(amountText(def, e.slot))
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
  if not nxt then return 1, cur.name end
  return (rep - cur.min) / math.max(1, nxt.min - cur.min), cur.name
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
  frame.seat:SetBarColor(frac < 0.75 and th.C.green or (frac < 1 and th.C.amber or th.C.red))
  local txt = U.fmtClock(seated)
  if ns.ctx and ns.ctx.away then txt = txt .. " (away)" end
  if st.rooted > 0 and seated >= every then txt = ("Rooted x%d   %s"):format(st.rooted, txt) else txt = "Seated " .. txt end
  frame.seat.text:SetText(txt)

  frame.rage:SetValue(math.min(1, st.rage / 100))
  local rtxt
  if st.restDay then rtxt = "Rest day"
  elseif st.rage >= 100 and st.featCooldown > 0 then rtxt = "Feat in " .. U.fmtDuration(st.featCooldown)
  else rtxt = "Rage " .. math.floor(st.rage) end
  frame.rage.text:SetText(rtxt)

  local p, standing = repProgress()
  frame.rep:SetValue(p)
  if (ns.vigorUntil or 0) > t then
    frame.rep:SetBarColor(th.C.green)
    frame.rep.text:SetText("Earthmother's Vigor")
  else
    frame.rep:SetBarColor(th.C.gold)
    frame.rep.text:SetText(standing)
  end
end

-- Refresh -------------------------------------------------------------------------------------------------------------------------
local function collect()
  entries = {}
  if not (ns.db and ns.db.queue) then return end
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
  if InCombatLockdown and InCombatLockdown() then
    dirty = true
    return
  end
  dirty = false
  local collapsed = s.totem.collapsed
  frame.collapse:SetText(collapsed and "+" or "-")
  for i = 1, MAX_ROWS do
    local r = rows[i]
    if not r then r = buildRow(i); rows[i] = r end
    if not collapsed and entries[i] then layoutRow(r, i, entries[i]) else r:Hide() r.itemId = nil end
  end
  local n = collapsed and 0 or #entries
  frame:SetHeight(HEADER_H + n * ROW_H + (n > 0 and 4 or 0))
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

  frame.seat = th.Bar(frame, WIDTH - 46 - 30, 14, th.C.green)
  frame.seat:SetPoint("TOPLEFT", 48, -8)
  frame.rage = th.Bar(frame, WIDTH - 46 - 30, 12, th.C.rage)
  frame.rage:SetPoint("TOPLEFT", 48, -24)
  frame.rep = th.Bar(frame, WIDTH - 46 - 30, 12, th.C.gold)
  frame.rep:SetPoint("TOPLEFT", 48, -38)

  frame.collapse = th.Button(frame, "-", 18, 18, function()
    ns.Do.setSetting("totem.collapsed", not ns.db.settings.totem.collapsed)
  end)
  frame.collapse:SetPoint("TOPRIGHT", -6, -7)
  th.Tooltip(frame.collapse, { "Collapse / expand" })

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
