local ADDON, ns = ...
local C = ns.C

-- Rage: 0-100 per Feat, banking up to C.RAGE_BANK (200) when `bank` is on. Fills passively with active play and from
-- game events (with diminishing returns). 100 earns a Feat of Strength (at most one per cooldown); a Feat spends 100,
-- or 200 for a Double Feat, and what is left stays banked. With banking off the bar clamps at 100 as it always did.
local Rage = {}
ns.Rage = Rage

function Rage.new(start)
  return { v = start or 40, lastFeatAt = 0, src = {}, ev = {}, last = {} }
end

-- The most Rage the bar can hold.
function Rage.cap(bank)
  return bank and C.RAGE_BANK or 100
end

-- Clamps to the cap and snaps float drift: 360 ticks of 0.2777 must reach exactly 100 (and 200 when banking).
local function settle(v, cap)
  v = math.min(cap, v)
  if cap > 100 and math.abs(v - 100) < 1e-6 then v = 100 end
  if v > cap - 1e-6 then v = cap end
  return v
end

-- dt seconds of active play; a full bar takes fullMin minutes. bank: keep filling past 100 up to 200.
-- Also clamps an existing value to the cap (e.g. banking was switched off with Rage above 100).
function Rage.passive(R, dt, fullMin, bank)
  local cap = Rage.cap(bank)
  if dt <= 0 then R.v = settle(R.v, cap) return end
  R.v = settle(R.v + dt * 100 / (fullMin * 60), cap)
end

-- Adds Rage for a game event. gain = base / (1 + 0.5 * same-kind events in the last hour).
-- Gains made while capped still count toward the flavor of the next Feat.
function Rage.event(R, kind, now, weights, dedupe, bank)
  local base = weights and weights[kind] or 0
  if not base or base <= 0 then return 0 end
  local window = dedupe and dedupe[kind]
  if window and R.last[kind] and now - R.last[kind] < window then return 0 end
  R.last[kind] = now
  local keep = {}
  local list = R.ev[kind]
  if type(list) == "table" then
    for i = 1, #list do
      if now - list[i] < 3600 then keep[#keep + 1] = list[i] end
    end
  end
  local n = #keep
  keep[#keep + 1] = now
  R.ev[kind] = keep
  local gain = base / (1 + 0.5 * n)
  R.src[kind] = (R.src[kind] or 0) + gain
  R.v = settle(R.v + gain, Rage.cap(bank))
  return gain
end

function Rage.cooldownLeft(R, now, cdMin)
  return math.max(0, cdMin * 60 - (now - (R.lastFeatAt or 0)))
end

function Rage.ready(R, now, cdMin)
  return R.v >= 100 and Rage.cooldownLeft(R, now, cdMin) <= 0
end

-- Spends 100 * size Rage (size 1 = Feat, 2 = Double Feat), leaving the rest banked, and returns the flavor: the
-- biggest event source since the last Feat (if it gave >= 20).
function Rage.spend(R, now, size)
  local best, bestV = nil, 0
  for _, kind in ipairs(C.RAGE_KINDS) do
    local v = R.src[kind] or 0
    if v > bestV then best, bestV = kind, v end
  end
  R.v = math.max(0, R.v - 100 * (size or 1))
  R.src = {}
  R.lastFeatAt = now
  if bestV >= 20 then return best end
  return nil
end
