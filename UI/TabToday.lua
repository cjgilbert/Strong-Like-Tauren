local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local Kit = UI.Kit
local COL = Kit.COL

local Today = { title = L["Today"], live = true }
UI.Tabs.today = Today

local ROW_H = 18

function Today.build(parent)
  local root = CreateFrame("Frame", nil, parent)
  local scroll, content = Kit.scroll(root, 616, 418)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  local W = 588
  local flow = Kit.flow(content, W)
  local F = {}
  root.F = F

  F.seated = Kit.text(content, "", "GameFontNormal", COL.text, W)
  flow:add(F.seated, 18)
  F.next = Kit.text(content, "", "GameFontHighlight", COL.text, W)
  flow:add(F.next, 18)

  F.rage = Kit.bar(content, 400, 18, COL.rage)
  flow:add(F.rage, 18)
  F.rageLbl = Kit.text(content, L["Rage"], "GameFontHighlightSmall", COL.dim)
  F.rageLbl:SetPoint("LEFT", F.rage, "RIGHT", 8, 0)

  F.rep = Kit.bar(content, 400, 18, COL.green)
  flow:add(F.rep, 18)
  F.repLbl = Kit.text(content, "", "GameFontHighlightSmall", COL.dim, 170)
  F.repLbl:SetPoint("LEFT", F.rep, "RIGHT", 8, 0)

  F.daily = Kit.bar(content, 400, 18, COL.amber)
  flow:add(F.daily, 18)
  F.dailyLbl = Kit.text(content, "[Daily] " .. L["Earthmother's Calling"], "GameFontHighlightSmall", COL.dim, 170)
  F.dailyLbl:SetPoint("LEFT", F.daily, "RIGHT", 8, 0)

  F.streak = Kit.text(content, "", "GameFontHighlight", COL.text, W)
  flow:add(F.streak, 18)

  flow:space(4)
  local b1 = Kit.button(content, L["Walkabout now"], 130, 26, function() if ns.Do then ns.Do.forceWalk() end end)
  flow:add(b1, 26)
  local b2 = Kit.button(content, L["I got up"], 110, 26, function() if ns.Do then ns.Do.gotUp() end end)
  b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
  Kit.tip(b2, L["Tell the Club you stood up and moved. Resets your sitting clock."])
  F.rest = Kit.check(content, L["Rest day (no nudges today)"], function()
    return ns.db.body.restDay and true or false
  end, function(v) ns.Do.setRestDay(v) end, 260)
  F.rest:SetPoint("LEFT", b2, "RIGHT", 12, 0)

  flow:header(L["Today's work"])
  F.walks = Kit.text(content, "", "GameFontHighlight", COL.text, W)
  flow:add(F.walks, 18)
  F.seatMax = Kit.text(content, "", "GameFontHighlight", COL.text, W)
  flow:add(F.seatMax, 18)
  F.rate = Kit.text(content, "", "GameFontHighlight", COL.text, W)
  flow:add(F.rate, 18)
  F.hint = Kit.text(content, "", "GameFontHighlightSmall", COL.amber, W)
  flow:add(F.hint, 14)
  F.exTitle = Kit.text(content, L["Exercise totals"], "GameFontNormal", COL.gold, W)
  flow:add(F.exTitle, 18)
  F.exRows = {}
  for i = 1, 14 do
    local fs = Kit.text(content, "", "GameFontHighlight", COL.text, W - 12)
    flow:add(fs, 16, 12)
    F.exRows[i] = fs
  end

  flow:header(L["Achievements"])
  F.ach = {}
  for i, a in ipairs(ns.D.ACHIEVEMENTS) do
    local nameFs = Kit.text(content, "", "GameFontHighlight", COL.text, 250)
    flow:add(nameFs, ROW_H)
    local info = Kit.text(content, "", "GameFontHighlightSmall", COL.dim, 320)
    info:SetPoint("LEFT", nameFs, "RIGHT", 6, 0)
    info:SetWordWrap(false)
    nameFs:SetWordWrap(false)
    F.ach[i] = { name = nameFs, info = info, a = a }
  end
  flow:finish()
  return root
end

local function clockStr(sec) return ns.U.fmtDuration(sec) end

function Today.refresh(root)
  local F = root.F
  local db, U, P, H = ns.db, ns.U, ns.Progress, ns.History
  if not db then return end
  local now = ns.now()
  local st = ns.Scheduler.status(db, now, ns.ctx or {})
  local key = Kit.today()
  local day = H.day(db, key)

  F.seated:SetText(L["Seated this stretch: "] .. clockStr(st.seated))
  if not db.settings.enabled then
    F.next:SetText(L["Strong Like Tauren is turned off (Settings > General)."])
  elseif st.restDay then
    F.next:SetText(L["Rest day: no Walkabouts or Feats will nudge you today."])
  elseif st.W then
    F.next:SetText(L["A Walkabout is waiting for you."])
  else
    F.next:SetText(L["Next Walkabout in "] .. clockStr(st.dueIn))
  end

  local rv = st.rage or 0
  local rtext
  if st.restDay then rtext = L["Rest day"]
  elseif st.F then rtext = L["Feat of Strength ready"]
  elseif rv >= 100 and (st.featCooldown or 0) > 0 then
    if db.settings.rage.bank and rv >= ns.C.RAGE_BANK then rtext = L["Double Feat in "] .. clockStr(st.featCooldown)
    elseif db.settings.rage.bank then rtext = L["Feat in "] .. clockStr(st.featCooldown) .. (" \194\183 Rage %d"):format(math.floor(rv))
    else rtext = L["Feat in "] .. clockStr(st.featCooldown) end
  else rtext = ("%d / %d"):format(math.floor(rv + 0.5), db.settings.rage.bank and ns.C.RAGE_BANK or 100) end
  F.rage:Set(math.min(1, rv / 100), rtext)

  local rep = db.prog.rep or 0
  local idx, stand, nextMin = P.standing(rep)
  local frac, rtxt = 1, ("%d"):format(rep)
  if nextMin then
    frac = (rep - stand.min) / (nextMin - stand.min)
    rtxt = ("%d / %d"):format(rep, nextMin)
  end
  F.rep:Set(frac, rtxt)
  F.repLbl:SetText(stand.name .. " - " .. ns.C.FACTION)

  local dn = math.min(day.dn or 0, ns.C.DAILY_GOAL)
  F.daily:Set(dn / ns.C.DAILY_GOAL, (day.dq and (L["Complete"] .. " ") or "") .. ("%d / %d"):format(dn, ns.C.DAILY_GOAL))

  local cur, best = P.currentStreak(db, key), db.prog.streak.best or 0
  F.streak:SetText((L["Streak: %d days"]):format(cur) .. "    " .. (L["Best: %d days"]):format(best))

  F.walks:SetText((L["Walkabouts today: %d due, %d done, %d skipped, %d credited"]):format(
    day.w.due, day.w.done, day.w.skip, day.w.cred))
  F.seatMax:SetText(L["Longest seated stretch today: "] .. clockStr(day.seatMax or 0))
  local rate, n = H.completionRate(db, now, 7, db.settings.dayStart)
  if rate then
    F.rate:SetText((L["7-day completion rate: %d%% (%d breaks)"]):format(math.floor(rate * 100 + 0.5), n))
    F.hint:SetText(rate < 0.6 and L["Try a lower tier? Settings > Intensity makes everything gentler. Skipping is always fine."] or "")
  else
    F.rate:SetText(L["7-day completion rate: no data yet"])
    F.hint:SetText("")
  end

  local ids = {}
  for x in pairs(day.ex) do ids[#ids + 1] = x end
  table.sort(ids)
  for i, fs in ipairs(F.exRows) do
    local x = ids[i]
    if x then
      local def = ns.env.byId[x]
      local e = day.ex[x]
      fs:SetText(("%s: %s  (x%d)"):format(def and ns.Library.displayName(def) or x, Kit.amountStr(def, e.a), e.n))
    elseif i == 1 then
      fs:SetText(L["Nothing logged yet today."])
    else
      fs:SetText("")
    end
  end

  for _, r in ipairs(F.ach) do
    local a, got = r.a, db.prog.ach[r.a.id]
    if got then
      r.name:SetText("[x] " .. a.name)
      r.name:SetTextColor(COL.green[1], COL.green[2], COL.green[3])
      r.info:SetText(L["Earned "] .. U.date("%Y-%m-%d", got) .. " - " .. a.desc)
    else
      local p = P.achievementProgress(db, a)
      r.name:SetText("[ ] " .. a.name)
      r.name:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
      r.info:SetText(("%d / %d - %s"):format(math.floor(p), a.n, a.desc))
    end
  end
  F.rest:Refresh()
end
