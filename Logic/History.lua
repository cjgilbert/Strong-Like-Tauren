local ADDON, ns = ...
local U = ns.U

-- The exercise ledger. Every outcome is a row; day/lifetime totals are kept incrementally with apply(row, +-1),
-- so undo is exact and pruning old raw rows never changes the totals.
--
-- Row: { id, t = time, d = day key, x = exercise id, k = "r"|"s", a = amount, l = load in standard sets,
--        g = muscle-group weights, o = outcome, s = source, p = tier %, c = character index, q = queue item id,
--        r = rep gained, cn = counted toward the daily }
-- Outcomes: done, part (partial), skip, exp (expired), cred (credited break)
-- Sources:  walk (Walkabout), feat (Feat of Strength), man (manual log), away (credited away time),
--           up ("I got up"), move (Walkabout credited by other exercise)
local History = {}
ns.History = History

History.DONE = { done = true, part = true }
local DONE = History.DONE

History.KEEP_DAYS = 90
History.MAX_ROWS = 6000

local function newDay()
  return {
    ex = {}, g = {},
    w = { due = 0, done = 0, skip = 0, cred = 0 },
    f = { earn = 0, done = 0, skip = 0, exp = 0 },
    seatMax = 0, play = 0, dn = 0, dq = false,
  }
end

function History.day(db, dayKey)
  local d = db.days[dayKey]
  if type(d) ~= "table" then
    d = newDay()
    db.days[dayKey] = d
  else
    U.merge(d, newDay())
  end
  return d
end

function History.apply(db, row, sign)
  local d, T = History.day(db, row.d), db.totals
  local isWalk = (row.s == "walk")
  local isFeat = (row.s == "feat")
  if DONE[row.o] then
    local e = d.ex[row.x]
    if not e then e = { a = 0, n = 0 }; d.ex[row.x] = e end
    e.a = e.a + sign * (row.a or 0)
    e.n = e.n + sign
    T.ex[row.x] = (T.ex[row.x] or 0) + sign * (row.a or 0)
    if row.g and row.l then
      for g, w in pairs(row.g) do
        local load = sign * row.l * w
        d.g[g] = (d.g[g] or 0) + load
        T.g[g] = (T.g[g] or 0) + load
      end
    end
    if isWalk then
      d.w.done = d.w.done + sign
      T.walks = T.walks + sign
      T.walkSec = T.walkSec + sign * (row.a or 0)
    elseif isFeat then
      d.f.done = d.f.done + sign
      T.feats = T.feats + sign
    end
  elseif row.o == "skip" then
    if isWalk then d.w.skip = d.w.skip + sign elseif isFeat then d.f.skip = d.f.skip + sign end
  elseif row.o == "exp" then
    d.f.exp = d.f.exp + sign
  elseif row.o == "cred" then
    d.w.cred = d.w.cred + sign
    T.credited = T.credited + sign
  end
end

function History.append(db, row)
  local log = db.log
  log.seq = (log.seq or 0) + 1
  row.id = log.seq
  log.rows[#log.rows + 1] = row
  History.apply(db, row, 1)
  log.ver = (log.ver or 0) + 1
  return row
end

function History.find(db, id)
  local rows = db.log.rows
  for i = #rows, 1, -1 do
    if rows[i].id == id then return i, rows[i] end
  end
end

-- Removes a row and reverses its effect on all totals. Returns the row, or nil if not found.
function History.undo(db, id)
  local i, row = History.find(db, id)
  if not i then return nil end
  History.apply(db, row, -1)
  table.remove(db.log.rows, i)
  db.log.ver = (db.log.ver or 0) + 1
  return row
end

-- Drops raw rows older than KEEP_DAYS (and the oldest beyond MAX_ROWS). Totals are untouched.
function History.prune(db, now)
  local rows = db.log.rows
  local cutoff = now - History.KEEP_DAYS * 86400
  local first = 1
  while first <= #rows and (rows[first].t < cutoff or (#rows - first + 1) > History.MAX_ROWS) do
    first = first + 1
  end
  if first == 1 then return 0 end
  local keep = {}
  for i = first, #rows do keep[#keep + 1] = rows[i] end
  db.log.rows = keep
  db.log.ver = (db.log.ver or 0) + 1
  return first - 1
end

function History.lastDone(db, x)
  local rows = db.log.rows
  for i = #rows, 1, -1 do
    local r = rows[i]
    if r.x == x and DONE[r.o] then return r.t end
  end
end

-- Completion rate over the last `days` day keys (done + partial vs. skipped + expired), or nil when no data.
function History.completionRate(db, now, days, dayStart)
  local done, missed = 0, 0
  for i = 0, days - 1 do
    local d = db.days[U.dayKey(now - i * 86400, dayStart)]
    if d then
      done = done + d.w.done + d.f.done
      missed = missed + d.w.skip + d.f.skip + d.f.exp
    end
  end
  if done + missed == 0 then return nil end
  return done / (done + missed), done + missed
end
