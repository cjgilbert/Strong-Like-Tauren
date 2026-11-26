local ADDON, ns = ...
local C, L = ns.C, ns.L

-- Share strings for exercise lists:   SLT1!<record>;<record>!<CCCC>
-- A record is comma-separated key=value pairs. Bytes outside [A-Za-z0-9.-] are escaped as ~HH (space -> +),
-- so strings never contain WoW "|" escape codes. CCCC is a Fletcher-16 checksum (hex) of everything before the
-- last "!". Decoding never executes anything; every record goes through Library.validate.
-- Optional key sd = l (counted per leg) | s (per side); absent or unknown = not sided, so older strings still decode.
local Codec = {}
ns.Codec = Codec

Codec.PREFIX = "SLT1!"
Codec.MAX_RECORDS = 60
Codec.MAX_BYTES = 8192

local FLAG_CODE = { jump = "j", floor = "F", wrist = "w", seated = "s" }
local CODE_FLAG = { j = "jump", F = "floor", w = "wrist", s = "seated" }
local TAG_CODE = { death = "d", boss = "b", quest = "q", zone = "z", hearth = "h", level = "l" }
local CODE_TAG = { d = "death", b = "boss", q = "quest", z = "zone", h = "hearth", l = "level" }

local function esc(s)
  return (tostring(s):gsub("[^A-Za-z0-9%.%-]", function(c)
    if c == " " then return "+" end
    return ("~%02X"):format(c:byte())
  end))
end

local function unesc(s)
  s = s:gsub("%+", " ")
  s = s:gsub("~(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  return s
end

function Codec.checksum(s)
  local a, b = 0, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 255
    b = (b + a) % 255
  end
  return ("%02X%02X"):format(b, a)
end

local function encodeOne(d)
  local p = { "id=" .. esc(d.id), "n=" .. esc(d.name or d.id) }
  if d.pun then p[#p + 1] = "p=" .. esc(d.pun) end
  p[#p + 1] = "k=" .. (d.kind == "s" and "s" or "r")
  p[#p + 1] = "s=" .. math.floor(d.std)
  if d.lo then p[#p + 1] = "lo=" .. math.floor(d.lo) end
  if d.hi then p[#p + 1] = "hi=" .. math.floor(d.hi) end
  local g = {}
  for _, grp in ipairs(C.GROUPS) do
    local w = d.g and d.g[grp]
    if w and w > 0 then g[#g + 1] = grp .. ":" .. math.floor(w * 10 + 0.5) end
  end
  p[#p + 1] = "g=" .. esc(table.concat(g, "/"))
  p[#p + 1] = "i=" .. (d.int or "m")
  local f = {}
  for _, key in ipairs({ "jump", "floor", "wrist", "seated" }) do
    if d.flags and d.flags[key] then f[#f + 1] = FLAG_CODE[key] end
  end
  if #f > 0 then p[#p + 1] = "f=" .. table.concat(f) end
  if d.needs then p[#p + 1] = "q=" .. esc(d.needs) end
  if d.rest then p[#p + 1] = "r=" .. math.floor(d.rest) end
  if d.pref and d.pref ~= 2 then p[#p + 1] = "pr=" .. math.floor(d.pref) end
  if d.pct then p[#p + 1] = "pc=" .. math.floor(d.pct) end
  if d.walk then p[#p + 1] = "w=1" end
  if d.side and d.kind ~= "s" then p[#p + 1] = "sd=" .. (d.side == "leg" and "l" or "s") end
  local t = {}
  for _, key in ipairs(C.RAGE_KINDS) do
    if d.tags and d.tags[key] then t[#t + 1] = TAG_CODE[key] end
  end
  if #t > 0 then p[#p + 1] = "t=" .. table.concat(t) end
  if d.desc then p[#p + 1] = "d=" .. esc(d.desc) end
  if d.on == false then p[#p + 1] = "off=1" end
  return table.concat(p, ",")
end

function Codec.encode(defs)
  local recs = {}
  for _, d in ipairs(defs) do recs[#recs + 1] = encodeOne(d) end
  local body = Codec.PREFIX .. table.concat(recs, ";")
  return body .. "!" .. Codec.checksum(body)
end

local function decodeOne(rec)
  local d = { g = {}, flags = {}, tags = {} }
  for kv in rec:gmatch("[^,]+") do
    local k, v = kv:match("^(%a+)=(.*)$")
    if k then
      if k == "id" then d.id = unesc(v)
      elseif k == "n" then d.name = unesc(v)
      elseif k == "p" then d.pun = unesc(v)
      elseif k == "d" then d.desc = unesc(v)
      elseif k == "k" then d.kind = (v == "s") and "s" or "r"
      elseif k == "s" then d.std = tonumber(v)
      elseif k == "lo" then d.lo = tonumber(v)
      elseif k == "hi" then d.hi = tonumber(v)
      elseif k == "r" then d.rest = tonumber(v)
      elseif k == "pr" then d.pref = tonumber(v)
      elseif k == "pc" then d.pct = tonumber(v)
      elseif k == "i" then d.int = v
      elseif k == "q" then d.needs = unesc(v)
      elseif k == "w" then d.walk = (v == "1")
      elseif k == "sd" then d.side = (v == "l") and "leg" or (v == "s" and "side" or nil)
      elseif k == "off" then d.on = (v ~= "1")
      elseif k == "g" then
        for grp, w in unesc(v):gmatch("(%a+):(%d+)") do d.g[grp] = tonumber(w) / 10 end
      elseif k == "f" then
        for ch in v:gmatch(".") do if CODE_FLAG[ch] then d.flags[CODE_FLAG[ch]] = true end end
      elseif k == "t" then
        for ch in v:gmatch(".") do if CODE_TAG[ch] then d.tags[CODE_TAG[ch]] = true end end
      end
    end
  end
  local clean = ns.Library.validate(d)
  if clean and tonumber(d.pct) then clean.pct = math.max(10, math.min(300, math.floor(d.pct))) end
  return clean
end

-- Returns a list of validated definitions, or nil and a reason. Records that fail validation are skipped
-- and counted in the second return value.
function Codec.decode(str)
  if type(str) ~= "string" then return nil, L["Nothing to import."] end
  str = str:gsub("%s", "")
  if #str == 0 then return nil, L["Nothing to import."] end
  if #str > Codec.MAX_BYTES then return nil, L["That string is too long."] end
  local body, sum = str:match("^(.*)!(%x%x%x%x)$")
  local ver = body and body:match("^SLT(%d+)!")
  if not ver then return nil, L["That isn't a Strong Like Tauren share string."] end
  if ver ~= "1" then return nil, L["That string was made by a newer version of Strong Like Tauren."] end
  if Codec.checksum(body) ~= sum:upper() then return nil, L["That string is damaged (checksum mismatch). Copy it again."] end
  local out, bad = {}, 0
  for rec in body:sub(#Codec.PREFIX + 1):gmatch("[^;]+") do
    if #out >= Codec.MAX_RECORDS then break end
    local d = decodeOne(rec)
    if d then out[#out + 1] = d else bad = bad + 1 end
  end
  if #out == 0 then return nil, L["No valid exercises in that string."] end
  return out, bad
end
