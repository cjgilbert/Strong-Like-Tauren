local ADDON, ns = ...
local C = ns.C

-- Rage: 0-100. Fills passively with active play and from game events (with diminishing returns).
-- A full bar earns a Feat of Strength, at most one per cooldown.
local Rage = {}
ns.Rage = Rage

function Rage.new(start)
  return { v = start or 40, lastFeatAt = 0, src = {}, ev = {}, last = {} }
end

-- dt seconds of active play; a full bar takes fullMin minutes.
function Rage.passive(R, dt, fullMin)
  if dt <= 0 then return end
  R.v = math.min(100, R.v + dt * 100 / (fullMin * 60))
  if R.v > 100 - 1e-6 then R.v = 100 end -- float drift: 360 ticks of 0.2777 must reach exactly 100
end

-- Adds Rage for a game event. gain = base / (1 + 0.5 * same-kind events in the last hour).
-- Gains made while capped still count toward the flavor of the next Feat.
function Rage.event(R, kind, now, weights, dedupe)
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
  R.v = math.min(100, R.v + gain)
  return gain
end

function Rage.cooldownLeft(R, now, cdMin)
  return math.max(0, cdMin * 60 - (now - (R.lastFeatAt or 0)))
end

function Rage.ready(R, now, cdMin)
  return R.v >= 100 and Rage.cooldownLeft(R, now, cdMin) <= 0
end

-- Empties the bar and returns the flavor: the biggest event source since the last Feat (if it gave >= 20).
function Rage.spend(R, now)
  local best, bestV = nil, 0
  for _, kind in ipairs(C.RAGE_KINDS) do
    local v = R.src[kind] or 0
    if v > bestV then best, bestV = kind, v end
  end
  R.v = 0
  R.src = {}
  R.lastFeatAt = now
  if bestV >= 20 then return best end
  return nil
end
