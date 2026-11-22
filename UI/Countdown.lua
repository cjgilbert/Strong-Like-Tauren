local ADDON, ns = ...
local C, U = ns.C, ns.U

-- Compact timer for timed slots (planks, walks). Pause / Stop (logs what you did) / Done.
ns.UI = ns.UI or {}
local Cd = {}
ns.UI.Countdown = Cd

local frame
local st = { active = false }

local function findSlot(itemId, idx)
  if not (ns.db and ns.db.queue) then return end
  local it = ns.Queue.byId(ns.db.queue, itemId)
  local sl = it and it.slots[idx]
  if sl and not sl.o then return it, sl end
end

local function finishAndClose(amount)
  local id, idx = st.itemId, st.idx
  Cd:Stop()
  ns.Do.complete(id, idx, amount)
end

local function update()
  if not st.active then return end
  local remaining = st.total - st.elapsed
  frame.time:SetText(U.fmtClock(math.max(0, math.ceil(remaining))))
  frame.bar:SetValue(math.min(1, st.elapsed / math.max(1, st.total)))
end

local function onUpdate(_, el)
  if not st.active then return end
  if not findSlot(st.itemId, st.idx) then Cd:Stop() return end -- resolved elsewhere
  if st.paused then return end
  st.elapsed = st.elapsed + el
  local left = math.ceil(st.total - st.elapsed)
  if left <= 3 and left > 0 and left ~= st.lastTick then
    st.lastTick = left
    ns.sound("tick")
  end
  if st.elapsed >= st.total then
    ns.sound("finish")
    finishAndClose(nil)
    return
  end
  update()
end

local function build()
  local th = ns.UI.Theme
  frame = th.Panel(UIParent, "StrongLikeTaurenCountdown", 230, 112)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:Hide()

  frame.title = th.Text(frame, "GameFontNormal", "", th.C.gold)
  frame.title:SetPoint("TOP", 0, -8)
  frame.title:SetWidth(210)
  frame.title:SetJustifyH("CENTER")
  frame.title:SetWordWrap(false)

  frame.time = th.Text(frame, "GameFontNormalLarge", "0:00", th.C.text)
  frame.time:SetPoint("TOP", 0, -26)
  frame.time:SetJustifyH("CENTER")
  local font, _, flags = frame.time:GetFont()
  if font then pcall(frame.time.SetFont, frame.time, font, 30, flags) end

  frame.bar = th.Bar(frame, 206, 10, th.C.green)
  frame.bar:SetPoint("TOP", 0, -64)

  frame.pause = th.Button(frame, "Pause", 64, 22, function()
    st.paused = not st.paused
    frame.pause:SetText(st.paused and "Resume" or "Pause")
  end)
  frame.pause:SetPoint("BOTTOMLEFT", 10, 8)
  frame.stop = th.Button(frame, "Stop", 64, 22, function()
    if not st.active then return end
    local done = math.floor(st.elapsed)
    if done >= 1 then finishAndClose(done) else Cd:Stop() end
  end)
  frame.stop:SetPoint("BOTTOM", 0, 8)
  frame.done = th.Button(frame, "Done", 64, 22, function()
    if st.active then finishAndClose(nil) end
  end)
  frame.done:SetPoint("BOTTOMRIGHT", -10, 8)
  th.Tooltip(frame.stop, { "Stop", "Logs the time you actually did." })
  frame:SetScript("OnUpdate", onUpdate)
end

function Cd:Start(itemId, idx)
  if not (ns.db and ns.env) then return end
  local it, sl = findSlot(itemId, idx)
  if not sl then return end
  if not frame then build() end
  local def = ns.env.byId[sl.x]
  st = { active = true, itemId = itemId, idx = idx, total = math.max(1, sl.a), elapsed = 0, paused = false }
  frame.title:SetText(def and ((def.pun and def.pun ~= def.name) and def.pun or def.name) or sl.x)
  frame.pause:SetText("Pause")
  frame:ClearAllPoints()
  local anchor = ns.UI.Totem and ns.UI.Totem.frame
  if anchor and anchor:IsShown() then
    frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
  update()
  frame:Show()
end

function Cd:Stop()
  st = { active = false }
  if frame then frame:Hide() end
end

function Cd:IsActive()
  return st.active
end
