local ADDON, ns = ...
local C = ns.C

-- Palette (from the logo) and small widget builders. No Ace, no UIDropDownMenu.
ns.UI = ns.UI or {}
local T = {}
ns.UI.Theme = T

T.C = {
  bg     = { 0.16, 0.10, 0.06, 0.96 },
  bg2    = { 0.22, 0.14, 0.08, 1 },
  border = { 0.30, 0.20, 0.10, 1 },
  gold   = { 0.83, 0.66, 0.32 },
  text   = { 0.95, 0.90, 0.80 },
  dim    = { 0.70, 0.64, 0.52 },
  green  = { 0.42, 0.62, 0.30 },
  amber  = { 0.93, 0.66, 0.20 },
  red    = { 0.80, 0.25, 0.18 },
  rage   = { 0.75, 0.12, 0.10 },
}
local P = T.C
local WHITE = "Interface\\Buttons\\WHITE8X8"
T.WHITE = WHITE

local BACKDROP = {
  bgFile = WHITE,
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = false, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- CreateFrame with an optional template; falls back to a plain frame when the template is missing.
local function create(kind, name, parent, template)
  if template then
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f, true end
  end
  return CreateFrame(kind, name, parent), false
end
T.create = create

local function applyBackdrop(f, r, g, b, a)
  if f.SetBackdrop then
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(r, g, b, 0)
    f:SetBackdropBorderColor(unpack(P.border))
  end
end

-- Solid texture filling a frame (Forever's stock backdrop is see-through, so panels paint their own).
function T.solid(frame, color, layer, sub)
  local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -8)
  tex:SetTexture(WHITE)
  tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
  tex:SetAllPoints(frame)
  return tex
end

function T.Panel(parent, name, w, h)
  local f = create("Frame", name, parent or UIParent, "BackdropTemplate")
  if w and h then f:SetSize(w, h) end
  f.bgTex = T.solid(f, P.bg, "BACKGROUND", -8)
  applyBackdrop(f, 0, 0, 0, 0)
  return f
end

function T.Text(parent, font, text, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetJustifyH("LEFT")
  local c = color or P.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  if text then fs:SetText(text) end
  return fs
end

function T.Header(parent, text)
  local fs = T.Text(parent, "GameFontNormalLarge", text, P.gold)
  return fs
end

local function setupClicks(btn, onClick)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(self, mouse)
    if onClick then onClick(self, mouse) end
  end)
end

function T.Button(parent, text, w, h, onClick)
  local b, templated = create("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 80, h or 22)
  if templated then
    b:SetText(text or "")
  else
    T.solid(b, P.bg2, "BACKGROUND", -7)
    local fs = T.Text(b, "GameFontNormalSmall", text, P.gold)
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    b.label = fs
    b:SetScript("OnEnter", function(self) if self.label then self.label:SetTextColor(1, 1, 1) end end)
    b:SetScript("OnLeave", function(self) if self.label then self.label:SetTextColor(unpack(P.gold)) end end)
    b.SetText = function(self, t) self.label:SetText(t) end
  end
  setupClicks(b, onClick)
  return b
end

-- Small top-right close "X" (Blizzard's close button when available, else a plain "x" button).
function T.CloseButton(parent, onClick)
  local b, templated = create("Button", nil, parent, "UIPanelCloseButton")
  if templated then
    b:SetSize(22, 22)
    setupClicks(b, onClick)
  else
    b = T.Button(parent, "x", 18, 18, onClick)
  end
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -3)
  return b
end

-- Shows a tooltip on owner. lines = { "Title", "text", { "left", "right" } } or a function returning that table.
function T.Tooltip(owner, lines)
  owner:HookScript("OnEnter", function(self)
    local l = lines
    if type(l) == "function" then l = l(self) end
    if not l or #l == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for i, line in ipairs(l) do
      if type(line) == "table" then
        GameTooltip:AddDoubleLine(line[1], line[2] or "", 1, 1, 1, 1, 1, 1)
      elseif i == 1 then
        GameTooltip:AddLine(line, P.gold[1], P.gold[2], P.gold[3], true)
      else
        GameTooltip:AddLine(line, P.text[1], P.text[2], P.text[3], true)
      end
    end
    GameTooltip:Show()
  end)
  owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function T.IconButton(parent, texture, size, tip, onClick)
  local b = create("Button", nil, parent)
  b:SetSize(size or 20, size or 20)
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  tex:SetTexture(texture)
  b.icon = tex
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(WHITE)
  hl:SetVertexColor(1, 1, 1, 0.18)
  setupClicks(b, onClick)
  if tip then T.Tooltip(b, type(tip) == "table" and tip or { tip }) end
  return b
end

function T.Check(parent, label, get, set)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(260, 24)
  local cb = create("CheckButton", nil, holder, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("LEFT", 0, 0)
  local fs = T.Text(holder, "GameFontHighlight", label, P.text)
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  holder.label, holder.check = fs, cb
  cb:SetScript("OnClick", function(self)
    if set then set(self:GetChecked() and true or false) end
    if ns.sound then ns.sound("click") end
  end)
  function holder:Refresh()
    cb:SetChecked(get and get() and true or false)
  end
  function holder:SetEnabled(on)
    if cb.SetEnabled then cb:SetEnabled(on) end
    fs:SetAlpha(on and 1 or 0.5)
  end
  holder:Refresh()
  return holder
end

function T.Stepper(parent, label, get, set, min, max, step, fmt)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(300, 24)
  local fs = T.Text(holder, "GameFontHighlight", label, P.text)
  fs:SetPoint("LEFT", 0, 0)
  fs:SetWidth(150)
  local plus = T.Button(holder, "+", 22, 22)
  plus:SetPoint("RIGHT", 0, 0)
  local val = T.Text(holder, "GameFontNormal", "", P.gold)
  val:SetPoint("RIGHT", plus, "LEFT", -4, 0)
  val:SetWidth(60)
  val:SetJustifyH("CENTER")
  local minus = T.Button(holder, "-", 22, 22)
  minus:SetPoint("RIGHT", val, "LEFT", -4, 0)
  holder.label, holder.value = fs, val
  step = step or 1
  local function show()
    local v = get and get()
    if v == nil then val:SetText("?") return end
    val:SetText(fmt and fmt(v) or tostring(v))
  end
  local function bump(dir)
    local v = (get and get()) or min or 0
    v = v + dir * step
    if min and v < min then v = min end
    if max and v > max then v = max end
    v = math.floor(v * 1000 + 0.5) / 1000
    if set then set(v) end
    show()
  end
  minus:SetScript("OnClick", function() bump(-1) end)
  plus:SetScript("OnClick", function() bump(1) end)
  function holder:Refresh() show() end
  show()
  return holder
end

-- options: { "a", "b" } or { { value, label }, ... } or { { value = , label = }, ... }.
function T.Segmented(parent, options, get, set)
  local holder = CreateFrame("Frame", nil, parent)
  local btns, x = {}, 0
  for i, o in ipairs(options) do
    local value, label
    if type(o) == "table" then
      value = o.value or o[1]
      label = o.label or o[2] or tostring(value)
    else
      value, label = o, tostring(o)
    end
    local b = T.Button(holder, label, math.max(50, #label * 8 + 16), 22)
    b:SetPoint("LEFT", x, 0)
    x = x + b:GetWidth() + 2
    b.value = value
    b:SetScript("OnClick", function()
      if set then set(value) end
      holder:Refresh()
    end)
    btns[i] = b
  end
  holder:SetSize(math.max(x, 1), 22)
  function holder:Refresh()
    local cur = get and get()
    for _, b in ipairs(btns) do
      local on = (b.value == cur)
      if b.label then
        b.label:SetTextColor(unpack(on and P.text or P.gold))
      else
        local fs = b.GetFontString and b:GetFontString()
        if fs then fs:SetTextColor(unpack(on and { 1, 1, 1 } or P.gold)) end
      end
      if b.SetAlpha then b:SetAlpha(on and 1 or 0.65) end
    end
  end
  holder.buttons = btns
  holder:Refresh()
  return holder
end

function T.Bar(parent, w, h, color)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetSize(w or 100, h or 12)
  bar:SetStatusBarTexture(WHITE)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  local c = color or P.green
  bar:SetStatusBarColor(c[1], c[2], c[3], 1)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  bar.bg:SetTexture(WHITE)
  bar.bg:SetVertexColor(0.05, 0.03, 0.02, 0.9)
  bar.text = T.Text(bar, "GameFontNormalSmall", "", P.text)
  bar.text:SetPoint("CENTER", 0, 0)
  bar.text:SetJustifyH("CENTER")
  function bar:SetBarColor(col) self:SetStatusBarColor(col[1], col[2], col[3], 1) end
  return bar
end

-- Returns scroll, content (content is the scroll child; width = w - 26).
function T.Scroll(parent, w, h)
  local scroll, templated = create("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetSize(w, h)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(math.max(1, w - 26), 10)
  scroll:SetScrollChild(content)
  if not templated then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local cur = self:GetVerticalScroll()
      local maxv = math.max(0, content:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.max(0, math.min(maxv, cur - delta * 30)))
    end)
  end
  return scroll, content
end

-- Single-line (InputBoxTemplate) or multi-line edit box. Returns the EditBox.
function T.EditBox(parent, w, h, multiline)
  local eb
  if multiline then
    eb = CreateFrame("EditBox", nil, parent)
    eb:SetMultiLine(true)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetSize(w, h)
    T.solid(eb, { 0.08, 0.05, 0.03, 0.95 }, "BACKGROUND", -7)
  else
    local templated
    eb, templated = create("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, h or 22)
    if not templated then
      eb:SetFontObject("GameFontHighlight")
      eb:SetTextInsets(4, 4, 2, 2)
      T.solid(eb, { 0.08, 0.05, 0.03, 0.95 }, "BACKGROUND", -7)
    end
    eb:SetAutoFocus(false)
    eb:SetMultiLine(false)
  end
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return eb
end
