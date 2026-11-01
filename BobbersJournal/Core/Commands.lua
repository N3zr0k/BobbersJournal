local _, ns = ...
local BJ = ns.BJ
-- Few slash commands on purpose. /bob toggles the journal, /bob options opens the settings,
-- /bob probe prints what the client reports about the fishing skill (for bug reports).
SLASH_BOBBERSJOURNAL1 = "/bob"

local function probe()
  local Skill = ns.Skill
  BJ:Print("flavor " .. ns.Flavor.current .. ", skill " .. tostring(Skill.Info()))
  for _, e in ipairs(Skill.RetailLines() or {}) do
    BJ:Print(format("line %s: %s/%s (+%s)", tostring(e.expansion), tostring(e.rank), tostring(e.max), tostring(e.modifier)))
  end
  local stats, base, bonus = Skill.RetailStats()
  BJ:Print(format("gathering: base %s, bonus %s, %d stats", tostring(base), tostring(bonus), stats and #stats or 0))
  for _, s in ipairs(stats or {}) do BJ:Print(format("stat %s = %s (%s %%)", tostring(s.name), tostring(s.value), tostring(s.pct))) end
  if BJ.lastError then BJ:Print("last error: " .. BJ.lastError) end
end

SlashCmdList["BOBBERSJOURNAL"] = function(msg)
  msg = msg and msg:lower() or ""
  if msg:find("^opt") then BJ:OpenOptions()
  elseif msg:find("^probe") then probe()
  else BJ.modules.Journal.Toggle() end
end
