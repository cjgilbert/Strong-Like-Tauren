local ADDON, ns = ...

-- Small pure helpers. Nothing here touches the WoW API, so these run in the offline test runner too.
local U = {}
ns.U = U

local floor, max, min = math.floor, math.max, math.min

U.date = date or (os and os.date)

function U.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function U.round(v)
  return floor(v + 0.5)
end

function U.round5(v)
  return 5 * floor(v / 5 + 0.5)
end

function U.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = U.copy(v) end
  return out
end

-- Fills missing keys in dst from defaults (deep). Values of the wrong type are replaced.
function U.merge(dst, defaults)
  if type(dst) ~= "table" then dst = {} end
  for k, dv in pairs(defaults) do
    local v = dst[k]
    if type(dv) == "table" then
      dst[k] = U.merge(type(v) == "table" and v or {}, dv)
    elseif v == nil or type(v) ~= type(dv) then
      dst[k] = dv
    end
  end
  return dst
end

function U.getPath(t, path)
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

function U.setPath(t, path, value)
  local parts = {}
  for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
  for i = 1, #parts - 1 do
    local p = parts[i]
    if type(t[p]) ~= "table" then t[p] = {} end
    t = t[p]
  end
  t[parts[#parts]] = value
end

-- Calendar day for a timestamp, with the day rolling over at `startHour` local time (default 4 am).
function U.dayKey(t, startHour)
  return U.date("%Y-%m-%d", t - (startHour or 4) * 3600)
end

-- "1h 05m", "12m", "45s"
function U.fmtDuration(sec)
  sec = max(0, floor(sec + 0.5))
  if sec < 60 then return sec .. "s" end
  local m = floor(sec / 60)
  if m < 60 then return m .. "m" end
  return ("%dh %02dm"):format(floor(m / 60), m % 60)
end

-- "4:05" or "1:02:03"
function U.fmtClock(sec)
  sec = max(0, floor(sec + 0.5))
  local h, m, s = floor(sec / 3600), floor(sec / 60) % 60, sec % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%d:%02d"):format(m, s)
end

function U.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function U.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function U.sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

function U.indexOf(list, value)
  for i = 1, #list do if list[i] == value then return i end end
  return nil
end

-- Deterministic Park-Miller RNG (exact in double precision), so tests and sims are reproducible.
-- In game it is seeded from the clock. rng:next() returns [0, 1).
function U.rng(seed)
  local state = floor(tonumber(seed) or 1) % 2147483647
  if state <= 0 then state = state + 2147483646 end
  local r = {}
  function r:next()
    state = (state * 16807) % 2147483647
    return (state - 1) / 2147483646
  end
  function r:int(a, b)
    return a + floor(self:next() * (b - a + 1))
  end
  return r
end

-- Picks one item from `list` with probability proportional to weight(item) (> 0).
function U.weightedPick(list, weight, rng)
  local total, ws = 0, {}
  for i = 1, #list do
    local w = weight(list[i])
    if w and w > 0 then ws[i] = w; total = total + w else ws[i] = 0 end
  end
  if total <= 0 then return nil end
  local roll = rng:next() * total
  for i = 1, #list do
    roll = roll - ws[i]
    if roll < 0 and ws[i] > 0 then return list[i] end
  end
  for i = #list, 1, -1 do if ws[i] > 0 then return list[i] end end
end

function U.randomHex(rng, digits)
  local out = {}
  for i = 1, digits do out[i] = ("%x"):format(rng:int(0, 15)) end
  return table.concat(out)
end

-- Picks a random element (uniform).
function U.pick(list, rng)
  if not list or #list == 0 then return nil end
  return list[rng:int(1, #list)]
end

U.max, U.min, U.floor = max, min, floor
