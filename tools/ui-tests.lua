-- UI-level regression tests under the fake WoW API: luajit tools/ui-tests.lua
-- Loads the whole addon (like tools/smoke.lua), then drives the real Totem / Toast / Prompts frames by firing their
-- OnClick scripts and asserts that what is on screen always matches the live queue.
local script = arg and arg[0] or "tools/ui-tests.lua"
local dir = script:gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local root = dir .. "/.."
local ADDON = "StrongLikeTauren"

local stub = dofile(dir .. "/wowstub.lua")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1 print("FAIL  " .. label) end
end

local ns
local function boot(keep, pew)
  stub.frames, stub.timers = {}, {}
  if not keep then _G.StrongLikeTaurenDB, _G.StrongLikeTaurenCharDB = nil, nil end -- fresh saved variables per scenario
  ns = {}
  for line in io.lines(root .. "/" .. ADDON .. ".toc") do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local path = root .. "/" .. line:gsub("\\", "/")
      local fh = io.open(path, "rb")
      if fh then
        fh:close()
        assert(loadfile(path))(ADDON, ns)
      end
    end
  end
  local function fire(event, ...)
    for _, f in ipairs({ unpack(stub.frames) }) do
      local h = f._scripts.OnEvent
      if h and f._events[event] then h(f, event, ...) end
    end
  end
  fire("ADDON_LOADED", ADDON)
  fire("PLAYER_LOGIN")
  if pew then fire("PLAYER_ENTERING_WORLD", table.unpack and table.unpack(pew) or unpack(pew)) end
  assert(ns.ready, "addon did not become ready")
  ns.db.settings.firstRun = false
  ns.db.settings.nudge.center = false
  stub.chat = {}
end

-- Queue fixtures -----------------------------------------------------------------------------------------------
local function slot(x, a, extra)
  local s = { x = x, a = a, l = 1, u = a, p = 100 }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local function addFeat()
  local Q = ns.db.queue
  local it = { id = ns.Queue.newId(Q), k = "F", t = ns.now(), exp = ns.now() + 86400, bonus = 0, flavor = "quest",
               slots = { slot("squat", 15), slot("twist", 20) } }
  Q.items[#Q.items + 1] = it
  return it
end
local function addWalk()
  local Q = ns.db.queue
  local it = { id = ns.Queue.newId(Q), k = "W", t = ns.now(), min = 2, rooted = 0,
               slots = { slot("walk", 120, { walk = true }) } }
  table.insert(Q.items, 1, it)
  return it
end

-- Screen readers -------------------------------------------------------------------------------------------------
local function totemRows()
  local out = {}
  for _, f in ipairs(stub.frames) do
    if f._parent == ns.UI.Totem.frame and f.done and f.name then out[#out + 1] = f end
  end
  return out
end
local function visibleRows()
  local out = {}
  for _, r in ipairs(totemRows()) do
    if r._shown then out[#out + 1] = r end
  end
  return out
end
local function click(btn, mouse) btn._scripts.OnClick(btn, mouse or "LeftButton") end
local function rowFor(pattern)
  for _, r in ipairs(visibleRows()) do
    if r.name._text:find(pattern) then return r end
  end
end
local function toastShown() return _G.StrongLikeTaurenToast and _G.StrongLikeTaurenToast._shown end
local function toastText()
  local t = {}
  if _G.StrongLikeTaurenToast then
    for _, fs in ipairs(_G.StrongLikeTaurenToast.lines) do
      if fs._text and fs._text ~= "" then t[#t + 1] = fs._text end
    end
  end
  return table.concat(t, "\n")
end
local function toastSlotCount()
  local n = 0
  if _G.StrongLikeTaurenToast then
    for _, fs in ipairs(_G.StrongLikeTaurenToast.lines) do
      if fs._text and fs._text ~= "" then n = n + 1 end
    end
  end
  return n
end
local function lastHeight(f) return f._heights and f._heights[#f._heights] end
local function historyDone(x)
  local n = 0
  for _, r in ipairs(ns.db.log.rows) do
    if r.o == "done" and (not x or r.x == x) then n = n + 1 end
  end
  return n
end
local function pendingCount()
  local n = 0
  for _, it in ipairs(ns.Queue.list(ns.db.queue)) do
    for _, sl in ipairs(it.slots) do if not sl.o then n = n + 1 end end
  end
  return n
end

-- The invariant behind every scenario: every visible display agrees with the live queue.
local function consistent(label)
  check(#visibleRows() == pendingCount(), label .. ": visible Totem rows (" .. #visibleRows() .. ") == pending slots ("
    .. pendingCount() .. ")")
  if toastShown() then
    local n = toastSlotCount()
    check(pendingCount() > 0, label .. ": Toast still visible with nothing pending")
    check(n == pendingCount(), label .. ": Toast lists " .. n .. " line(s), pending is " .. pendingCount())
  end
end

local function scenario(name, withWalk, toastFirst)
  print("-- " .. name)
  boot()
  local W = withWalk and addWalk() or nil
  local F = addFeat()
  ns.UI.Totem:Show()
  ns.UI.refreshAll()
  if toastFirst then ns.UI.Toast:Show(W, F, "login") end
  check(#visibleRows() == (withWalk and 3 or 2), name .. ": initial rows")
  if toastFirst then
    check(toastShown() and toastText():find("Whirlwind") and toastText():find("Kodo Squats"), name .. ": toast lists both")
  end

  local r1 = rowFor("Kodo Squats")
  check(r1 ~= nil, name .. ": Kodo Squats row")
  click(r1.done)
  ns.UI.Totem:Refresh()
  consistent(name .. " after 1st Done")
  check(rowFor("Kodo Squats") == nil, name .. ": Kodo row gone after its Done")
  check(historyDone("squat") >= 1, name .. ": squat logged")

  local r2 = rowFor("Whirlwind")
  check(r2 ~= nil, name .. ": Whirlwind row")
  click(r2.done)
  ns.UI.Totem:Refresh()
  consistent(name .. " after 2nd Done")

  check(ns.Queue.get(ns.db.queue, "F") == nil, name .. ": no F item left in queue")
  check(rowFor("Kodo") == nil and rowFor("Whirlwind") == nil, name .. ": no Feat rows left on Totem")
  for _, r in ipairs(visibleRows()) do
    check(r.kind._text ~= "Feat of Strength", name .. ": no visible Feat row")
  end
  check(not (toastShown() and (toastText():find("Kodo") or toastText():find("Whirlwind"))),
    name .. ": toast does not list resolved slots")
  check(historyDone("squat") >= 1 and historyDone("twist") == 1, name .. ": history has both Feat exercises done")
  local undo = _G.StrongLikeTaurenPromptUndo
  check(undo and undo._shown and undo.text._text:find("Whirlwind"), name .. ": Undo toast is for Whirlwind")
end

scenario("feat only", false, false)
scenario("feat + walkabout", true, false)
scenario("feat, toast shown first", false, true)
scenario("feat + walkabout, toast shown first", true, true)

-- A Skip on the toast after everything was resolved must not log anything extra.
print("-- toast Skip after resolve")
boot()
local F = addFeat()
ns.UI.Totem:Show()
ns.UI.Toast:Show(nil, F, "login")
click(rowFor("Kodo Squats").done)
click(rowFor("Whirlwind").done)
local rowsBefore = #ns.db.log.rows
if toastShown() then click(_G.StrongLikeTaurenToast.skip) end
check(#ns.db.log.rows == rowsBefore, "toast Skip after resolve logs nothing")

-- Toast refreshes through ns.UI.refreshAll when a slot is resolved elsewhere.
print("-- toast follows the queue")
boot()
F = addFeat()
ns.UI.Totem:Show()
ns.UI.Toast:Show(nil, F, "login")
ns.Do.skip(F.id, 1)
check(toastShown() and not toastText():find("Kodo") and toastText():find("Whirlwind"), "toast drops a skipped slot")
ns.Do.skip(F.id, 2)
check(not toastShown(), "toast hides when nothing it listed is pending")

-- Long exercise names must reach the toast whole (never cut to fit), and the toast grows with its content.
print("-- toast shows full names")
boot()
local W2 = addWalk()
W2.slots = { slot("shuffle", 120, { walk = true }) }
local F2 = addFeat()
F2.slots = { slot("climbers", 20) }
ns.UI.Totem:Show()
ns.UI.Toast:Show(W2, nil, "login")
local toast = _G.StrongLikeTaurenToast
local shuffle, climbers = ns.env.byId.shuffle, ns.env.byId.climbers
check(toast.lines[1]._text:find(shuffle.pun, 1, true) and toast.lines[1]._text:find(shuffle.name, 1, true),
  "toast has full Hoof & Squat Shuffle pun and name")
check(toast.lines[1]._wrap ~= false, "toast line wraps rather than truncating")
local h1 = lastHeight(toast)
ns.UI.Toast:Show(W2, F2, "login")
check(toast.lines[2]._text:find(climbers.pun, 1, true) and toast.lines[2]._text:find(climbers.name, 1, true),
  "toast has full Thunder Bluff Climbers pun and name")
check(lastHeight(toast) > h1, "toast height grows with more lines (" .. tostring(h1) .. " -> " .. tostring(lastHeight(toast)) .. ")")
-- a long custom name (40 + 40 bytes) wraps into more height than a short one
local long = { id = "longx", name = ("N"):rep(40), pun = ("P"):rep(40), kind = "r", std = 10, lo = 1, hi = 20 }
ns.env.byId.longx = long
F2.slots = { slot("longx", 10) }
ns.UI.Toast:Show(nil, F2, "login")
local h3 = lastHeight(toast)
check(toast.lines[1]._text:find(long.pun, 1, true) and toast.lines[1]._text:find(long.name, 1, true), "toast keeps a 40+40 byte name whole")
F2.slots = { slot("squat", 10) }
ns.UI.Toast:Show(nil, F2, "login")
check(h3 > lastHeight(toast), "toast is taller for a long name than a short one")
ns.env.byId.longx = nil

-- Close buttons: X and OK are neutral; nothing changes in history, rep or queue.
print("-- close buttons")
local function snapshot()
  local n = 0
  for _, it in ipairs(ns.Queue.list(ns.db.queue)) do for _, sl in ipairs(it.slots) do n = n + 1; if sl.o then n = n + 100 end end end
  return #ns.db.log.rows .. "|" .. tostring(ns.db.prog.rep) .. "|" .. n .. "|" .. #ns.db.queue.items
end
boot()
F = addFeat()
ns.UI.Totem:Show()
ns.UI.refreshAll()
click(rowFor("Kodo Squats").done)
local before = snapshot()
undo = _G.StrongLikeTaurenPromptUndo
check(undo and undo._shown, "undo prompt shown")
check(undo.b1._text == "Undo" and undo.b2._text == "OK" and undo.b2._shown, "undo prompt has Undo and OK")
click(undo.b2)
check(not undo._shown and snapshot() == before, "Undo prompt OK hides and changes nothing")
click(rowFor("Whirlwind").done)
before = snapshot()
undo = _G.StrongLikeTaurenPromptUndo
check(undo._shown, "undo prompt shown again")
click(undo.close)
check(not undo._shown and snapshot() == before, "Undo prompt X hides and changes nothing")

boot()
F = addFeat()
ns.UI.Totem:Show()
ns.UI.Toast:Show(nil, F, "login")
before = snapshot()
click(_G.StrongLikeTaurenToast.close)
check(not toastShown() and snapshot() == before, "toast X hides and changes nothing")

boot()
before = snapshot()
local walks = 0
ns.UI.Prompts:Offer("early")
local offer = _G.StrongLikeTaurenPromptOffer
check(offer and offer._shown, "offer prompt shown")
click(offer.close)
check(not offer._shown and snapshot() == before and not ns.Queue.get(ns.db.queue, "W"), "Offer X does not create a Walkabout")

-- The Totem rep bar shows reputation only: no exercise name, no "Vigor", one fixed color, immediately and after a refresh.
print("-- rep bar after a Walkabout")
boot()
addWalk()
ns.UI.Totem:Show()
ns.UI.refreshAll()
local repBar = ns.UI.Totem.frame.rep
local fixedColor = repBar._color
local walkName = ns.env.byId.walk and ns.env.byId.walk.name
local function checkRepBar(label)
  local txt = repBar.text._text or ""
  local st = ns.C.STANDINGS[ns.Progress.standing(ns.db.prog.rep)]
  check(txt:find(ns.C.FACTION, 1, true) and txt:find(st.name, 1, true), label .. ": rep bar shows faction and standing (" .. txt .. ")")
  check(txt:find(tostring(ns.db.prog.rep), 1, true), label .. ": rep bar shows the rep value (" .. txt .. ")")
  check(not txt:find("Vigor", 1, true) and not (walkName and txt:find(walkName, 1, true)), label .. ": rep bar has no exercise/buff name")
  local c = repBar._color
  local g = ns.UI.Theme and ns.UI.Theme.C and ns.UI.Theme.C.gold
  check(c and fixedColor and c[1] == fixedColor[1] and c[2] == fixedColor[2] and c[3] == fixedColor[3], label .. ": rep bar color is fixed")
  check(not (g and c) or (c[1] == g[1] and c[2] == g[2] and c[3] == g[3]), label .. ": rep bar color is the rep color")
end
click(visibleRows()[1].done)
check(ns.db.prog.rep == ns.C.REP.walk, "walkabout Done awarded rep")
checkRepBar("right after Done")
ns.UI.Totem:Refresh()
checkRepBar("after refresh")
ns.UI.refreshAll()
checkRepBar("after refreshAll")

-- Login after the game was closed: the seated clock must not carry the old stretch or the offline gap.
local function seatText() return ns.UI.Totem.frame.seat.text._text or "" end
local function loginScenario(label, offline, acc, pew, expectMin, expectMax)
  print("-- " .. label)
  boot()
  local saved = _G.StrongLikeTaurenDB
  saved.body.acc = acc
  saved.body.lastTick = os.time() - offline
  boot(true, pew) -- same saved variables: ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD
  ns.UI.Totem:Show()
  ns.UI.Totem:Refresh()
  local shown = ns.Scheduler.seatedNow(ns.db, ns.now(), ns.ctx)
  check(shown >= expectMin and shown <= expectMax, label .. ": seatedNow " .. shown .. " not in [" .. expectMin .. "," .. expectMax .. "]")
  return seatText()
end
local txt = loginScenario("login after 2 h with acc 37 min", 7200, 37 * 60, { true, false }, 0, 20)
check(txt:find("Seated 0:0"), "login after 2 h: Totem shows 0:0x immediately (" .. txt .. ")")
txt = loginScenario("login after 5 min with acc 37 min", 300, 37 * 60, { true, false }, 37 * 60, 37 * 60 + 20)
check(txt:find("Seated 37:"), "login after 5 min: Totem shows 37:xx, not +5 min (" .. txt .. ")")
txt = loginScenario("/reload with acc 37 min", 4, 37 * 60, { false, true }, 37 * 60, 37 * 60 + 20)
check(txt:find("Seated 37:"), "/reload keeps counting (" .. txt .. ")")

print(("ui-tests: %d passed, %d failed"):format(passed, failed))
print(failed == 0 and "UI TESTS OK" or ("UI TESTS: " .. failed .. " failure(s)"))
os.exit(failed == 0 and 0 or 1)
