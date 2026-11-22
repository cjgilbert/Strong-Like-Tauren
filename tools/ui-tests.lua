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
local function toastText() return _G.StrongLikeTaurenToast and _G.StrongLikeTaurenToast.text._text or "" end
local function toastSlotCount()
  local t = toastText()
  if t == "" then return 0 end
  local n = 1
  for _ in t:gmatch(" \194\183 ") do n = n + 1 end
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

-- Buttons on the toast after everything was resolved must not log anything extra.
print("-- toast buttons after resolve")
boot()
local F = addFeat()
ns.UI.Totem:Show()
ns.UI.Toast:Show(nil, F, "login")
click(rowFor("Kodo Squats").done)
click(rowFor("Whirlwind").done)
local rowsBefore = #ns.db.log.rows
check(not toastShown(), "toast is gone once everything it listed is done")
check(#ns.db.log.rows == rowsBefore, "toast after resolve logs nothing")

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
check(toast.text._text:find(shuffle.pun, 1, true), "toast has the full Hoof & Squat Shuffle name")
check(toast.text._wrap ~= false, "toast line wraps rather than truncating")
local h1 = lastHeight(toast)
ns.UI.Toast:Show(W2, F2, "login")
check(toast.text._text:find(shuffle.pun, 1, true) and toast.text._text:find(climbers.pun, 1, true),
  "toast has both full names")
check(lastHeight(toast) > h1, "toast height grows with more lines (" .. tostring(h1) .. " -> " .. tostring(lastHeight(toast)) .. ")")
-- a long custom name (40 + 40 bytes) wraps into more height than a short one
local long = { id = "longx", name = ("N"):rep(40), pun = ("P"):rep(60), kind = "r", std = 10, lo = 1, hi = 20 }
ns.env.byId.longx = long
F2.slots = { slot("longx", 10) }
ns.UI.Toast:Show(nil, F2, "login")
local h3 = lastHeight(toast)
check(toast.text._text:find(long.pun, 1, true), "toast keeps a 60 byte name whole")
F2.slots = { slot("squat", 10) }
ns.UI.Toast:Show(nil, F2, "login")
check(h3 > lastHeight(toast), "toast is taller for a long name than a short one")
ns.env.byId.longx = nil

-- The compact reminder: title, one line, sound once, 10 s auto-close, X, Snooze 10.
print("-- compact reminder")
local plays, flashes = 0, 0
local lastSound, lastChannel
_G.PlaySound = function(id, ch) plays = plays + 1 lastSound, lastChannel = id, ch end
_G.FlashClientIcon = function() flashes = flashes + 1 end
boot()
local W3 = addWalk()
ns.UI.Totem:Show()
ns.UI.refreshAll()
local qBefore = #ns.db.queue.items .. "|" .. pendingCount()
ns.dispatch({ { t = "toast", w = W3, f = nil, moment = "tick" } })
local rem = _G.StrongLikeTaurenToast
check(rem and rem._shown, "due Walkabout shows the compact notification")
check(rem.title._text == "Walkabout time!", "title is Walkabout time! (" .. tostring(rem.title._text) .. ")")
check(rem.text._text:find(ns.env.byId.walk.pun, 1, true) and rem.text._text:find("2:00", 1, true),
  "line names the exercise and time (" .. tostring(rem.text._text) .. ")")
check(rem.go._text == "Let's go" and rem.snooze._text == "Snooze 10" and rem.close, "Let's go, Snooze 10 and X exist")
check(not rem.skip, "no Skip button")
check(plays == 1 and flashes == 1, "sound plays once and taskbar flashes once (" .. plays .. "/" .. flashes .. ")")
stub.clock = stub.clock + 9
rem._scripts.OnUpdate(rem, 9)
check(rem._shown, "still shown after 9 s")
stub.clock = stub.clock + 2
rem._scripts.OnUpdate(rem, 2)
check(not rem._shown, "auto-closes after 10 s")
check(#ns.db.queue.items .. "|" .. pendingCount() == qBefore and ns.Queue.get(ns.db.queue, "W") ~= nil,
  "auto-close leaves the queue unchanged")
ns.UI.refreshAll()
check(#visibleRows() == 1, "Walkabout still in the Totem after auto-close")
-- feat title and both
ns.UI.Toast:Show(nil, addFeat(), "tick")
check(rem.title._text == "Feat of Strength!", "feat-only title")
ns.UI.Toast:Show(W3, ns.Queue.get(ns.db.queue, "F"), "tick")
check(rem.title._text:find("Walkabout") and rem.title._text:find("Feat"), "both title")
-- sound off
ns.db.settings.nudge.sound = false
plays = 0
ns.dispatch({ { t = "toast", w = W3, f = nil, moment = "tick" } })
check(plays == 0, "no sound when settings.nudge.sound is false")
ns.db.settings.nudge.sound = true
-- Snooze 10
ns.dispatch({ { t = "toast", w = W3, f = nil, moment = "tick" } })
click(rem.snooze)
check(not rem._shown and ns.db.nudge.snoozeUntil and ns.db.nudge.snoozeUntil >= ns.now() + 590, "Snooze 10 snoozes and hides")
check(ns.Queue.get(ns.db.queue, "W") ~= nil, "Snooze keeps the Walkabout queued")

-- Placement, dismissal, hover pause, sounds.
print("-- reminder placement, dismissal and sound")
boot()
local W4 = addWalk()
ns.UI.Totem:Show()
ns.UI.refreshAll()
ns.dispatch({ { t = "toast", w = W4, f = nil, moment = "tick" } })
local r4 = _G.StrongLikeTaurenToast
local pt = r4._points and r4._points[#r4._points]
check(pt and pt[1] == "TOP" and pt[2] == _G.UIParent and pt[3] == "TOP" and pt[5] < 0, "reminder is anchored to UIParent TOP")
local inSpecial = false
for _, n in ipairs(_G.UISpecialFrames) do if n == "StrongLikeTaurenToast" then inSpecial = true end end
check(inSpecial, "reminder is in UISpecialFrames (Escape closes it)")
local snap4 = #ns.db.queue.items .. "|" .. pendingCount()
r4._scripts.OnMouseUp(r4, "LeftButton")
check(not r4._shown and #ns.db.queue.items .. "|" .. pendingCount() == snap4, "body click dismisses without changing the queue")
ns.UI.refreshAll()
check(#visibleRows() == 1, "dismissed reminder leaves the item in the Totem")
-- Escape path: the game calls Hide() on registered frames
ns.dispatch({ { t = "toast", w = W4, f = nil, moment = "tick" } })
r4:Hide()
check(not r4._shown and ns.Queue.get(ns.db.queue, "W") ~= nil, "Escape (Hide) closes it and keeps the queue")
-- hover pauses the countdown
ns.dispatch({ { t = "toast", w = W4, f = nil, moment = "tick" } })
r4.IsMouseOver = function() return true end
stub.clock = stub.clock + 20
r4._scripts.OnUpdate(r4, 20)
check(r4._shown, "mouse-over pauses the auto-close")
r4.IsMouseOver = nil
stub.clock = stub.clock + 9
r4._scripts.OnUpdate(r4, 9)
check(r4._shown, "still shown 9 s after the mouse left")
stub.clock = stub.clock + 2
r4._scripts.OnUpdate(r4, 2)
check(not r4._shown, "auto-closes 10 s after the mouse left")
-- sounds: every name gets a distinct id so the expected SOUNDKIT entry can be told apart
local ids = { READY_CHECK = 11, RAID_WARNING = 12, UI_RAID_BOSS_WHISPER_WARNING = 13, IG_QUEST_LIST_COMPLETE = 14,
              IG_QUEST_LIST_OPEN = 15, IG_MAINMENU_OPEN = 16 }
local function setKit() for k, v in pairs(ids) do _G.SOUNDKIT[k] = v end end
local function soundFor(kind)
  setKit()
  ns.db.settings.nudge.sound = true
  ns.db.settings.nudge.soundKind = kind
  plays, lastSound, lastChannel = 0, nil, nil
  ns.dispatch({ { t = "toast", w = W4, f = nil, moment = "tick" } })
  return lastSound
end
check(ns.db.settings.nudge.soundKind == "alert", "default soundKind is alert")
check(soundFor("alert") == ids.READY_CHECK and plays == 1 and lastChannel == "Master", "alert plays READY_CHECK on Master")
check(soundFor("horn") == ids.RAID_WARNING, "horn plays RAID_WARNING")
check(soundFor("chime") == ids.UI_RAID_BOSS_WHISPER_WARNING, "chime plays UI_RAID_BOSS_WHISPER_WARNING")
check(soundFor("menu") == ids.IG_QUEST_LIST_OPEN, "menu plays IG_QUEST_LIST_OPEN")
_G.SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING = nil
ns.db.settings.nudge.soundKind = "chime"
lastSound = nil
ns.nudgeSound()
check(lastSound == ids.IG_QUEST_LIST_COMPLETE, "chime falls back to IG_QUEST_LIST_COMPLETE")
_G.SOUNDKIT.IG_QUEST_LIST_COMPLETE = nil
lastSound = nil
ns.nudgeSound()
check(lastSound == ids.READY_CHECK, "chime falls back to READY_CHECK when nothing else exists")
_G.SOUNDKIT.RAID_WARNING = nil
ns.db.settings.nudge.soundKind = "horn"
lastSound = nil
ns.nudgeSound()
check(lastSound == ids.READY_CHECK, "horn falls back to READY_CHECK when RAID_WARNING is missing")
setKit()
ns.db.settings.nudge.sound = false
plays = 0
ns.dispatch({ { t = "toast", w = W4, f = nil, moment = "tick" } })
check(plays == 0, "sound off plays nothing")
ns.db.settings.nudge.sound = true
-- Settings Test button path: plays even with sounds off and shows a sample reminder
plays = 0
r4:Hide()
ns.UI.Toast:Sample()
ns.nudgeSound(true)
check(r4._shown and plays == 1 and r4.text._text:find("Kodo Squats", 1, true), "Test shows a sample reminder and plays the sound")
ns.UI.refreshAll()
check(r4._shown, "sample reminder survives a refresh")
r4:Hide()

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

-- Pause seated clock / I got up buttons.
print("-- pause and I got up buttons")
boot()
ns.UI.Totem:Show()
ns.UI.Totem:Refresh()
local realServerTime, offset = _G.GetServerTime, 0
_G.GetServerTime = function() return realServerTime() + offset end
local function fireEvent(event, ...)
  for _, f in ipairs({ unpack(stub.frames) }) do
    local h = f._scripts.OnEvent
    if h and f._events[event] then h(f, event, ...) end
  end
end
local function chatHas(p)
  for _, l in ipairs(stub.chat) do if tostring(l):find(p, 1, true) then return true end end
end
ns.db.body.acc = 125
ns.db.body.lastTick = ns.now()
local tf2 = ns.UI.Totem.frame
check(tf2.pause and tf2.gotUp, "Totem has Pause and I got up buttons")
click(tf2.pause)
check(ns.db.body.paused, "pause click stores body.paused")
check((ns.UI.Totem.frame.seat.text._text or ""):find("Paused 2:05"), "bar says Paused 2:05 (" .. tostring(tf2.seat.text._text) .. ")")
offset = 3
fireEvent("GLOBAL_MOUSE_DOWN")
check(ns.db.body.paused, "input at +3 s: still paused")
offset = 6
fireEvent("GLOBAL_MOUSE_DOWN")
check(not ns.db.body.paused, "input at +6 s: resumed")
check(chatHas("Welcome back! Seated clock resumed."), "auto-resume prints a chat line")
check((tf2.seat.text._text or ""):find("Seated 2:0"), "bar is back to Seated (" .. tostring(tf2.seat.text._text) .. ")")
-- cursor movement polled every second while paused
click(tf2.pause)
offset = offset + 7
local curX = 500
_G.GetCursorPosition = function() curX = curX + 10 return curX, 400 end
ns.Events.pausePoll() -- grace over (7 s): movement resumes
check(not ns.db.body.paused, "cursor movement after the grace period resumes")
-- I got up
ns.db.body.acc = 900
click(tf2.pause)
click(tf2.gotUp)
check(not ns.db.body.paused and ns.db.body.acc == 0, "I got up clears pause and resets the clock")
check((tf2.seat.text._text or ""):find("Seated 0:0"), "seated text 0:00 after I got up (" .. tostring(tf2.seat.text._text) .. ")")
_G.GetServerTime = realServerTime

-- Collapse / expand button on the Totem.
print("-- collapse button")
boot()
addFeat()
ns.UI.Totem:Show()
ns.UI.refreshAll()
local tf = ns.UI.Totem.frame
local expandedH = tf._h
check(#visibleRows() == 2 and not ns.db.settings.totem.collapsed, "collapse: starts expanded with 2 rows")
click(tf.collapse)
check(ns.db.settings.totem.collapsed == true, "collapse: click sets the setting")
check(#visibleRows() == 0, "collapse: rows hidden")
check(tf._h < expandedH, "collapse: frame shrinks to the header (" .. tostring(expandedH) .. " -> " .. tostring(tf._h) .. ")")
check(tf.collapse._text == "+", "collapse: button shows +")
ns.UI.Totem:Refresh(); ns.UI.refreshAll()
check(#visibleRows() == 0 and ns.db.settings.totem.collapsed == true, "collapse: survives Refresh")
click(tf.collapse)
check(ns.db.settings.totem.collapsed == false and #visibleRows() == 2 and tf._h == expandedH, "collapse: click again expands")
ns.UI.Totem:Refresh()
check(#visibleRows() == 2, "collapse: expanded survives Refresh")

-- Snooze hides everything; the end comes back like a normal reminder.
print("-- snooze hides and returns")
boot()
do
  local base = realServerTime()
  local soff = 0
  _G.GetServerTime = function() return base + soff end
  setKit()
  ns.db.settings.nudge.soundKind = "horn"
  ns.db.settings.nudge.sound = true
  local W = addWalk(); addFeat()
  ns.UI.Totem:Show(); ns.UI.refreshAll()
  check(#visibleRows() == 3, "snooze: 3 rows before")
  local row = rowFor("Walk") or visibleRows()[1]
  click(row.snooze)
  local menu = _G.StrongLikeTaurenSnoozeMenu
  click(menu.btns[2]) -- 10 min
  check(#visibleRows() == 0, "snooze: no Totem rows while snoozed")
  ns.dispatch({ { t = "toast", w = W, f = nil, moment = "tick" } })
  ns.UI.refreshAll()
  check(not toastShown(), "snooze: reminder hidden while snoozed")
  plays = 0
  for _ = 1, 41 do soff = soff + 15; ns.ctx.lastInput = ns.now(); ns.Do.tick() end
  check(#visibleRows() == 3, "snooze end: rows visible again")
  check(toastShown() and plays >= 1 and lastSound == ids.RAID_WARNING, "snooze end: reminder shown with the horn")
  -- until I leave
  ns.UI.Toast:Hide()
  ns.ctx.inst = "party"
  ns.UI.refreshAll()
  check(#visibleRows() == 3, "inst: rows visible before snoozing")
  ns.Do.snoozeInstance()
  check(#visibleRows() == 0, "inst: rows hidden after 'until I leave'")
  ns.ctx.inst = "none"
  ns.Do.moment("leave")
  check(#visibleRows() == 3, "inst: rows return on leave")
  _G.GetServerTime = realServerTime
end

-- Sticky quiet flags heal themselves --------------------------------------------------------------------------
print("-- stuck quiet flags")
do
  local base = realServerTime() + 5000
  local soff = 0
  _G.GetServerTime = function() return base + soff end
  boot()
  if _G.StrongLikeTaurenToast then _G.StrongLikeTaurenToast._shown = false end -- stale frame from an earlier scenario
  local E = ns.Events
  local function fire(ev, ...) E.frame._scripts.OnEvent(E.frame, ev, ...) end
  local function advance(sec) soff = soff + sec end
  local function poll() ns.ctx.lastInput = ns.now(); E.poll() end
  local function open() ns.ctx.settleUntil = 0; ns.ctx.lastInput = ns.now() end
  local function gate() return ns.Scheduler.gate(ns.db, ns.now(), ns.ctx) end
  local saved = { _G.InCinematic, _G.IsInCinematicScene, _G.MovieFrame, _G.CinematicFrame, _G.IsEncounterInProgress,
                  _G.IsInInstance }

  -- movie with no stop event, probe says it is over
  open()
  fire("PLAY_MOVIE")
  check(ns.ctx.cinematic == true and gate().why == "cinematic" and not gate().may, "movie: gate blocks while it plays")
  stub.inCinematic = false
  poll()
  check(ns.ctx.cinematic == false and gate().may and gate().why == nil, "movie: poll with probe 'no' reopens the gate")

  -- a due Walkabout produces a toast once the stuck flag clears
  fire("PLAY_MOVIE")
  addWalk()
  ns.Do.tick()
  check(not toastShown(), "walkabout: no toast while the movie flag is stuck")
  poll(); open()
  ns.Do.tick()
  check(toastShown(), "walkabout: toast appears once the stuck flag has cleared")
  ns.UI.Toast:Hide()

  -- probe unavailable: the 10 minute safety net
  _G.InCinematic, _G.IsInCinematicScene, _G.MovieFrame, _G.CinematicFrame = nil, nil, nil, nil
  check(ns.Api.inCinematic() == nil, "cinematic probe: nil when nothing can tell")
  fire("PLAY_MOVIE")
  advance(599); poll()
  check(ns.ctx.cinematic == true, "movie: still held just before 10 minutes without a probe")
  advance(2); poll()
  check(ns.ctx.cinematic == false, "movie: safety net clears it after 10 minutes")
  _G.InCinematic, _G.IsInCinematicScene, _G.MovieFrame, _G.CinematicFrame = saved[1], saved[2], saved[3], saved[4]

  -- boss fight: leaving the instance clears it
  _G.IsEncounterInProgress = nil
  check(ns.Api.encounterInProgress() == nil, "encounter probe: nil when the function is missing")
  _G.IsInInstance = function() return true, "raid" end
  poll()
  fire("ENCOUNTER_START")
  poll()
  check(ns.ctx.encounter == true and ns.ctx.inst == "raid", "encounter: held inside the raid")
  _G.IsInInstance = saved[6]
  poll()
  check(ns.ctx.inst == "none" and ns.ctx.encounter == false, "encounter: leaving the instance clears it")
  _G.IsInInstance = function() return true, "raid" end
  poll()
  fire("ENCOUNTER_START")
  advance(1801); poll()
  check(ns.ctx.encounter == false, "encounter: safety net clears it after 30 minutes")
  _G.IsInInstance = saved[6]
  poll()
  _G.IsEncounterInProgress = saved[5]
  fire("ENCOUNTER_START")
  poll()
  check(ns.ctx.encounter == false, "encounter: probe 'no' overrides the flag")

  -- loading screen without a DISABLED event
  fire("LOADING_SCREEN_ENABLED")
  advance(119); poll()
  check(ns.ctx.loading == true, "loading: held for under 2 minutes")
  advance(2); poll()
  check(ns.ctx.loading == false, "loading: cleared 2 minutes after it began")
  fire("LOADING_SCREEN_ENABLED")
  fire("PLAYER_ENTERING_WORLD", false, false)
  check(ns.ctx.loading == false, "loading: PLAYER_ENTERING_WORLD clears it")

  -- gate.why, in priority order
  open()
  local function whyOf(mut, setting)
    local ctx = { inst = "none" }
    for k, v in pairs(mut or {}) do ctx[k] = v end
    local old = ns.db.settings.dungeon
    if setting then ns.db.settings.dungeon = setting end
    local g = ns.Scheduler.gate(ns.db, ns.now(), ctx)
    ns.db.settings.dungeon = old
    return g.why, g.may
  end
  local t0 = ns.now()
  check(whyOf({}) == nil and select(2, whyOf({})) == true, "why: nil when open")
  check(whyOf({ combat = true }) == "combat", "why: combat")
  check(whyOf({ encounter = true }) == "encounter", "why: encounter")
  check(whyOf({ loading = true }) == "loading", "why: loading")
  check(whyOf({ dead = true }) == "dead", "why: dead")
  check(whyOf({ cinematic = true }) == "cinematic", "why: cinematic")
  check(whyOf({ settleUntil = t0 + 5 }) == "settling", "why: settling")
  check(whyOf({ inst = "raid" }) == "instance", "why: instance")
  check(whyOf({ inst = "party" }, "hold") == "instance", "why: dungeon hold")
  check(whyOf({ away = true }) == "away", "why: away")
  check(whyOf({ combat = true, cinematic = true }) == "combat", "why: first reason wins")
  ns.db.nudge.snoozeUntil = t0 + 600
  check(whyOf({}) == "snoozed", "why: snoozed")
  ns.db.nudge.snoozeUntil = 0
  ns.db.nudge.pauseUntil = t0 + 600
  check(whyOf({}) == "paused", "why: paused (timed)")
  ns.db.nudge.pauseUntil = 0
  check(whyOf({ pausedSession = true }) == "paused", "why: paused (session)")
  ns.db.settings.enabled = false
  check(whyOf({ combat = true }) == "off", "why: off")
  ns.db.settings.enabled = true

  -- Totem says reminders are on hold
  boot()
  addWalk()
  ns.UI.Totem:Show(); ns.UI.refreshAll()
  local hold = ns.UI.Totem.frame.hold
  check(not hold._shown, "totem hold: nothing shown while reminders can come")
  local h0 = ns.UI.Totem.frame._h
  ns.ctx.pausedSession = true
  ns.UI.refreshAll()
  check(hold._shown and hold._text == "Reminders paused", "totem hold: 'Reminders paused' for a paused session")
  check(ns.UI.Totem.frame._h > h0, "totem hold: extra line reserves its own space")
  ns.ctx.pausedSession = false
  ns.ctx.combat = true
  ns.UI.refreshAll()
  check(hold._shown and hold._text == "Reminder waits: in combat", "totem hold: combat reason")
  ns.ctx.combat = false
  ns.ctx.cinematic = true
  ns.UI.refreshAll()
  check(hold._shown and hold._text == "Reminder waits: cutscene", "totem hold: cutscene reason")
  ns.ctx.cinematic = false
  ns.ctx.settleUntil = 0
  ns.UI.refreshAll()
  check(not hold._shown and ns.UI.Totem.frame._h == h0, "totem hold: line and space go away again")

  _G.GetServerTime = realServerTime
end

-- Rage banking and the ENRAGED! Double Feat -----------------------------------------------------------------------
print("-- banked Rage, Double Feat toast and ENRAGED")
do
  boot()
  setKit()
  local function rageText() return ns.UI.Totem.frame.rage.text._text or "" end
  ns.UI.Totem:Show()
  local now = ns.now()
  ns.db.body.rage.lastFeatAt = now -- cooldown running
  ns.db.body.rage.v = 60
  ns.UI.Totem:Refresh()
  check(rageText() == "Rage 60", "totem: below 100 says 'Rage 60' (" .. rageText() .. ")")
  check(not ns.UI.Totem.frame.rage.over._shown, "totem: no overflow segment below 100")
  ns.db.body.rage.v = 175
  ns.UI.Totem:Refresh()
  check(rageText():find("^Feat in %S+ \194\183 Rage 175$") ~= nil, "totem: 'Feat in ... \194\183 Rage 175' (" .. rageText() .. ")")
  check(ns.UI.Totem.frame.rage.over._shown, "totem: overflow segment shown for 175")
  ns.db.body.rage.v = 200
  ns.UI.Totem:Refresh()
  check(rageText():find("^Double Feat in %S+$") ~= nil, "totem: 'Double Feat in ...' at 200 (" .. rageText() .. ")")
  ns.db.settings.rage.bank = false
  ns.db.body.rage.v = 100
  ns.UI.Totem:Refresh()
  check(rageText():find("^Feat in %S+$") ~= nil and not ns.UI.Totem.frame.rage.over._shown,
    "totem: banking off shows plain 'Feat in ...' (" .. rageText() .. ")")
  ns.db.settings.rage.bank = true

  -- Double Feat item labels and toast
  local Q = ns.db.queue
  local F = { id = ns.Queue.newId(Q), k = "F", t = now, exp = now + 86400, bonus = 0, flavor = "quest", double = true,
              slots = { slot("squat", 15), slot("twist", 20), slot("pushup", 10), slot("plank", 30, { }) } }
  Q.items[#Q.items + 1] = F
  local oldPun = ns.env.byId.squat.pun
  ns.env.byId.squat.pun = nil -- the row only shows the Feat label when there is no separate pun line
  ns.UI.Totem:Show(); ns.UI.refreshAll()
  local sawDouble = false
  for _, r in ipairs(visibleRows()) do
    if r.kind and (r.kind._text or ""):find("Double Feat", 1, true) then sawDouble = true end
  end
  ns.env.byId.squat.pun = oldPun
  check(sawDouble, "totem: rows of a Double Feat are labelled 'Double Feat'")

  if _G.StrongLikeTaurenToast then _G.StrongLikeTaurenToast._shown = false end
  ns.UI.Toast:Show(nil, F, "tick")
  local ts = _G.StrongLikeTaurenToast
  check(ts.title._text == "ENRAGED! Double Feat of Strength", "toast: Double Feat title (" .. tostring(ts.title._text) .. ")")
  check(ts.sub._shown and (ts.sub._text or ""):find("twice the exercises", 1, true), "toast: subtitle line for a Double Feat")
  check(ts.glowKind == "enraged", "toast: red-orange glow for a Double Feat")
  check(toastSlotCount() == 4, "toast: lists all 4 exercises (" .. toastSlotCount() .. ")")
  local W = addWalk()
  ns.UI.Toast:Show(W, F, "tick")
  check(ts.title._text == "Walkabout & ENRAGED Double Feat!", "toast: Walkabout & Double Feat title (" .. tostring(ts.title._text) .. ")")
  ns.Queue.remove(Q, W.id)
  ns.Queue.remove(Q, F.id)
  local F1 = addFeat()
  ns.UI.Toast:Show(nil, F1, "tick")
  check(ts.title._text == "Feat of Strength!" and not ts.sub._shown and ts.glowKind == "gold",
    "toast: a normal Feat keeps the gold glow, title and no subtitle")
  ns.Queue.remove(Q, F1.id)

  -- the ENRAGED! moment: chat line always; center text and sound only when the game is not busy
  local center = function() return _G.StrongLikeTaurenCenterText end
  ns.db.settings.nudge.center = false
  ns.db.settings.nudge.sound = true
  local D = { id = 99, k = "F", double = true, slots = {} }
  stub.chat = {}
  plays, lastSound = 0, nil
  ns.ctx.settleUntil = 0
  ns.dispatch({ { t = "enraged", item = D } })
  check(#stub.chat >= 1, "enraged: prints an explanatory chat line")
  check(center() and center()._shown and center().fs._text == "ENRAGED!", "enraged: center text even with center text off")
  check(center().color and center().color[1] >= 0.9 and center().color[3] <= 0.2, "enraged: red-orange center text")
  check(plays == 1 and lastSound == ids.RAID_WARNING, "enraged: war-horn sound (RAID_WARNING)")
  center()._shown = false
  center().fs._text = ""
  ns.ctx.combat = true
  stub.chat = {}
  plays = 0
  ns.dispatch({ { t = "enraged", item = D } })
  check(#stub.chat >= 1, "enraged in combat: chat line still printed")
  check(not center()._shown and center().fs._text == "" and plays == 0, "enraged in combat: no center text, no sound")
  ns.ctx.combat = false
  ns.db.settings.nudge.sound = false
  plays = 0
  ns.dispatch({ { t = "enraged", item = D } })
  check(plays == 0 and center()._shown, "enraged with sounds off: banner but no sound")
  ns.db.settings.nudge.sound = true
  _G.SOUNDKIT.RAID_WARNING = nil
  plays, lastSound = 0, nil
  ns.dispatch({ { t = "enraged", item = D } })
  check(plays == 1 and lastSound == ids.READY_CHECK, "enraged: falls back to READY_CHECK when nothing better exists")
  setKit()

  -- Scheduler -> dispatch: only a Double Feat enrages
  boot(); setKit()
  stub.chat = {}
  ns.db.body.rage.v = 100
  ns.db.body.rage.lastFeatAt = 0
  ns.ctx.settleUntil = 0
  ns.dispatch(ns.Scheduler.tick(ns.db, ns.now() + 15, ns.ctx, ns.env))
  check(ns.Queue.get(ns.db.queue, "F") and not ns.Queue.get(ns.db.queue, "F").double, "normal Feat earned at 100")
  check(not (center() and center()._shown and center().fs._text == "ENRAGED!" and ns.db.prog.enraged > 0),
    "no ENRAGED! for a normal Feat")
end

print(("ui-tests: %d passed, %d failed"):format(passed, failed))
print(failed == 0 and "UI TESTS OK" or ("UI TESTS: " .. failed .. " failure(s)"))
os.exit(failed == 0 and 0 or 1)
