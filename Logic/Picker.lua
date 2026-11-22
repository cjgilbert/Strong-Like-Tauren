local ADDON, ns = ...
local U, C, L = ns.U, ns.C, ns.L
local Library, Fatigue = ns.Library, ns.Fatigue
local DONE = ns.History.DONE

-- Chooses what to do. Walkabout moves are timed light movement; Feat slots are strength/cardio sets,
-- sized by tier and kept under the hourly/daily caps per muscle group.
local Picker = {}
ns.Picker = Picker

local PREF_W = { 0.5, 1, 2 }   -- preference 1 (less often), 2 (normal), 3 (favorite)
local NEVER_DONE_MIN = 240     -- "minutes since" used for exercises never done

-- Snapshot of everything the picker needs, computed once per decision.
function Picker.context(db, defs, byId, now, rng)
  local s = db.settings
  local today = U.dayKey(now, s.dayStart)
  local rows = db.log.rows
  local F, hour, day = Fatigue.compute(rows, now, s.halfLife, today)
  local last, lastGroup = {}, {}
  local prevFeat, prevWalk
  for i = #rows, 1, -1 do
    local r = rows[i]
    if now - r.t > 7 * 86400 then break end
    if DONE[r.o] then
      if not last[r.x] then last[r.x] = r.t end
      if r.s == "feat" and not prevFeat then prevFeat = r.x end
      if r.s == "walk" and not prevWalk then prevWalk = r.x end
      if r.g then
        for g, w in pairs(r.g) do
          if w >= 0.3 and not lastGroup[g] then lastGroup[g] = r.t end
        end
      end
    end
  end
  return {
    s = s, defs = defs, byId = byId, now = now, rng = rng, today = today,
    F = F, hour = hour, day = day, last = last, lastGroup = lastGroup,
    prevFeat = prevFeat, prevWalk = prevWalk,
  }
end

local function minutesSince(P, id)
  local t = P.last[id]
  if not t then return NEVER_DONE_MIN end
  return (P.now - t) / 60
end

-- Amount for `sets` standard sets at `pct`%: reps rounded to whole numbers, seconds to the nearest 5.
-- Returns amount, load (in standard sets), unit (amount of one standard set).
function Picker.amount(def, pct, sets)
  local unit = def.std * pct / 100
  local raw = unit * sets
  local a
  if def.kind == "s" then a = math.max(5, U.round5(raw)) else a = math.max(1, U.round(raw)) end
  a = U.clamp(a, def.lo or 1, def.hi or a)
  return a, (unit > 0) and a / unit or 0, unit
end

-- Walkabout move -------------------------------------------------------------------------------------
function Picker.walkCandidates(P, exclude)
  local s, out = P.s, {}
  for _, d in ipairs(P.defs) do
    if d.walk and Library.allowed(d, s) and not (exclude and exclude[d.id]) then
      if Library.isStanding(d) or s.filters.seatedOk then out[#out + 1] = d end
    end
  end
  return out
end

function Picker.walkMove(P, flavor, exclude)
  local cands = Picker.walkCandidates(P, exclude)
  if #cands == 0 then
    if exclude then return nil end
    return P.byId.march or P.byId.walk
  end
  return U.weightedPick(cands, function(d)
    local w = PREF_W[d.pref or 2] or 1
    if d.id == P.prevWalk then w = w * 0.25 end
    if flavor and d.tags and d.tags[flavor] then w = w * 3 end
    return w * U.clamp(minutesSince(P, d.id) / 120, 0.25, 2)
  end, P.rng)
end

function Picker.walkSlot(P, minutes, flavor)
  local d = Picker.walkMove(P, flavor)
  local a = minutes * 60
  return { x = d.id, a = a, u = d.std, l = a / d.std, p = 100, walk = true }
end

-- Feat slots -----------------------------------------------------------------------------------------
-- How many standard sets of `d` still fit under the hourly and daily caps.
local function capRoom(P, d, hour, day)
  local room = math.huge
  for g, w in pairs(d.g) do
    if C.CAPPED[g] and w > 0 then
      room = math.min(room, (P.s.cap.hour - (hour[g] or 0)) / w, (P.s.cap.day - (day[g] or 0)) / w)
    end
  end
  return room
end

function Picker.score(P, d, flavor)
  local w = PREF_W[d.pref or 2] or 1
  w = w * U.clamp(minutesSince(P, d.id) / 120, 0.25, 2)
  w = w / (1 + (P.F[d.primary] or 0))
  if flavor and d.tags and d.tags[flavor] then w = w * 2 end
  return w
end

function Picker.why(P, d, flavor, shrunk)
  local parts = {}
  if flavor and d.tags and d.tags[flavor] then
    parts[#parts + 1] = L["fits"] .. " " .. (C.RAGE_NAME[flavor] or flavor):lower()
  end
  local g = d.primary
  local lastG = P.lastGroup[g]
  if lastG then
    parts[#parts + 1] = ("%s %s %s"):format(C.GROUP_NAME[g] or g, L["rested"], U.fmtDuration(P.now - lastG))
  else
    parts[#parts + 1] = ("%s %s"):format(C.GROUP_NAME[g] or g, L["fresh"])
  end
  local busiest, busiestF = nil, 0.4
  for _, gg in ipairs(C.GROUPS) do
    local f = P.F[gg] or 0
    if C.CAPPED[gg] and gg ~= g and f > busiestF then busiest, busiestF = gg, f end
  end
  if busiest then parts[#parts + 1] = ("%s %s"):format(C.GROUP_NAME[busiest], L["resting"]) end
  if shrunk then parts[#parts + 1] = L["smaller set (near your hourly cap)"] end
  if (d.pref or 2) >= 3 then parts[#parts + 1] = L["a favorite"] end
  return table.concat(parts, " · ")
end

-- One Feat slot for `target` standard sets. Relaxes rules in order (rest -> previous pick) before giving up.
function Picker.oneSlot(P, target, flavor, used, usedPrim, hour, day, exclude)
  for relax = 0, 2 do
    local cands = {}
    for _, d in ipairs(P.defs) do
      if not d.walk and Library.allowed(d, P.s) and not used[d.id] and not usedPrim[d.primary]
          and not (exclude and exclude[d.id]) then
        local okRest = relax >= 1 or not P.last[d.id] or (P.now - P.last[d.id]) >= (d.rest or 0)
        local okPrev = relax >= 2 or d.id ~= P.prevFeat
        if okRest and okPrev then
          local sets = math.min(target, capRoom(P, d, hour, day))
          if sets >= 0.5 * target - 1e-9 then cands[#cands + 1] = { d = d, sets = sets } end
        end
      end
    end
    if #cands > 0 then
      local c = U.weightedPick(cands, function(c) return Picker.score(P, c.d, flavor) end, P.rng)
      local pct = Library.effectivePct(c.d, P.s)
      local a, l, unit = Picker.amount(c.d, pct, c.sets)
      return { x = c.d.id, sets = c.sets, a = a, l = l, u = unit, p = pct,
               why = Picker.why(P, c.d, flavor, c.sets < target - 1e-9) }
    end
  end
  return nil
end

-- Fallback when filters and caps leave nothing: neighbor-friendly step jacks, else marching.
function Picker.fallbackSlot(P)
  local d = P.byId.lowjacks
  if d and Library.allowed(d, P.s) then
    local pct = Library.effectivePct(d, P.s)
    local a, l, unit = Picker.amount(d, pct, 1)
    return { x = d.id, sets = 1, a = a, l = l, u = unit, p = pct, why = L["everything else is resting"] }
  end
  d = P.byId.march
  return { x = d.id, sets = 1, a = 120, l = 1, u = d.std, p = 100, why = L["everything else is resting"] }
end

local function addLoad(hour, day, d, sets)
  for g, w in pairs(d.g) do
    hour[g] = (hour[g] or 0) + sets * w
    day[g] = (day[g] or 0) + sets * w
  end
end

-- n slots on different primary muscle groups. bonus: +0.25 per ding / merge (max +0.5).
function Picker.featSlots(P, n, bonus, flavor)
  local target = 1 + (bonus or 0)
  local hour, day = U.copy(P.hour), U.copy(P.day)
  local used, usedPrim, slots = {}, {}, {}
  for _ = 1, n do
    local slot = Picker.oneSlot(P, target, flavor, used, usedPrim, hour, day)
    if not slot then break end
    local d = P.byId[slot.x]
    slots[#slots + 1] = slot
    used[d.id] = true
    usedPrim[d.primary] = true
    addLoad(hour, day, d, slot.sets)
  end
  if #slots == 0 then slots[1] = Picker.fallbackSlot(P) end
  return slots
end

-- Re-rolls one slot: same load, excluding everything already tried. Max 3 swaps per slot.
function Picker.swap(P, item, idx)
  local slot = item.slots[idx]
  if not slot or slot.o then return nil, "resolved" end
  if (slot.swaps or 0) >= 3 then return nil, "limit" end
  local tried = slot.tried or {}
  tried[slot.x] = true
  local new
  if item.k == "W" then
    local d = Picker.walkMove(P, item.flavor, tried)
    if not d then return nil, "none" end
    new = { x = d.id, a = slot.a, u = d.std, l = slot.a / d.std, p = 100, walk = true }
  else
    local used, usedPrim = {}, {}
    local hour, day = U.copy(P.hour), U.copy(P.day)
    for j, other in ipairs(item.slots) do
      local d2 = P.byId[other.x]
      if j ~= idx and d2 then
        used[d2.id] = true
        usedPrim[d2.primary] = true
        if not other.o then addLoad(hour, day, d2, other.sets or 1) end
      end
    end
    new = Picker.oneSlot(P, slot.sets or 1, item.flavor, used, usedPrim, hour, day, tried)
    if not new then return nil, "none" end
  end
  new.swaps = (slot.swaps or 0) + 1
  new.tried = tried
  item.slots[idx] = new
  return new
end

-- Scales an unresolved slot (used when a second Feat merges into a pending one).
function Picker.rescale(byId, slot, factor)
  local d = byId[slot.x]
  if not d or slot.o or slot.walk then return end
  slot.sets = (slot.sets or 1) * factor
  local a, l, unit = Picker.amount(d, slot.p or 100, slot.sets)
  slot.a, slot.l, slot.u = a, l, unit
end
