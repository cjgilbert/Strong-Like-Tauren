local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local Kit = UI.Kit
local COL = Kit.COL

local History = { title = L["History"] }
UI.Tabs.history = History

local MAX_ROWS = 200
local ROW_H = 20

local OUTCOME = {
  done = L["Done"], part = L["Partial"], skip = L["Skipped"], exp = L["Expired"], cred = L["Credited"],
}
local SOURCE = {
  walk = L["Walkabout"], feat = L["Feat"], man = L["Manual"], away = L["Away"], up = L["Got up"], move = L["Move"],
}

local function logExercise(root)
  local F = root.F
  local def = F.defs[F.sel]
  if not def then return end
  local amount = tonumber(F.amount:GetText())
  if not amount or amount <= 0 then
    F.msg:SetText(L["Enter an amount first."])
    return
  end
  local ok, err = ns.Do.manualLog(def.id, amount)
  if ok == false or ok == nil then
    F.msg:SetText(err and tostring(err) or L["That didn't work."])
    F.msg:SetTextColor(COL.red[1], COL.red[2], COL.red[3])
  else
    F.msg:SetText(L["Logged: "] .. ns.Library.displayName(def))
    F.msg:SetTextColor(COL.green[1], COL.green[2], COL.green[3])
  end
  History.refresh(root)
end

local function chooseExercise(root, idx)
  local F = root.F
  F.defs = ns.env.defs
  local n = #F.defs
  if n == 0 then return end
  F.sel = ((idx - 1) % n) + 1
  local def = F.defs[F.sel]
  F.exName:SetText(ns.Library.displayName(def))
  F.unit:SetText(def.kind == "s" and L["seconds"] or L["reps"])
  F.amount:SetText(tostring(def.std))
end

function History.build(parent)
  local root = CreateFrame("Frame", nil, parent)
  local F = { filter = "today", sel = 1, defs = {} }
  root.F = F

  -- Log form
  local formTitle = Kit.text(root, L["Log exercise"], "GameFontNormal", COL.gold)
  formTitle:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -2)
  local prev = Kit.button(root, "<", 24, 22, function() chooseExercise(root, F.sel - 1) end)
  prev:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -22)
  F.exName = Kit.text(root, "", "GameFontHighlight", COL.text, 300, "CENTER")
  F.exName:SetPoint("LEFT", prev, "RIGHT", 4, 0)
  F.exName:SetWordWrap(false)
  local nxt = Kit.button(root, ">", 24, 22, function() chooseExercise(root, F.sel + 1) end)
  nxt:SetPoint("LEFT", prev, "RIGHT", 308, 0)
  F.amount = Kit.edit(root, 54, 22, true)
  F.amount:SetPoint("LEFT", nxt, "RIGHT", 12, 0)
  F.unit = Kit.text(root, "", "GameFontHighlightSmall", COL.dim, 50)
  F.unit:SetPoint("LEFT", F.amount, "RIGHT", 6, 0)
  local logBtn = Kit.button(root, L["Log"], 60, 22, function() logExercise(root) end)
  logBtn:SetPoint("LEFT", F.unit, "RIGHT", 4, 0)
  F.msg = Kit.text(root, "", "GameFontHighlightSmall", COL.dim, 560)
  F.msg:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -48)

  -- Filter
  F.seg = Kit.segmented(root, {
    { "today", L["Today"] }, { "week", L["7 days"] }, { "all", L["All"] },
  }, function() return F.filter end, function(v) F.filter = v; History.refresh(root) end, 300)
  F.seg:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -64)
  F.count = Kit.text(root, "", "GameFontHighlightSmall", COL.dim, 280, "RIGHT")
  F.count:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8, -70)

  -- Column headings
  local heads = { { L["When"], 4 }, { L["Exercise"], 92 }, { L["Amount"], 282 }, { L["Outcome"], 346 }, { L["Source / who"], 420 } }
  for _, h in ipairs(heads) do
    local fs = Kit.text(root, h[1], "GameFontNormalSmall", COL.gold, 120)
    fs:SetPoint("TOPLEFT", root, "TOPLEFT", h[2], -96)
  end

  local scroll, content = Kit.scroll(root, 616, 300)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -112)
  F.content = content
  F.rows = {}
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(588, ROW_H)
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    if i % 2 == 0 then
      local bg = r:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(1, 1, 1, 0.04)
    end
    local function col(x, w)
      local fs = Kit.text(r, "", "GameFontHighlightSmall", COL.text, w)
      fs:SetPoint("LEFT", r, "LEFT", x, 0)
      fs:SetWordWrap(false)
      return fs
    end
    r.t = col(4, 86)
    r.x = col(92, 186)
    r.a = col(282, 60)
    r.o = col(346, 70)
    r.s = col(420, 130)
    r.del = Kit.button(r, "x", 20, 18)
    r.del:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    Kit.tip(r.del, L["Delete this entry"])
    -- The exercise column is a fixed single line; the tooltip shows the full name.
    r:EnableMouse(true)
    r:HookScript("OnEnter", function(self)
      if GameTooltip and self.fullName then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.fullName, 1, 1, 1, 1, true)
        GameTooltip:Show()
      end
    end)
    r:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.del:SetScript("OnClick", function()
      local id = r.rowId
      if not id then return end
      Kit.confirm(L["Delete this log entry? Totals will be corrected."], function()
        ns.Do.deleteRow(id)
        History.refresh(root)
      end)
    end)
    r:Hide()
    F.rows[i] = r
  end
  F.empty = Kit.text(content, L["Nothing here yet. Go for a Walkabout!"], "GameFontHighlight", COL.dim, 560)
  F.empty:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)

  chooseExercise(root, 1)
  return root
end

function History.refresh(root)
  local F = root.F
  local db, U = ns.db, ns.U
  if not db then return end
  F.seg:Refresh()
  if #F.defs ~= #ns.env.defs then chooseExercise(root, F.sel) end
  local now = ns.now()
  local today = Kit.today()
  local rows = db.log.rows
  local shown, total = 0, 0
  for i = #rows, 1, -1 do
    local row = rows[i]
    local ok = true
    if F.filter == "today" then ok = (row.d == today)
    elseif F.filter == "week" then ok = (row.t >= now - 7 * 86400) end
    if ok then
      total = total + 1
      if shown < MAX_ROWS then
        shown = shown + 1
        local r = F.rows[shown]
        local def = ns.env.byId[row.x]
        r.rowId = row.id
        r.t:SetText(U.date("%m-%d %H:%M", row.t))
        r.fullName = def and ns.Library.displayName(def) or tostring(row.x)
        r.x:SetText(r.fullName)
        local amt = (row.o == "skip" or row.o == "exp" or row.o == "cred") and "-" or Kit.amountStr(def, row.a, row.k)
        r.a:SetText(amt)
        r.o:SetText(OUTCOME[row.o] or tostring(row.o))
        local who = row.c and ns.DB.charName(db, row.c)
        r.s:SetText((SOURCE[row.s] or tostring(row.s or "")) .. (who and (" - " .. who) or ""))
        r:Show()
      end
    end
  end
  for i = shown + 1, MAX_ROWS do F.rows[i]:Hide() end
  F.empty:SetShown(shown == 0)
  F.content:SetHeight(math.max(10, shown * ROW_H + 6))
  if total > shown then
    F.count:SetText((L["Showing newest %d of %d"]):format(shown, total))
  else
    F.count:SetText((L["%d entries"]):format(total))
  end
end
