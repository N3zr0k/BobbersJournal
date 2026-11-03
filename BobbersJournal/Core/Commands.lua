local _, ns = ...
local BJ = ns.BJ
-- Few slash commands on purpose. /bob toggles the journal, /bob options opens the settings,
-- /bob probe prints what the client reports about the fishing skill (for bug reports), /bob export lists item data to copy.
SLASH_BOBBERSJOURNAL1 = "/bob"

local function probe()
  local Skill = ns.Skill
  local rank, max, mod = Skill.Info() -- nothing when the character has not learned fishing
  BJ:Print(format("flavor %s, skill %s/%s (+%s)", tostring(ns.Flavor.current), tostring(rank), tostring(max), tostring(mod)))
  -- where the player stands, as the game reports it: sub zone text, and (if the client has the functions) the IDs of the
  -- explored areas at the position with their names. Shows whether an area ID can replace the sub zone name.
  BJ:Print(format("zone text %s | sub zone text %s | minimap text %s", tostring(GetZoneText and GetZoneText()), tostring(GetSubZoneText and GetSubZoneText()), tostring(GetMinimapZoneText and GetMinimapZoneText())))
  local explore = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
  local areaName = C_Map and C_Map.GetAreaInfo
  local mapID = C_Map and C_Map.GetBestMapForUnit and BJ.Clean(C_Map.GetBestMapForUnit("player"))
  BJ:Print(format("area functions: GetExploredAreaIDsAtPosition %s, GetAreaInfo %s, map %s", tostring(explore ~= nil), tostring(areaName ~= nil), tostring(mapID)))
  if explore and mapID and C_Map.GetPlayerMapPosition then
    local ok, ids = pcall(function()
      local pos = C_Map.GetPlayerMapPosition(mapID, "player")
      return pos and explore(mapID, pos)
    end)
    if ok and type(ids) == "table" then
      local parts = {}
      for _, id in ipairs(ids) do
        local nameOk, name = pcall(areaName, id)
        parts[#parts + 1] = format("%s = %s", tostring(id), nameOk and tostring(name) or "?")
      end
      BJ:Print(format("explored areas here: %d  %s", #ids, table.concat(parts, "  |  ")))
    else
      BJ:Print("explored areas here: none (" .. tostring(ok and "no result" or ids) .. ")")
    end
  end
  for _, e in ipairs(Skill.RetailLines() or {}) do
    BJ:Print(format("line %s [%s] id %s: %s/%s (+%s)", tostring(e.expansion), tostring(e.name), tostring(e.id), tostring(e.rank), tostring(e.max), tostring(e.modifier)))
  end
  -- raw view of the client's skill line list (why RetailLines may be empty)
  if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines then
    local ok, ids = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    ids = ok and type(ids) == "table" and ids or {}
    BJ:Print("skill lines from the client: " .. #ids)
    local shown, tables, named, sample = 0, 0, 0, 0
    for _, id in ipairs(ids) do
      local ok2, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
      if ok2 and type(info) == "table" then
        tables = tables + 1
        local nm = BJ.Clean(info.professionName)
        if type(nm) == "string" and nm ~= "" then named = named + 1 end
        if sample < 4 then
          sample = sample + 1
          BJ:Print(format("sample %s: name %s | profession %s | parent %s | skill %s/%s", tostring(id), tostring(nm), tostring(info.profession),
            tostring(info.parentProfessionID), tostring(BJ.Clean(info.skillLevel)), tostring(BJ.Clean(info.maxSkillLevel))))
        end
      end
      if ok2 and Skill.IsFishingLine(info) then
        shown = shown + 1
        BJ:Print(format("raw %s: %s | %s | profession %s | parent %s | %s/%s", tostring(id), tostring(BJ.Clean(info.professionName)), tostring(BJ.Clean(info.expansionName)),
          tostring(info.profession), tostring(info.parentProfessionID), tostring(BJ.Clean(info.skillLevel)), tostring(BJ.Clean(info.maxSkillLevel))))
      end
    end
    BJ:Print(format("infos: %d tables, %d with a name; fishing lines in it: %d", tables, named, shown))
  end
  local childFn = C_TradeSkillUI and C_TradeSkillUI.GetChildProfessionInfos
  if childFn then
    local ok, infos = pcall(childFn)
    BJ:Print("child profession infos: " .. (ok and type(infos) == "table" and #infos or "none"))
  end
  -- zone to skill line assignment used by the tooltip and the skill bar
  local zone = ns.Zone.Key()
  local T = BJ.modules.Tooltip
  local lv = T and T.ZoneLevel and T.ZoneLevel(zone)
  local line = lv and Skill.RetailLineForLevel(lv)
  BJ:Print(format("zone %s: expansion level %s, skill line %s", tostring(zone), tostring(lv), line and tostring(line.name or line.expansion) or "none"))
  local stats, base, bonus = Skill.RetailStats()
  BJ:Print(format("gathering: base %s, bonus %s, %d stats", tostring(base), tostring(bonus), stats and #stats or 0))
  for _, s in ipairs(stats or {}) do BJ:Print(format("stat %s = %s (%s %%)", tostring(s.name), tostring(s.value), tostring(s.pct))) end
  local npcs = BJ.API.GetNPCs(ns.Flavor.current)
  local trainers = 0
  for _, n in ipairs(npcs) do if n.trainer then trainers = trainers + 1 end end
  local P = BJ.modules.Pins
  BJ:Print(format("vendors/teachers saved: %d (%d teachers), pins option %s, world map provider %s", #npcs, trainers, tostring(BJ.settings.npcPins), tostring(P and P.HasProvider and P.HasProvider())))
  for _, n in ipairs(npcs) do
    BJ:Print(format("npc %s %s: map %s, %s / %s%s", tostring(n.id), tostring(n.name), tostring(n.map), tostring(n.x and n.x * 100), tostring(n.y and n.y * 100), n.trainer and " (teacher)" or ""))
  end
  local D = BJ.modules.Diary
  if D and D.Probe then BJ:Print(D.Probe()) end
  if BJ.lastError then BJ:Print("last error: " .. BJ.lastError) end
end

SlashCmdList["BOBBERSJOURNAL"] = function(msg)
  msg = msg and msg:lower() or ""
  if msg:find("^opt") then BJ:OpenOptions()
  elseif msg:find("^probe") then probe()
  elseif msg:find("^export") then ns.Export.Open()
  else BJ.modules.Journal.Toggle() end
end
