-- A permissive fake of the WoW API, just enough to LOAD the addon offline (see tools/smoke.lua).
local stub = { frames = {}, timers = {}, unknown = {}, chat = {}, clock = 1000.0 }

local G = _G
G._G = G

-- Frames ---------------------------------------------------------------------------------------------------
local GETTERS = {
  GetWidth = 100, GetHeight = 20, GetLeft = 100, GetTop = 200, GetRight = 200, GetBottom = 180,
  GetScale = 1, GetEffectiveScale = 1, GetAlpha = 1, GetFrameLevel = 1, GetNumChildren = 0,
  GetNumRegions = 0, GetStringWidth = 50, GetStringHeight = 12, GetNumPoints = 0, GetVerticalScroll = 0,
  GetVerticalScrollRange = 0, GetHorizontalScroll = 0, GetHorizontalScrollRange = 0,
  GetNumLines = 0, GetNumber = 0, GetFrameStrata = "MEDIUM", GetDuration = 0,
  GetProgress = 0, GetOrder = 1, GetFont = "Fonts\\FRIZQT__.TTF",
}
local FALSES = { IsMouseOver = false, IsPlaying = false, GetChecked = false, HasFocus = false }
local TRUES = { IsEnabled = true, IsMovable = true, IsMouseEnabled = true }

local Frame = {}
local function mkframe(kind, name, parent)
  local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _events = {}, _scripts = {}, _shown = false },
    Frame)
  stub.frames[#stub.frames + 1] = f
  if name then G[name] = f end
  return f
end

local methods = {}
function methods.GetName(self) return self._name end
function methods.GetParent(self) return self._parent end
function methods.GetObjectType(self) return self._kind end
function methods.RegisterEvent(self, ev) self._events[ev] = true end
function methods.RegisterUnitEvent(self, ev) self._events[ev] = true end
function methods.RegisterAllEvents(self) self._all = true end
function methods.UnregisterEvent(self, ev) self._events[ev] = nil end
function methods.UnregisterAllEvents(self) self._events = {} end
function methods.IsEventRegistered(self, ev) return self._events[ev] and true or false end
function methods.SetScript(self, k, fn) self._scripts[k] = fn end
function methods.GetScript(self, k) return self._scripts[k] end
function methods.HookScript(self, k, fn)
  local old = self._scripts[k]
  self._scripts[k] = old and function(...) old(...) fn(...) end or fn
end
function methods.HasScript() return true end
function methods.Show(self) self._shown = true end
function methods.Hide(self) self._shown = false end
function methods.SetShown(self, v) self._shown = v and true or false end
function methods.IsShown(self) return self._shown end
function methods.IsVisible(self) return self._shown end
function methods.SetText(self, t) self._text = t end
-- Text metrics proportional to the text, so layouts that size themselves from the rendered text are testable.
function methods.SetWidth(self, w) self._w = w end
function methods.SetWordWrap(self, v) self._wrap = v end
function methods.SetHeight(self, h) self._h = h; self._heights = self._heights or {}; self._heights[#self._heights + 1] = h end
function methods.GetStringWidth(self) return #(self._text or "") * 6 end
function methods.GetStringHeight(self)
  if (self._text or "") == "" then return 0 end
  local n = 0
  for line in ((self._text or "") .. "\n"):gmatch("(.-)\n") do
    n = n + math.max(1, math.ceil(#line * 6 / (self._w or 1e9)))
  end
  return n * 12
end
function methods.GetText(self) return self._text or "" end
function methods.SetValue(self, v) self._value = v end
function methods.SetStatusBarColor(self, r, g, b) self._color = { r, g, b } end
function methods.GetValue(self) return self._value or 0 end
function methods.SetMinMaxValues(self, a, b) self._min, self._max = a, b end
function methods.GetMinMaxValues(self) return self._min or 0, self._max or 100 end
function methods.CreateTexture(self, name) return mkframe("Texture", name, self) end
function methods.CreateFontString(self, name) return mkframe("FontString", name, self) end
function methods.CreateAnimationGroup(self, name) return mkframe("AnimationGroup", name, self) end
function methods.CreateAnimation(self, kind, name) return mkframe("Animation", name, self) end
function methods.ClearAllPoints(self) self._points = {} return self end
function methods.SetPoint(self, ...)
  self._points = self._points or {}
  self._points[#self._points + 1] = { ... }
  return self
end
function methods.GetPoint() return "CENTER", G.UIParent, "CENTER", 0, 0 end
function methods.GetCenter() return 400, 300 end
function methods.GetScrollChild(self) self._sc = self._sc or mkframe("Frame", nil, self) return self._sc end
function methods.GetFontString(self) self._fs = self._fs or mkframe("FontString", nil, self) return self._fs end
function methods.GetNormalTexture(self) self._nt = self._nt or mkframe("Texture", nil, self) return self._nt end
function methods.GetThumbTexture(self) self._tt = self._tt or mkframe("Texture", nil, self) return self._tt end
function methods.GetStatusBarTexture(self) self._st = self._st or mkframe("Texture", nil, self) return self._st end
function methods.GetHighlightTexture(self) self._ht = self._ht or mkframe("Texture", nil, self) return self._ht end
function methods.GetPushedTexture(self) self._pt = self._pt or mkframe("Texture", nil, self) return self._pt end
function methods.GetCheckedTexture(self) self._ct = self._ct or mkframe("Texture", nil, self) return self._ct end
function methods.GetDisabledTexture(self) self._dt = self._dt or mkframe("Texture", nil, self) return self._dt end
function methods.GetRegions() return end
function methods.GetChildren() return end
function methods.GetNumLetters() return 0 end

Frame.__index = function(self, k)
  local m = methods[k]
  if m then return m end
  local g = GETTERS[k]
  if g ~= nil then return function() return g end end
  if FALSES[k] ~= nil then return function() return false end end
  if TRUES[k] ~= nil then return function() return true end end
  -- WoW methods are CamelCase; lowercase fields (frame.text, frame.cache) are the addon's own and stay nil.
  if type(k) == "string" and k:find("^%u") then
    return function(s) return s end
  end
end

function G.CreateFrame(kind, name, parent, template)
  local f = mkframe(kind or "Frame", name, parent)
  f._template = template
  return f
end

G.UIParent = mkframe("Frame", "UIParent")
G.UIParent._shown = true
G.Minimap = mkframe("Frame", "Minimap")
G.GameTooltip = mkframe("GameTooltip", "GameTooltip")
G.WorldFrame = mkframe("Frame", "WorldFrame")
G.DEFAULT_CHAT_FRAME = mkframe("Frame", "DEFAULT_CHAT_FRAME")
function G.DEFAULT_CHAT_FRAME:AddMessage(msg)
  stub.chat[#stub.chat + 1] = msg
  print("[chat] " .. tostring(msg))
end
for _, n in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontHighlight",
                     "GameFontHighlightSmall", "GameFontHighlightLarge", "GameFontDisable", "GameFontWhite",
                     "ChatFontNormal", "SystemFont_Small", "SystemFont_Med1", "SystemFont_Large", "Fancy16Font" }) do
  mkframe("Font", n)
end
G.BackdropTemplateMixin = {}

-- Time ------------------------------------------------------------------------------------------------------
local function timer(kind)
  return function(sec, fn)
    local t = { sec = sec, fn = fn, kind = kind }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled and true or false end
    stub.timers[#stub.timers + 1] = t
    return t
  end
end
G.C_Timer = { After = timer("after"), NewTicker = timer("ticker"), NewTimer = timer("timer") }
G.GetServerTime = function() return os.time() end
G.GetTime = function() return stub.clock end
G.GetBuildInfo = function() return "1.60.1", "71037", "Nov 2026", 16001 end
G.GetCursorPosition = function() return 500, 400 end
G.GetLocale = function() return "enUS" end

-- Unit / world ----------------------------------------------------------------------------------------------
G.UnitName = function() return "Bloodhoof Runner" end
G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
G.UnitGUID = function() return "Player-1-0000TEST" end
G.UnitLevel = function() return 60 end
G.UnitIsAFK = function() return false end
G.UnitOnTaxi = function() return false end
G.UnitIsDeadOrGhost = function() return false end
G.UnitAffectingCombat = function() return false end
G.IsResting = function() return false end
G.IsInInstance = function() return false, "none" end
G.InCombatLockdown = function() return stub.inCombat and true or false end
G.InCinematic = function() return stub.inCinematic and true or false end
G.IsInCinematicScene = function() return false end
G.IsEncounterInProgress = function() return stub.inEncounter and true or false end
G.MovieFrame = mkframe("Frame", "MovieFrame")
G.CinematicFrame = mkframe("Frame", "CinematicFrame")
G.IsInGroup = function() return false end
G.GetNumGroupMembers = function() return 0 end
G.C_Map = { GetBestMapForUnit = function() return 1411 end }
G.GetRealZoneText = function() return "Mulgore" end
G.GetZoneText = function() return "Mulgore" end
G.issecretvalue = function() return false end
G.GetAddOnMetadata = function(_, f) return f == "Version" and "0.1.0" or nil end
G.C_AddOns = { GetAddOnMetadata = G.GetAddOnMetadata, IsAddOnLoaded = function() return true end }
G.IsAddOnLoaded = function() return true end
G.GetCVar = function() return "0" end

-- Sound / UI services ---------------------------------------------------------------------------------------
G.SOUNDKIT = {}
for _, n in ipairs({ "IG_QUEST_LIST_OPEN", "IG_MAINMENU_OPEN", "IG_QUEST_LIST_COMPLETE", "IG_CHARACTER_INFO_TAB",
                     "READY_CHECK", "IG_MAINMENU_OPTION_CHECKBOX_ON" }) do G.SOUNDKIT[n] = 1 end
G.PlaySound = function() end
G.PlaySoundFile = function() end
G.FlashClientIcon = function() end

local function category(name)
  local c = { name = name, id = 1 }
  function c:GetID() return self.id end
  return c
end
G.Settings = {
  RegisterCanvasLayoutCategory = function(_, name) return category(name) end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function() end,
}
G.SlashCmdList = {}
G.hash_SlashCmdList = {}
G.StaticPopupDialogs = {}
G.StaticPopup_Show = function() end
G.UISpecialFrames = {}
G.CreateColor = function(r, g, b, a)
  local c = { r = r, g = g, b = b, a = a or 1 }
  function c:GetRGB() return self.r, self.g, self.b end
  function c:GetRGBA() return self.r, self.g, self.b, self.a end
  function c:WrapTextInColorCode(t) return t end
  return c
end
G.Mixin = function(obj, ...)
  for i = 1, select("#", ...) do
    for k, v in pairs((select(i, ...))) do obj[k] = v end
  end
  return obj
end

-- Lua conveniences WoW provides ------------------------------------------------------------------------------
G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
G.strsplit = function(delim, s, n)
  local out, pos = {}, 1
  while true do
    local i = s:find(delim, pos, true)
    if not i or (n and #out >= n - 1) then out[#out + 1] = s:sub(pos) break end
    out[#out + 1] = s:sub(pos, i - 1)
    pos = i + #delim
  end
  return unpack(out)
end
G.strtrim = function(s, chars)
  chars = chars or " \t\r\n"
  local set = "[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]"
  return (s:gsub("^" .. set .. "+", ""):gsub(set .. "+$", ""))
end
G.strjoin = function(d, ...) return table.concat({ ... }, d) end
G.format, G.tinsert, G.tremove, G.sort = string.format, table.insert, table.remove, table.sort
G.strlower, G.strupper, G.strfind, G.strsub, G.strlen = string.lower, string.upper, string.find, string.sub, string.len
G.gsub, G.strrep = string.gsub, string.rep
G.floor, G.ceil, G.abs, G.max, G.min, G.sqrt, G.random = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt,
  math.random
G.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
G.hooksecurefunc = function() end

-- Unknown uppercase globals (probable API gaps) are noted, not fatal.
setmetatable(G, { __index = function(_, k)
  if type(k) == "string" and k:find("^%u") and not k:find("^SLASH_") then stub.unknown[k] = true end
  return nil
end })

stub.mkframe = mkframe
return stub
