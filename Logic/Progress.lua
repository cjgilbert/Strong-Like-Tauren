local ADDON, ns = ...
local C, U = ns.C, ns.U
local History = ns.History

-- Reputation with the Bloodhoof Athletic Club, the daily quest, streaks and achievements.
local Progress = {}
ns.Progress = Progress

-- Standing index (1-8) for a rep total, plus the threshold of the next standing (nil at Exalted).
function Progress.standing(rep)
  local idx = 1
  for i, st in ipairs(C.STANDINGS) do
    if rep >= st.min then idx = i end
  end
  local nextSt = C.STANDINGS[idx + 1]
  return idx, C.STANDINGS[idx], nextSt and nextSt.min or nil
end

-- Adds rep, capped per day. Returns the amount gained and the new standing name if it went up.
function Progress.addRep(db, amount, dayKey)
  local P = db.prog
  if P.repDay.day ~= dayKey then
    P.repDay.day = dayKey
    P.repDay.n = 0
  end
  local gain = math.max(0, math.min(amount, C.REP.dayCap - P.repDay.n))
  local before = Progress.standing(P.rep)
  P.rep = P.rep + gain
  P.repDay.n = P.repDay.n + gain
  local after = Progress.standing(P.rep)
  return gain, (after > before) and C.STANDINGS[after].name or nil
end

function Progress.removeRep(db, amount)
  local P = db.prog
  P.rep = math.max(0, P.rep - (amount or 0))
  P.repDay.n = math.max(0, P.repDay.n - (amount or 0))
end

-- A play day "counts" for the streak once it has STREAK_PLAY_MIN seconds of play.
local function playedDay(d)
  return d and (d.play or 0) >= C.STREAK_PLAY_MIN
end

-- Advances the streak when today's daily is done. Days off never break it; a played day without the daily does.
function Progress.updateStreak(db, dayKey)
  local S = db.prog.streak
  if S.last == dayKey then return end
  local broken = (S.last == "")
  if not broken then
    for k, d in pairs(db.days) do
      if k > S.last and k < dayKey and playedDay(d) and not d.dq then
        broken = true
        break
      end
    end
  end
  S.cur = broken and 1 or (S.cur + 1)
  if S.cur > S.best then S.best = S.cur end
  S.last = dayKey
end

-- The streak as it stands right now (0 if a played day since the last completed daily was missed).
function Progress.currentStreak(db, todayKey)
  local S = db.prog.streak
  if S.last == "" then return 0 end
  for k, d in pairs(db.days) do
    if k > S.last and k < todayKey and playedDay(d) and not d.dq then return 0 end
  end
  return S.cur
end

-- Counts one completion toward today's daily. Returns true when this completion finished the daily.
function Progress.onCompletion(db, dayKey)
  local day = History.day(db, dayKey)
  day.dn = (day.dn or 0) + 1
  if day.dq or day.dn < C.DAILY_GOAL then return false end
  day.dq = true
  db.prog.dailies = (db.prog.dailies or 0) + 1
  Progress.updateStreak(db, dayKey)
  return true
end

local function met(db, a)
  local T, P = db.totals, db.prog
  if a.type == "walks" then return (T.walks or 0) >= a.n
  elseif a.type == "ex" then return (T.ex[a.x] or 0) >= a.n
  elseif a.type == "feats" then return (T.feats or 0) >= a.n
  elseif a.type == "streak" then return (P.streak.best or 0) >= a.n
  elseif a.type == "rep" then return (P.rep or 0) >= a.n
  elseif a.type == "dailies" then return (P.dailies or 0) >= a.n
  elseif a.type == "doubles" then return (P.doubles or 0) >= a.n
  elseif a.type == "distinct" then
    local n = 0
    for _, v in pairs(T.ex) do if v > 0 then n = n + 1 end end
    return n >= a.n
  end
  return false
end

-- Marks and returns newly earned achievements.
function Progress.checkAchievements(db, now)
  local out = {}
  for _, a in ipairs(ns.D.ACHIEVEMENTS) do
    if not db.prog.ach[a.id] and met(db, a) then
      db.prog.ach[a.id] = now
      out[#out + 1] = a
    end
  end
  return out
end

function Progress.achievementProgress(db, a)
  local T, P = db.totals, db.prog
  if a.type == "walks" then return T.walks or 0
  elseif a.type == "ex" then return T.ex[a.x] or 0
  elseif a.type == "feats" then return T.feats or 0
  elseif a.type == "streak" then return P.streak.best or 0
  elseif a.type == "rep" then return P.rep or 0
  elseif a.type == "dailies" then return P.dailies or 0
  elseif a.type == "doubles" then return P.doubles or 0
  elseif a.type == "distinct" then
    local n = 0
    for _, v in pairs(T.ex) do if v > 0 then n = n + 1 end end
    return n
  end
  return 0
end
