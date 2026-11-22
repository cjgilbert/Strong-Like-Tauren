local ADDON, ns = ...
local L = ns.L

-- Main window plus "Kit": small self-contained widget helpers shared by the tab files (Kit is loaded here first).
-- The Kit is deliberately independent of UI\Theme.lua so the tabs keep working whatever Theme exposes.
ns.UI = ns.UI or {}
local UI = ns.UI
UI.Tabs = UI.Tabs or {}
local Kit = {}
UI.Kit = Kit

local WHITE = "Interface\\Buttons\\WHITE8X8"
Kit.WHITE = WHITE
Kit.COL = {
  bg = { 0.10, 0.07, 0.05, 1 }, panel = { 0.17, 0.12, 0.08, 1 }, row = { 0.22, 0.16, 0.11, 1 },
  border = { 0.55, 0.42, 0.22, 1 }, gold = { 0.83, 0.66, 0.32 }, text = { 0.96, 0.91, 0.80 },
  dim = { 0.68, 0.62, 0.52 }, green = { 0.45, 0.75, 0.35 }, red = { 0.86, 0.32, 0.26 },
  amber = { 0.95, 0.70, 0.20 }, rage = { 0.80, 0.15, 0.10 },
}
local COL = Kit.COL

local function color(fs, c) if c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end end

function Kit.report(err)
  if ns.DB and ns.DB.logError and ns.db then pcall(ns.DB.logError, ns.db, ns.now and ns.now() or 0, tostring(err)) end
end

function Kit.say(msg)
  if ns.say then ns.say(msg) else print("Strong Like Tauren: " .. tostring(msg)) end
end

function Kit.today()
  return ns.U.dayKey(ns.now(), ns.db.settings.dayStart)
end

-- Solid panel: opaque background texture under an optional border backdrop.
function Kit.panel(parent, name, w, h, bg)
  local ok, f = pcall(CreateFrame, "Frame", name, parent, "BackdropTemplate")
  if not ok or not f then f = CreateFrame("Frame", name, parent) end
  f:SetSize(w, h)
  local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  t:SetAllPoints()
  local c = bg or COL.bg
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  f.bgTex = t
  if f.SetBackdrop then
    pcall(f.SetBackdrop, f, { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    pcall(f.SetBackdropBorderColor, f, COL.border[1], COL.border[2], COL.border[3], 1)
  end
  return f
end

function Kit.text(parent, str, font, c, w, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  if w then fs:SetWidth(w) end
  fs:SetText(str or "")
  color(fs, c or COL.text)
  return fs
end

function Kit.tip(owner, text)
  owner:HookScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(text, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  owner:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

function Kit.button(parent, text, w, h, onClick)
  local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if not ok or not b then
    b = CreateFrame("Button", nil, parent)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(COL.row[1], COL.row[2], COL.row[3], 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetAllPoints()
    b:SetFontString(fs)
  end
  b:SetSize(w or 100, h or 24)
  b:SetText(text or "")
  if onClick then b:SetScript("OnClick", function(self, ...) onClick(self, ...) end) end
  return b
end

-- Checkbox with a label. get() -> bool, set(bool). Returns a frame with :Refresh() and :SetEnabled(bool).
function Kit.check(parent, label, get, set, w)
  w = w or 300
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 24)
  local ok, cb = pcall(CreateFrame, "CheckButton", nil, f, "UICheckButtonTemplate")
  if not ok or not cb then
    cb = CreateFrame("CheckButton", nil, f)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  end
  cb:SetSize(24, 24)
  cb:SetPoint("LEFT", f, "LEFT", 0, 0)
  local fs = Kit.text(f, label, "GameFontHighlight", COL.text, w - 30)
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  fs:SetWordWrap(false)
  f.label, f.cb = fs, cb
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    f:Refresh()
  end)
  function f:Refresh() cb:SetChecked(get() and true or false) end
  function f:SetEnabled(en)
    if cb.SetEnabled then cb:SetEnabled(en) end
    fs:SetAlpha(en and 1 or 0.5)
  end
  f:Refresh()
  return f
end

-- Numeric stepper: label, [-] value [+]. Returns a frame with :Refresh() and :SetEnabled(bool).
function Kit.stepper(parent, label, get, set, min, max, step, fmt, w)
  w = w or 360
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 24)
  local fs = Kit.text(f, label, "GameFontHighlight", COL.text, w - 140)
  fs:SetPoint("LEFT", f, "LEFT", 2, 0)
  fs:SetWordWrap(false)
  local minus = Kit.button(f, "-", 24, 22)
  minus:SetPoint("RIGHT", f, "RIGHT", -86, 0)
  local val = Kit.text(f, "", "GameFontNormal", COL.gold, 60, "CENTER")
  val:SetPoint("LEFT", minus, "RIGHT", 0, 0)
  local plus = Kit.button(f, "+", 24, 22)
  plus:SetPoint("LEFT", val, "RIGHT", 0, 0)
  f.label, f.value = fs, val
  local function bump(dir)
    local v = (tonumber(get()) or min) + dir * step
    v = math.max(min, math.min(max, v))
    v = math.floor(v * 1000 + 0.5) / 1000
    set(v)
    f:Refresh()
  end
  minus:SetScript("OnClick", function() bump(-1) end)
  plus:SetScript("OnClick", function() bump(1) end)
  function f:Refresh()
    local v = get()
    val:SetText(fmt and fmt(v) or tostring(v))
  end
  function f:SetEnabled(en)
    if minus.SetEnabled then minus:SetEnabled(en); plus:SetEnabled(en) end
    val:SetAlpha(en and 1 or 0.5)
    fs:SetAlpha(en and 1 or 0.5)
  end
  f:Refresh()
  return f
end

-- Segmented control. options = { {key, label}, ... }. Selected = "[label]" in gold (text, not colour alone).
function Kit.segmented(parent, options, get, set, w)
  w = w or 400
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 26)
  local bw = math.floor(w / #options)
  local btns = {}
  for i, o in ipairs(options) do
    local b = Kit.button(f, o[2], bw - 2, 24, function()
      set(o[1])
      f:Refresh()
    end)
    b:SetPoint("LEFT", f, "LEFT", (i - 1) * bw, 0)
    btns[i] = b
  end
  function f:Refresh()
    local cur = get()
    for i, o in ipairs(options) do
      local sel = (cur == o[1])
      btns[i]:SetText(sel and ("[" .. o[2] .. "]") or o[2])
      local fs = btns[i]:GetFontString()
      if fs then color(fs, sel and COL.gold or COL.text) end
    end
  end
  f:Refresh()
  return f
end

-- Progress bar with centred text. :Set(fraction, text, colorTable)
function Kit.bar(parent, w, h, c)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.04, 0.03, 1)
  local sb = CreateFrame("StatusBar", nil, f)
  sb:SetPoint("TOPLEFT", 1, -1)
  sb:SetPoint("BOTTOMRIGHT", -1, 1)
  sb:SetStatusBarTexture(WHITE)
  sb:SetMinMaxValues(0, 1)
  sb:SetValue(0)
  local c0 = c or COL.green
  sb:SetStatusBarColor(c0[1], c0[2], c0[3])
  local fs = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER")
  f.sb, f.text = sb, fs
  function f:Set(frac, text, cc)
    sb:SetValue(math.max(0, math.min(1, frac or 0)))
    if cc then sb:SetStatusBarColor(cc[1], cc[2], cc[3]) end
    fs:SetText(text or "")
  end
  return f
end

-- Scroll area. Returns scroll, content (content width = w - 28). Call flow:finish() to set the content height.
function Kit.scroll(parent, w, h)
  local ok, s = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  if not ok or not s then
    s = CreateFrame("ScrollFrame", nil, parent)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, d)
      local cur = self:GetVerticalScroll()
      local max = math.max(0, (self:GetScrollChild() and self:GetScrollChild():GetHeight() or 0) - self:GetHeight())
      self:SetVerticalScroll(math.max(0, math.min(max, cur - d * 30)))
    end)
  end
  s:SetSize(w - 28, h)
  local c = CreateFrame("Frame", nil, s)
  c:SetSize(w - 28, 10)
  s:SetScrollChild(c)
  return s, c
end

-- Vertical layout helper for scroll contents.
function Kit.flow(content, width)
  local F = { content = content, width = width or content:GetWidth(), y = 0 }
  function F:add(obj, h, x)
    obj:ClearAllPoints()
    obj:SetPoint("TOPLEFT", content, "TOPLEFT", x or 0, -self.y)
    self.y = self.y + (h or obj:GetHeight()) + 4
    return obj
  end
  function F:space(n) self.y = self.y + (n or 8) end
  function F:header(text)
    self.y = self.y + 6
    local fs = Kit.text(content, text, "GameFontNormalLarge", COL.gold, self.width)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -self.y)
    self.y = self.y + 22
    return fs
  end
  function F:note(text, indent, font, c)
    indent = indent or 0
    local fs = Kit.text(content, text, font or "GameFontHighlightSmall", c or COL.dim, self.width - indent - 4)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -self.y)
    local h = math.max(12, fs:GetStringHeight() or 12)
    self.y = self.y + h + 6
    return fs
  end
  function F:finish() content:SetHeight(self.y + 10) end
  return F
end

-- Single-line edit box.
function Kit.edit(parent, w, h, numeric)
  local ok, e = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
  if not ok or not e then
    e = CreateFrame("EditBox", nil, parent)
    local bg = e:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(4, 4, 2, 2)
  end
  e:SetSize(w, h or 22)
  e:SetAutoFocus(false)
  if numeric then e:SetNumeric(true) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

-- Multi-line edit box inside a scroll frame. Returns holder, editbox.
function Kit.multiEdit(parent, w, h, readonly)
  local holder = Kit.panel(parent, nil, w, h, { 0.04, 0.03, 0.02, 1 })
  local s, c = Kit.scroll(holder, w - 8, h - 8)
  s:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -6)
  local e = CreateFrame("EditBox", nil, c)
  e:SetMultiLine(true)
  e:SetFontObject("ChatFontNormal")
  e:SetAutoFocus(false)
  e:SetWidth(w - 40)
  e:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
  e:SetTextInsets(2, 2, 2, 2)
  e:SetMaxLetters(0)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnTextChanged", function(self, user)
    local hgt = math.max(h - 12, (self:GetHeight() or 0) + 8)
    c:SetHeight(hgt)
    if readonly and user and self.lockedText then
      self:SetText(self.lockedText)
      self:HighlightText()
    elseif self.onChange then
      self.onChange(self, user)
    end
  end)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function() e:SetFocus() end)
  function e:SetLocked(text)
    self.lockedText = text
    self:SetText(text)
  end
  return holder, e
end

-- Yes/No confirmation (shared frame).
local confirmFrame
function Kit.confirm(text, onYes)
  if not confirmFrame then
    local f = Kit.panel(UIParent, "StrongLikeTaurenConfirm", 340, 130, COL.panel)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f.msg = Kit.text(f, "", "GameFontHighlight", COL.text, 300, "CENTER")
    f.msg:SetPoint("TOP", f, "TOP", 0, -18)
    f.yes = Kit.button(f, L["Yes"], 100, 24)
    f.yes:SetPoint("BOTTOMLEFT", f, "BOTTOM", -108, 14)
    f.no = Kit.button(f, L["Cancel"], 100, 24, function() f:Hide() end)
    f.no:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 108, 14)
    f:Hide()
    confirmFrame = f
  end
  local f = confirmFrame
  f.msg:SetText(text)
  f.yes:SetScript("OnClick", function()
    f:Hide()
    local ok, err = pcall(onYes)
    if not ok then Kit.report(err) end
  end)
  f:Show()
end

-- "12 reps" / "0:30"
function Kit.amountStr(def, amount, kind)
  local k = (def and def.kind) or kind or "r"
  if k == "s" then return ns.U.fmtClock(amount or 0) end
  return tostring(amount or 0) .. " " .. L["reps"]
end

----------------------------------------------------------------------------------------------------------------
-- Main window
----------------------------------------------------------------------------------------------------------------
local Main = {}
UI.Main = Main
Main.CW, Main.CH = 616, 418

local ORDER = { "today", "history", "exercises", "settings", "health" }
local TITLES = {
  today = L["Today"], history = L["History"], exercises = L["Exercises"], settings = L["Settings"], health = L["Health"],
}

local frame, content, tabBtns, frames, cur, lastTab = nil, nil, {}, {}, nil, "today"

local function refreshTab(key)
  local tab, tf = UI.Tabs[key], frames[key]
  if tab and tf and tab.refresh then
    local ok, err = pcall(tab.refresh, tf)
    if not ok then Kit.report(err) end
  end
end

local function selectTab(key)
  local tab = UI.Tabs[key]
  if not tab then return end
  if not frames[key] then
    local ok, tf = pcall(tab.build, content)
    if not ok or not tf then
      Kit.report(tf)
      return
    end
    tf:SetAllPoints(content)
    frames[key] = tf
  end
  for k, tf in pairs(frames) do tf:SetShown(k == key) end
  cur, lastTab = key, key
  if ns.db then ns.db.uiTab = key end
  for k, b in pairs(tabBtns) do
    local sel = (k == key)
    b:SetText(sel and ("[" .. TITLES[k] .. "]") or TITLES[k])
    local fs = b:GetFontString()
    if fs then color(fs, sel and COL.gold or COL.text) end
  end
  refreshTab(key)
end

local function build()
  frame = Kit.panel(UIParent, "StrongLikeTaurenMain", 640, 520)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  local logo = frame:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(ns.C.LOGO)
  logo:SetSize(44, 44)
  logo:SetPoint("TOPLEFT", 12, -8)
  local title = Kit.text(frame, "Strong Like Tauren", "GameFontNormalHuge", COL.gold)
  title:SetPoint("LEFT", logo, "RIGHT", 8, 4)
  local ver = Kit.text(frame, "v" .. ns.C.VERSION .. "  -  " .. L["Zug zug. Stand up."], "GameFontHighlightSmall", COL.dim)
  ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)

  local ok, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
  if not ok or not close then
    close = Kit.button(frame, "X", 24, 24)
  end
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() frame:Hide() end)

  local x = 12
  for _, key in ipairs(ORDER) do
    local b = Kit.button(frame, TITLES[key], 112, 26, function() selectTab(key) end)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -58)
    x = x + 116
    tabBtns[key] = b
  end

  content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -90)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
  content:SetSize(Main.CW, Main.CH)

  tinsert(UISpecialFrames, "StrongLikeTaurenMain")
  local acc = 0
  frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    local tab = UI.Tabs[cur]
    if tab and tab.live then refreshTab(cur) end
  end)
  frame:SetScript("OnShow", function() if cur then refreshTab(cur) end end)
  frame:Hide()
end

function Main:Show(tab)
  if not frame then build() end
  frame:Show()
  local key = (tab and UI.Tabs[tab]) and tab or ((ns.db and ns.db.uiTab and UI.Tabs[ns.db.uiTab]) and ns.db.uiTab) or lastTab
  selectTab(key)
end

function Main:Hide()
  if frame then frame:Hide() end
end

function Main:IsShown()
  return frame and frame:IsShown() or false
end

function Main:Toggle(tab)
  if self:IsShown() and (tab == nil or tab == cur) then self:Hide() else self:Show(tab) end
end

function Main:Refresh()
  if not frame or not frame:IsShown() then return end
  refreshTab(cur)
end
