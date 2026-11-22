-- Load smoke test for the whole addon under a fake WoW API: luajit tools/smoke.lua
local script = arg and arg[0] or "tools/smoke.lua"
local dir = script:gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local root = dir .. "/.."
local ADDON = "StrongLikeTauren"

local stub = dofile(dir .. "/wowstub.lua")
local ns = {}
local errors = 0

local function trace(e) return debug.traceback(tostring(e), 2) end
local function try(label, fn, ...)
  local ok, err = xpcall(fn, trace, ...)
  if not ok then
    errors = errors + 1
    print("ERROR in " .. label .. ":\n    " .. tostring(err):gsub("\n", "\n    "))
  end
  return ok
end

-- Load every TOC file in order.
local loaded, skipped = 0, {}
for line in io.lines(root .. "/" .. ADDON .. ".toc") do
  line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if line ~= "" and line:sub(1, 1) ~= "#" then
    local path = root .. "/" .. line:gsub("\\", "/")
    local fh = io.open(path, "rb")
    if not fh then
      skipped[#skipped + 1] = line
    else
      fh:close()
      local fn, err = loadfile(path)
      if not fn then
        errors = errors + 1
        print("SYNTAX " .. line .. ": " .. tostring(err))
      elseif try("load " .. line, fn, ADDON, ns) then
        loaded = loaded + 1
      end
    end
  end
end
print(("loaded %d files; skipped (missing): %s"):format(loaded, #skipped > 0 and table.concat(skipped, ", ") or "none"))

-- Fire events at every frame that registered them.
local function fire(event, ...)
  local n = 0
  for _, f in ipairs({ unpack(stub.frames) }) do
    local h = f._scripts.OnEvent
    if h and (f._events[event] or f._all) then
      n = n + 1
      try(("%s handler on %s"):format(event, f._name or f._kind), h, f, event, ...)
    end
  end
  print(("  %s -> %d frame(s)"):format(event, n))
end
fire("ADDON_LOADED", ADDON)
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)

-- Recorded timers: run each pending callback once (callbacks queued meanwhile run in the next round, bounded).
local ran = 0
for _ = 1, 5 do
  local batch = stub.timers
  stub.timers = {}
  if #batch == 0 then break end
  for _, t in ipairs(batch) do
    if not t.cancelled then
      ran = ran + 1
      try("timer (" .. t.kind .. " " .. tostring(t.sec) .. "s)", t.fn, t)
    end
  end
end
print("timers run: " .. ran)

-- OnUpdate handlers once.
local upd = 0
for _, f in ipairs({ unpack(stub.frames) }) do
  local h = f._scripts.OnUpdate
  if h then
    upd = upd + 1
    try("OnUpdate on " .. (f._name or f._kind), h, f, 0.1)
  end
end
print("OnUpdate handlers run: " .. upd)

-- Slash commands.
local handler
for key, fn in pairs(_G.SlashCmdList) do
  local s1 = rawget(_G, "SLASH_" .. key .. "1")
  if s1 == "/tauren" or s1 == "/slt" then handler = fn end
end
if not handler then
  print("no /tauren slash handler registered (yet)")
else
  for _, msg in ipairs({ "help", "selftest", "sim all", "stats", "" }) do
    print("/tauren " .. msg)
    try("/tauren " .. msg, handler, msg)
  end
end

local unknown = {}
for k in pairs(stub.unknown) do unknown[#unknown + 1] = k end
table.sort(unknown)
if #unknown > 0 then print("unknown globals read (maybe missing from wowstub): " .. table.concat(unknown, ", ")) end

print(errors == 0 and "SMOKE OK" or ("SMOKE: " .. errors .. " error(s)"))
os.exit(errors == 0 and 0 or 1)
