local ADDON, ns = ...

-- The seated clock: continuous seated play time in the current stretch (body.acc, seconds).
local Seated = {}
ns.Seated = Seated

-- Starts a fresh seated stretch (after a break, a long gap, or credited time away).
function Seated.fresh(B, now)
  B.acc = 0
  B.stretchStart = now
  B.skipUntil = 0
  B.earlyOffered = false
  B.rooted = 0
end

-- 0 when no Walkabout is due; otherwise 1 + one per 15 minutes overdue ("Rooted" stacks = level - 1).
function Seated.dueLevel(acc, everyMin)
  local every = everyMin * 60
  if acc < every then return 0 end
  return 1 + math.floor((acc - every) / 900)
end

function Seated.walkMinutes(level, dose, maxMin)
  if level <= 0 then return dose end
  return math.min(dose + level - 1, maxMin)
end
