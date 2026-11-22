local ADDON, ns = ...
local U, C = ns.U, ns.C

-- SavedVariables: StrongLikeTaurenDB (account-wide: the human's body, history, settings) and
-- StrongLikeTaurenCharDB (per character: a stable key and the zones this character has visited).
local DB = {}
ns.DB = DB

function DB.newAccount(now)
  return {
    v = C.SCHEMA,
    created = now,
    settings = C.defaultSettings(),
    lib = { over = {}, custom = {}, seq = 0 },
    body = { acc = 0, lastTick = now, stretchStart = now, rooted = 0, skipUntil = 0, earlyOffered = false,
             rage = ns.Rage.new(40) },
    nudge = { lastAt = 0, ignored = 0, snoozeUntil = 0, pauseUntil = 0 },
    queue = { seq = 0, items = {} },
    log = { seq = 0, ver = 0, rows = {} },
    days = {},
    totals = { ex = {}, g = {}, walks = 0, walkSec = 0, feats = 0, credited = 0 },
    chars = {},
    charSeq = 0,
    prog = { rep = 0, repDay = { day = "", n = 0 }, dailies = 0, doubles = 0, enraged = 0, streak = { cur = 0, best = 0, last = "" }, ach = {} },
    errors = {},
  }
end

-- Per-version upgrades: MIGRATIONS[n] upgrades a version n-1 table to version n.
DB.MIGRATIONS = {}

-- Makes every setting valid (right type, in range), keeping what the player chose where possible.
function DB.repairSettings(s)
  if type(s) ~= "table" then s = {} end
  for _, opt in ipairs(C.OPTIONS) do
    U.setPath(s, opt[1], C.validate(opt, U.getPath(s, opt[1])))
  end
  if type(s.groupPct) ~= "table" then s.groupPct = {} end
  for g, v in pairs(s.groupPct) do
    if not C.CAPPED[g] or type(v) ~= "number" or v ~= v then s.groupPct[g] = nil
    else s.groupPct[g] = U.clamp(U.round(v), 10, 300) end
  end
  local t = s.totem
  if t.point ~= nil and type(t.point) ~= "string" then t.point = nil end
  if type(t.x) ~= "number" or t.x ~= t.x then t.x = nil end
  if type(t.y) ~= "number" or t.y ~= t.y then t.y = nil end
  return s
end

local function validRow(r)
  return type(r) == "table" and type(r.t) == "number" and type(r.x) == "string" and type(r.o) == "string"
    and type(r.d) == "string"
end

local function validItem(it)
  if type(it) ~= "table" or (it.k ~= "W" and it.k ~= "F") or type(it.slots) ~= "table" or #it.slots == 0 then
    return false
  end
  for _, sl in ipairs(it.slots) do
    if type(sl) ~= "table" or type(sl.x) ~= "string" or type(sl.a) ~= "number" then return false end
  end
  return true
end

-- Repairs structure in place: wrong types are replaced with defaults, broken rows/items are dropped.
function DB.repair(db, now)
  local fresh = DB.newAccount(now)
  for k, v in pairs(fresh) do
    if type(db[k]) ~= type(v) then db[k] = v end
  end
  db.settings = DB.repairSettings(db.settings)
  for _, key in ipairs({ "lib", "body", "nudge", "queue", "log", "totals", "prog" }) do
    U.merge(db[key], fresh[key])
  end
  if type(db.body.rage) ~= "table" then db.body.rage = ns.Rage.new(40) end
  U.merge(db.body.rage, fresh.body.rage)
  db.body.rage.v = U.clamp(tonumber(db.body.rage.v) or 0, 0, C.RAGE_BANK)
  if type(db.body.paused) ~= "number" then db.body.paused = nil end

  local rows, keep = db.log.rows, {}
  for i = 1, #rows do if validRow(rows[i]) then keep[#keep + 1] = rows[i] end end
  if #keep ~= #rows then db.log.rows = keep end

  local items, keepItems, seen = db.queue.items, {}, {}
  for i = 1, #items do
    local it = items[i]
    if validItem(it) and not seen[it.k] then
      seen[it.k] = true
      keepItems[#keepItems + 1] = it
    end
  end
  db.queue.items = keepItems

  for k, d in pairs(db.days) do
    if type(k) ~= "string" or type(d) ~= "table" then db.days[k] = nil end
  end
  for k, c in pairs(db.chars) do
    if type(c) ~= "table" or type(c.idx) ~= "number" then db.chars[k] = nil end
  end
  if type(db.errors) ~= "table" then db.errors = {} end
  return db
end

-- Loads (or creates) the account DB. A table we can't recognise is parked in db.broken, never thrown away.
function DB.init(sv, now)
  local db, note
  if type(sv) ~= "table" or type(sv.v) ~= "number" then
    db = DB.newAccount(now)
    if type(sv) == "table" and next(sv) ~= nil then
      db.broken = sv
      note = "unrecognised"
    end
  else
    db = sv
    if db.v > C.SCHEMA then
      note = "newer"
    else
      for v = db.v + 1, C.SCHEMA do
        local m = DB.MIGRATIONS[v]
        if m then
          local ok, err = pcall(m, db)
          if not ok then
            local broken = db
            db = DB.newAccount(now)
            db.broken = broken
            note = "migration failed: " .. tostring(err)
            break
          end
        end
        db.v = v
      end
    end
  end
  DB.repair(db, now)
  return db, note
end

-- Per-character data and a stable key. Names on Forever are "First Surname" with realms hidden, so the key is a
-- random id; if this character's file was lost but its GUID is known, the old key is reused.
function DB.initChar(db, cdb, info, rng)
  if type(cdb) ~= "table" then cdb = {} end
  cdb.v = 1
  if type(cdb.zones) ~= "table" then cdb.zones = {} end
  local key = type(cdb.key) == "string" and cdb.key ~= "" and cdb.key or nil
  if not key and info and info.guid then
    for k, c in pairs(db.chars) do
      if c.guid == info.guid then key = k break end
    end
  end
  if not key then key = "k" .. U.randomHex(rng, 8) end
  cdb.key = key
  local c = db.chars[key]
  if not c then
    db.charSeq = (db.charSeq or 0) + 1
    c = { idx = db.charSeq }
    db.chars[key] = c
  end
  if info then
    c.name = info.name or c.name
    c.class = info.class or c.class
    c.guid = info.guid or c.guid
  end
  return cdb, c.idx
end

function DB.charName(db, idx)
  for _, c in pairs(db.chars) do
    if c.idx == idx then return c.name end
  end
end

-- Keeps the last 10 errors for /tauren bug.
function DB.logError(db, now, msg)
  if type(db) ~= "table" or type(db.errors) ~= "table" then return end
  table.insert(db.errors, 1, { t = now, msg = tostring(msg):sub(1, 600) })
  while #db.errors > 10 do table.remove(db.errors) end
end
