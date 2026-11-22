local ADDON, ns = ...
local C, U = ns.C, ns.U

-- Small non-modal prompts: away question, credit notice, early offer, partial amount, undo toast.
ns.UI = ns.UI or {}
local Pr = {}
ns.UI.Prompts = Pr

local WIDTH = 320
local slots = {} -- one frame per prompt channel

-- A prompt frame with text and two buttons; closes itself after `timeout` seconds (calling onTimeout).
local function getPrompt(channel, y)
  local p = slots[channel]
  if p then return p end
  local th = ns.UI.Theme
  p = th.Panel(UIParent, "StrongLikeTaurenPrompt" .. channel, WIDTH, 84)
  p:SetFrameStrata("HIGH")
  p:SetClampedToScreen(true)
  p:SetPoint("TOP", UIParent, "TOP", 0, y)
  p:Hide()
  p.text = th.Text(p, "GameFontHighlight", "", th.C.text)
  p.text:SetPoint("TOPLEFT", 12, -10)
  p.text:SetWidth(WIDTH - 24)
  p.text:SetHeight(34)
  p.text:SetJustifyV("TOP")
  p.b1 = th.Button(p, "", 120, 22, function() p:Choose(1) end)
  p.b1:SetPoint("BOTTOMLEFT", 12, 10)
  p.b2 = th.Button(p, "", 120, 22, function() p:Choose(2) end)
  p.b2:SetPoint("BOTTOMRIGHT", -12, 10)
  function p:Choose(n)
    local fn = (n == 1) and self.fn1 or self.fn2
    self.fn1, self.fn2, self.onTimeout, self.expires = nil, nil, nil, nil
    self:Hide()
    if fn then ns.guard(fn) end
  end
  function p:Open(text, l1, f1, l2, f2, timeout, onTimeout)
    self.text:SetText(text or "")
    self.b1:SetText(l1 or "")
    self.b2:SetText(l2 or "")
    self.b1:SetShown(l1 ~= nil)
    self.b2:SetShown(l2 ~= nil)
    if l1 and not l2 then
      self.b1:ClearAllPoints()
      self.b1:SetPoint("BOTTOM", 0, 10)
    else
      self.b1:ClearAllPoints()
      self.b1:SetPoint("BOTTOMLEFT", 12, 10)
    end
    self.fn1, self.fn2, self.onTimeout = f1, f2, onTimeout
    self.expires = timeout and (GetTime() + timeout) or nil
    self:Show()
  end
  p:SetScript("OnUpdate", function(self)
    if self.expires and GetTime() >= self.expires then
      local fn = self.onTimeout
      self.fn1, self.fn2, self.onTimeout, self.expires = nil, nil, nil, nil
      self:Hide()
      if fn then ns.guard(fn) end
    end
  end)
  slots[channel] = p
  return p
end

function Pr:AskAway(dur)
  local p = getPrompt("Ask", -300)
  p:Open(ns.quip("awayAsk"),
    "Yes", function() ns.Do.answerAway(true) end,
    "No", function() ns.Do.answerAway(false) end,
    60, function() ns.Do.answerAway(false) end)
end

function Pr:Credit(action)
  local p = getPrompt("Credit", -300)
  p:Open(ns.quip("awayCredit"),
    "I was sitting", function() ns.Do.undoCredit(action.row, action.prevAcc) end,
    "OK", nil, 30)
end

function Pr:Offer(moment)
  local p = getPrompt("Offer", -300)
  local text = (moment == "taxi" or moment == "rest" or moment == "leave") and ns.quip(moment) or ns.quip("early")
  p:Open(text,
    "Break now", function() ns.Do.forceWalk() end,
    "Not now", nil, 30)
end

function Pr:Undo(action)
  if not (action and ns.db and ns.env) then return end
  local _, row = ns.History.find(ns.db, action.row)
  if not row then return end
  local def = ns.env.byId[row.x]
  local name = def and (def.pun or def.name) or row.x
  local amount = ns.Library.amountText(def, row.a)
  local p = getPrompt("Undo", -372)
  p:Open(("Logged: %s %s"):format(amount, name),
    "Undo", function() ns.Do.undo(action) end,
    nil, nil, 10)
end

-- Partial amount ----------------------------------------------------------------------------------------------------------------
local partial

function Pr:Partial(itemId, idx)
  if not (ns.db and ns.env) then return end
  local it = ns.Queue.byId(ns.db.queue, itemId)
  local sl = it and it.slots[idx]
  if not sl or sl.o then return end
  local th = ns.UI.Theme
  if not partial then
    partial = th.Panel(UIParent, "StrongLikeTaurenPartial", 260, 110)
    partial:SetFrameStrata("DIALOG")
    partial:SetClampedToScreen(true)
    partial:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    partial.text = th.Text(partial, "GameFontNormal", "", th.C.gold)
    partial.text:SetPoint("TOP", 0, -12)
    partial.text:SetWidth(240)
    partial.text:SetJustifyH("CENTER")
    partial.edit = th.EditBox(partial, 80, 22, false)
    partial.edit:SetPoint("TOP", 0, -38)
    partial.edit:SetNumeric(true)
    partial.edit:SetMaxLetters(5)
    partial.edit:SetJustifyH("CENTER")
    local function confirm()
      local n = tonumber(partial.edit:GetText())
      local id, i = partial.itemId, partial.idx
      partial:Hide()
      if n and n > 0 and id then ns.Do.complete(id, i, n) end
    end
    partial.edit:SetScript("OnEnterPressed", confirm)
    partial.edit:SetScript("OnEscapePressed", function() partial:Hide() end)
    partial.ok = th.Button(partial, "Log it", 100, 22, confirm)
    partial.ok:SetPoint("BOTTOMLEFT", 16, 12)
    partial.cancel = th.Button(partial, "Cancel", 100, 22, function() partial:Hide() end)
    partial.cancel:SetPoint("BOTTOMRIGHT", -16, 12)
    partial:Hide()
  end
  local def = ns.env.byId[sl.x]
  local timed = (def and def.kind == "s") or sl.walk
  partial.itemId, partial.idx = itemId, idx
  partial.text:SetText(timed and "How many seconds did you do?" or "How many did you do?")
  partial.edit:SetText(tostring(math.max(1, math.floor(sl.a / 2))))
  partial:Show()
  partial.edit:SetFocus()
  partial.edit:HighlightText()
end
