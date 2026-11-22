-- Offline runner: luajit tools/run-tests.lua  (from anywhere)
local script = arg and arg[0] or "tools/run-tests.lua"
local dir = script:gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local root = dir .. "/.."
local ADDON = "StrongLikeTauren"

local files = {}
for line in io.lines(root .. "/" .. ADDON .. ".toc") do
  line = line:gsub("\r", "")
  if line ~= "" and not line:find("^%s*##") and not line:find("^%s*#") then
    files[#files + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""))
  end
end

local fails, pending = 0, 0
local present = {}
for _, f in ipairs(files) do
  local path = root .. "/" .. f:gsub("\\", "/")
  local fh = io.open(path, "rb")
  if not fh then
    pending = pending + 1
    print("pending  " .. f)
  else
    fh:close()
    local fn, err = loadfile(path)
    if not fn then
      fails = fails + 1
      print("SYNTAX   " .. f .. ": " .. tostring(err))
    else
      present[#present + 1] = { f = f, path = path, fn = fn }
    end
  end
end
print(("syntax: %d ok, %d pending, %d broken"):format(#present, pending, fails))

local pure = { "Locales/", "Core/Util.lua", "Core/Const.lua", "Data/", "Logic/", "Store/DB.lua",
               "Test/SelfTest.lua", "Test/Sim.lua" }
local function isPure(f)
  f = f:gsub("\\", "/")
  for _, p in ipairs(pure) do
    if f:sub(1, #p) == p then return true end
  end
  return false
end

local ns = {}
for _, e in ipairs(present) do
  if isPure(e.f) then
    local ok, err = pcall(e.fn, ADDON, ns)
    if not ok then
      fails = fails + 1
      print("LOADERR  " .. e.f .. ": " .. tostring(err))
    end
  end
end

if ns.SelfTest then
  local p, f = ns.SelfTest.run(print)
  print(("selftest: %d passed, %d failed"):format(p, f))
  fails = fails + f
else
  fails = fails + 1
  print("FAIL no ns.SelfTest")
end

if ns.Sim then
  local p, f = ns.Sim.runAll(print)
  print(("sim: %d passed, %d failed"):format(p, f))
  fails = fails + f
else
  pending = pending + 1
  print("pending  ns.Sim not loaded")
end

print(fails == 0 and "ALL OK" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
