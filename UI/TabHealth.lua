local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local Kit = UI.Kit
local COL = Kit.COL

local Health = { title = L["Health"] }
UI.Tabs.health = Health

function Health.build(parent)
  local root = CreateFrame("Frame", nil, parent)
  local scroll, content = Kit.scroll(root, 616, 418)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  local flow = Kit.flow(content, 588)
  local H = ns.D.HEALTH

  flow:header(L["How it works"])
  for _, p in ipairs(H.pitch) do flow:note(p, 0, "GameFontHighlight", COL.text) end

  for _, s in ipairs(H.why) do
    flow:header(s.head)
    flow:note(s.body, 0, "GameFontHighlight", COL.text)
  end

  flow:header(L["Sources"])
  for _, s in ipairs(H.sources) do flow:note("- " .. s, 8) end

  flow:header(L["Disclaimer"])
  flow:note(H.disclaimer, 0, "GameFontHighlight", COL.amber)
  flow:finish()
  return root
end

function Health.refresh() end
