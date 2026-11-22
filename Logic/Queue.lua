local ADDON, ns = ...

-- Pending work ("the Totem"). At most one Walkabout (W) and one Feat of Strength (F).
--   item = { id, k = "W"|"F", t = created, exp = expiry (Feats), min = minutes (W), rooted, bonus, merged,
--            flavor, slots = { { x, a, l, u, p, sets, o = outcome once resolved, done = amount done } } }
local Queue = {}
ns.Queue = Queue

function Queue.newId(Q)
  Q.seq = (Q.seq or 0) + 1
  return Q.seq
end

function Queue.get(Q, kind)
  for _, it in ipairs(Q.items) do
    if it.k == kind then return it end
  end
end

function Queue.byId(Q, id)
  for _, it in ipairs(Q.items) do
    if it.id == id then return it end
  end
end

function Queue.remove(Q, id)
  for i, it in ipairs(Q.items) do
    if it.id == id then
      table.remove(Q.items, i)
      return it
    end
  end
end

function Queue.dropWalk(Q)
  local W = Queue.get(Q, "W")
  if W then Queue.remove(Q, W.id) end
  return W
end

-- Creates the pending Walkabout, or upgrades it (it only ever grows; never duplicates).
function Queue.upsertWalk(Q, now, minutes, rooted, makeSlot)
  local it = Queue.get(Q, "W")
  if it then
    if minutes > it.min then
      it.min = minutes
      local sl = it.slots[1]
      if sl and not sl.o then
        sl.a = minutes * 60
        sl.l = sl.a / (sl.u or 120)
      end
    end
    it.rooted = math.max(it.rooted or 0, rooted or 0)
    return it, false
  end
  it = { id = Queue.newId(Q), k = "W", t = now, min = minutes, rooted = rooted or 0, slots = { makeSlot(minutes) } }
  table.insert(Q.items, 1, it)
  return it, true
end

-- Adds a Feat, or merges into the pending one: +25% once (total bonus capped at +50%) and a fresh expiry.
-- double = a Double Feat (twice the exercises, built by makeSlots); a merge into a pending Feat never makes one.
function Queue.addFeat(Q, now, flavor, bonus, expireH, makeSlots, rescale, double)
  local it = Queue.get(Q, "F")
  if it then
    local merged = false
    if not it.merged then
      local old = it.bonus or 0
      it.bonus = math.min(old + 0.25, 0.5)
      it.merged = true
      merged = it.bonus > old
      if merged then
        local factor = (1 + it.bonus) / (1 + old)
        for _, sl in ipairs(it.slots) do rescale(sl, factor) end
      end
    end
    it.exp = now + expireH * 3600
    it.flavor = it.flavor or flavor
    return it, false, merged
  end
  bonus = math.min(bonus or 0, 0.5)
  it = { id = Queue.newId(Q), k = "F", t = now, exp = now + expireH * 3600, bonus = bonus, flavor = flavor,
         slots = makeSlots(bonus, flavor), double = double and true or nil }
  Q.items[#Q.items + 1] = it
  return it, true, false
end

-- Removes expired items and returns them.
function Queue.expire(Q, now)
  local keep, gone = {}, {}
  for _, it in ipairs(Q.items) do
    if it.exp and now >= it.exp then gone[#gone + 1] = it else keep[#keep + 1] = it end
  end
  Q.items = keep
  return gone
end

function Queue.finished(it)
  for _, sl in ipairs(it.slots) do
    if not sl.o then return false end
  end
  return true
end

function Queue.anyDone(it)
  for _, sl in ipairs(it.slots) do
    if sl.o == "done" or sl.o == "part" then return true end
  end
  return false
end

-- Pending items in display order (Walkabout first).
function Queue.list(Q)
  local out = {}
  local W, F = Queue.get(Q, "W"), Queue.get(Q, "F")
  if W then out[#out + 1] = W end
  if F then out[#out + 1] = F end
  return out
end
