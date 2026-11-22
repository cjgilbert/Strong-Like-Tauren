local ADDON, ns = ...

-- Muscle-group load from recent history.
--   F[g]    decayed fatigue (half-life in minutes) - only used to rank choices and explain them
--   hour[g] raw load (standard sets) in the last 60 minutes - hard cap
--   day[g]  raw load today - hard cap
local Fatigue = {}
ns.Fatigue = Fatigue

local DONE = ns.History.DONE

function Fatigue.compute(rows, now, halfLifeMin, todayKey)
  local F, hour, day = {}, {}, {}
  local hl = (halfLifeMin or 60) * 60
  for i = #rows, 1, -1 do
    local r = rows[i]
    local age = now - r.t
    if age > 86400 then break end -- rows are chronological
    if age >= 0 and DONE[r.o] and r.g and r.l and r.l > 0 then
      local decay = 0.5 ^ (age / hl)
      for g, w in pairs(r.g) do
        local load = r.l * w
        F[g] = (F[g] or 0) + load * decay
        if age < 3600 then hour[g] = (hour[g] or 0) + load end
        if r.d == todayKey then day[g] = (day[g] or 0) + load end
      end
    end
  end
  return F, hour, day
end
